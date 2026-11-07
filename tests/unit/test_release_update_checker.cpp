// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#include "kdockw.h"
#include "update/releaseupdatechecker.h"

#include <catch2/catch_test_macros.hpp>

#include <KSharedConfig>

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QFile>
#include <QTemporaryDir>
#include <QTcpServer>
#include <QTcpSocket>
#include <QSignalSpy>
#include <QtTest/QTest>

#include <functional>

using namespace std::chrono_literals;

namespace
{

QJsonObject release(const QString &version, bool draft = false, bool prerelease = false, QString url = {})
{
    if (url.isEmpty()) {
        url = kdockw::canonicalReleaseUrl(version).toString();
    }
    return {
        {QStringLiteral("tag_name"), QStringLiteral("kdockw-v%1").arg(version)},
        {QStringLiteral("draft"), draft},
        {QStringLiteral("prerelease"), prerelease},
        {QStringLiteral("html_url"), url},
    };
}

class TemporarySettings
{
public:
    TemporarySettings()
        : config(KSharedConfig::openConfig(directory.filePath(QStringLiteral("kdockwrc")), KConfig::SimpleConfig))
    {
        settings.setSharedConfig(config);
        settings.load();
    }

    QTemporaryDir directory;
    KSharedConfig::Ptr config;
    KDockWSettings settings;
};

class LocalApi final : public QObject
{
public:
    using Response = std::function<QByteArray(const QByteArray &request, int requestIndex)>;

    LocalApi()
    {
        QObject::connect(&server, &QTcpServer::newConnection, this, [this] {
            while (QTcpSocket *socket = server.nextPendingConnection()) {
                QObject::connect(socket, &QTcpSocket::readyRead, socket, [this, socket] {
                    auto &buffer = buffers[socket];
                    buffer.append(socket->readAll());
                    if (!buffer.contains(QByteArrayLiteral("\r\n\r\n"))) {
                        return;
                    }
                    const QByteArray response = responseFactory ? responseFactory(buffer, requestCount++) : QByteArray{};
                    if (!response.isEmpty()) {
                        socket->write(response);
                        socket->flush();
                    }
                    buffers.remove(socket);
                    QObject::connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
                    if (!response.isEmpty()) {
                        socket->disconnectFromHost();
                    }
                });
            }
        });
        REQUIRE(server.listen(QHostAddress::LocalHost));
    }

    QUrl url() const
    {
        return QUrl(QStringLiteral("http://127.0.0.1:%1/repos/thicking/kdockw/releases").arg(server.serverPort()));
    }

    static QByteArray httpResponse(int status, const QByteArray &body = {}, const QList<QPair<QByteArray, QByteArray>> &headers = {})
    {
        const QByteArray reason = status == 200 ? QByteArrayLiteral("OK")
            : status == 304                         ? QByteArrayLiteral("Not Modified")
            : status == 403                         ? QByteArrayLiteral("Forbidden")
            : status == 429                         ? QByteArrayLiteral("Too Many Requests")
                                                  : QByteArrayLiteral("Error");
        QByteArray response = QByteArrayLiteral("HTTP/1.1 ") + QByteArray::number(status) + ' ' + reason + QByteArrayLiteral("\r\n");
        response += QByteArrayLiteral("Content-Type: application/json\r\nContent-Length: ") + QByteArray::number(body.size()) + QByteArrayLiteral("\r\nConnection: close\r\n");
        for (const auto &[name, value] : headers) {
            response += name + QByteArrayLiteral(": ") + value + QByteArrayLiteral("\r\n");
        }
        response += QByteArrayLiteral("\r\n") + body;
        return response;
    }

    QTcpServer server;
    Response responseFactory;
    int requestCount = 0;

private:
    QHash<QTcpSocket *, QByteArray> buffers;
};

QByteArray jsonArray(const QJsonArray &array)
{
    return QJsonDocument(array).toJson(QJsonDocument::Compact);
}

#ifdef KDOCKW_DIAGNOSTIC_BUILD
QByteArray requestHeader(const QByteArray &request, const QByteArray &name)
{
    const QList<QByteArray> lines = request.split('\n');
    for (const QByteArray &line : lines) {
        const qsizetype separator = line.indexOf(':');
        if (separator > 0 && line.first(separator).trimmed().compare(name, Qt::CaseInsensitive) == 0) {
            return line.mid(separator + 1).trimmed();
        }
    }
    return {};
}
#endif

} // namespace

TEST_CASE("Release versions are compared numerically and recognize development builds", "[updates][version]")
{
    CHECK(kdockw::compareVersions(QStringLiteral("0.3.1"), QStringLiteral("0.3.0")) == 1);
    CHECK(kdockw::compareVersions(QStringLiteral("0.4.0"), QStringLiteral("0.3.9")) == 1);
    CHECK(kdockw::compareVersions(QStringLiteral("1.0.0"), QStringLiteral("0.99.99")) == 1);
    CHECK(kdockw::compareVersions(QStringLiteral("0.3.0"), QStringLiteral("0.3.0")) == 0);
    CHECK(kdockw::compareVersions(QStringLiteral("0.3.0"), QStringLiteral("0.3.0-dev")) == 1);
    CHECK(kdockw::compareVersions(QStringLiteral("0.3.0-dev"), QStringLiteral("0.3.0")) == -1);
    CHECK_FALSE(kdockw::compareVersions(QStringLiteral("0.3"), QStringLiteral("0.3.0")));
    CHECK_FALSE(kdockw::isValidInstalledVersion(QStringLiteral("01.2.3")));
    CHECK(kdockw::isValidInstalledVersion(QStringLiteral("0.3.0-dev")));
    CHECK(kdockw::canonicalReleaseUrl(QStringLiteral("0.3.0-dev")).isEmpty());
}

TEST_CASE("Release catalog filters tags and chooses the greatest stable version", "[updates][catalog]")
{
    const QByteArray body = jsonArray({
        release(QStringLiteral("1.0.0")),
        QJsonObject{{QStringLiteral("tag_name"), QStringLiteral("v0.12.0")}}, // Historical Krema tag.
        release(QStringLiteral("0.4.0"), false, true),
        release(QStringLiteral("0.9.0"), true, false),
        release(QStringLiteral("0.3.1")),
    });
    const auto result = kdockw::parseReleaseCatalog(body);
    REQUIRE(result.valid);
    REQUIRE(result.latest);
    CHECK(result.latest->version == QLatin1String("1.0.0"));
    CHECK(result.latest->url == kdockw::canonicalReleaseUrl(QStringLiteral("1.0.0")));
}

TEST_CASE("Release catalog accepts empty results and rejects malformed KDockW records", "[updates][catalog]")
{
    CHECK(kdockw::parseReleaseCatalog(QByteArrayLiteral("[]")).valid);
    const auto malformedJson = kdockw::parseReleaseCatalog(QByteArrayLiteral("{"));
    CHECK_FALSE(malformedJson.valid);
    const auto malformedRelease = kdockw::parseReleaseCatalog(jsonArray({release(QStringLiteral("0.3.1"), false, false, QStringLiteral("https://evil.example/release"))}));
    CHECK_FALSE(malformedRelease.valid);
    const auto missingFields = kdockw::parseReleaseCatalog(QByteArrayLiteral(R"([{"tag_name":"kdockw-v0.3.1"}])"));
    CHECK_FALSE(missingFields.valid);
}

TEST_CASE("Update checker handles GitHub HTTP response, ETag cache, and notification deduplication", "[updates][http]")
{
    TemporarySettings config;
    LocalApi api;
    const QByteArray catalog = jsonArray({release(QStringLiteral("0.3.1")), release(QStringLiteral("0.3.0"))});
    api.responseFactory = [&catalog](const QByteArray &request, int index) {
        if (index == 0) {
            CHECK_FALSE(request.contains(QByteArrayLiteral("Authorization:")));
            return LocalApi::httpResponse(200, catalog, {{QByteArrayLiteral("ETag"), QByteArrayLiteral("\"v3\"")}});
        }
        CHECK(request.contains(QByteArrayLiteral("If-None-Match: \"v3\"")));
        return LocalApi::httpResponse(304);
    };

    kdockw::ReleaseUpdateChecker checker(&config.settings, QStringLiteral("0.3.0"), api.url());
    QSignalSpy notificationSpy(&checker, &kdockw::ReleaseUpdateChecker::newReleaseAvailable);
    checker.checkManually();
    QTRY_COMPARE_WITH_TIMEOUT(checker.status(), kdockw::ReleaseUpdateChecker::UpdateAvailable, 5000);
    CHECK(checker.latestReleaseVersion() == QLatin1String("0.3.1"));
    CHECK(checker.updateAvailable());
    CHECK(checker.latestReleaseUrl() == kdockw::canonicalReleaseUrl(QStringLiteral("0.3.1")));
    CHECK(config.settings.releasesApiETag() == QLatin1String("\"v3\""));
    CHECK(notificationSpy.count() == 1);

    checker.checkManually();
    QTRY_COMPARE_WITH_TIMEOUT(api.requestCount, 2, 5000);
    QTRY_COMPARE_WITH_TIMEOUT(checker.status(), kdockw::ReleaseUpdateChecker::UpdateAvailable, 5000);
    CHECK(notificationSpy.count() == 1);
    CHECK_FALSE(checker.lastSuccessfulCheck().isEmpty());

    KDockWSettings restarted;
    restarted.setSharedConfig(KSharedConfig::openConfig(config.directory.filePath(QStringLiteral("kdockwrc")), KConfig::SimpleConfig));
    restarted.load();
    CHECK(restarted.cachedReleaseVersion() == QLatin1String("0.3.1"));
    CHECK(restarted.cachedReleaseUrl() == kdockw::canonicalReleaseUrl(QStringLiteral("0.3.1")).toString(QUrl::FullyEncoded));
    CHECK(restarted.releasesApiETag() == QLatin1String("\"v3\""));
    CHECK_FALSE(restarted.lastSuccessfulUpdateCheck().isEmpty());
    CHECK(restarted.lastNotifiedReleaseVersion() == QLatin1String("0.3.1"));
    kdockw::ReleaseUpdateChecker afterRestart(&restarted, QStringLiteral("0.3.0"), api.url());
    CHECK(afterRestart.status() == kdockw::ReleaseUpdateChecker::UpdateAvailable);
    QSignalSpy afterRestartNotification(&afterRestart, &kdockw::ReleaseUpdateChecker::newReleaseAvailable);
    afterRestart.checkAutomaticallyIfDue();
    CHECK(afterRestartNotification.count() == 0);
}

TEST_CASE("Update checker does not offer an equal or older stable version", "[updates][version][http]")
{
    for (const QString &availableVersion : {QStringLiteral("0.3.0"), QStringLiteral("0.2.9")}) {
        TemporarySettings config;
        LocalApi api;
        api.responseFactory = [availableVersion](const QByteArray &, int) {
            return LocalApi::httpResponse(200, jsonArray({release(availableVersion)}));
        };
        kdockw::ReleaseUpdateChecker checker(&config.settings, QStringLiteral("0.3.0"), api.url());
        checker.checkManually();
        QTRY_COMPARE_WITH_TIMEOUT(checker.status(), kdockw::ReleaseUpdateChecker::UpToDate, 5000);
        CHECK_FALSE(checker.updateAvailable());
    }
}

TEST_CASE("Update checker stores 429 backoff and does not send another request before Retry-After", "[updates][http]")
{
    TemporarySettings config;
    LocalApi api;
    api.responseFactory = [](const QByteArray &, int) {
        return LocalApi::httpResponse(429, QByteArrayLiteral("{}"), {{QByteArrayLiteral("Retry-After"), QByteArrayLiteral("60")} });
    };

    kdockw::ReleaseUpdateChecker checker(&config.settings, QStringLiteral("0.3.0"), api.url());
    checker.checkManually();
    QTRY_COMPARE_WITH_TIMEOUT(checker.status(), kdockw::ReleaseUpdateChecker::Failed, 5000);
    CHECK_FALSE(config.settings.releaseApiRetryAfter().isEmpty());
    checker.checkManually();
    QTest::qWait(100);
    CHECK(api.requestCount == 1);
}

TEST_CASE("Update checker backs off after a rate-limited 403 response", "[updates][http]")
{
    TemporarySettings config;
    LocalApi api;
    api.responseFactory = [](const QByteArray &, int) {
        const qint64 reset = QDateTime::currentDateTimeUtc().toSecsSinceEpoch() + 60;
        return LocalApi::httpResponse(403, QByteArrayLiteral("{}"), {{QByteArrayLiteral("X-RateLimit-Reset"), QByteArray::number(reset)}});
    };

    kdockw::ReleaseUpdateChecker checker(&config.settings, QStringLiteral("0.3.0"), api.url());
    checker.checkManually();
    QTRY_COMPARE_WITH_TIMEOUT(checker.status(), kdockw::ReleaseUpdateChecker::Failed, 5000);
    CHECK_FALSE(config.settings.releaseApiRetryAfter().isEmpty());
    checker.checkManually();
    QTest::qWait(100);
    CHECK(api.requestCount == 1);
}

TEST_CASE("Update checker throttles automatic checks but keeps manual checks available", "[updates][settings]")
{
    TemporarySettings config;
    LocalApi api;
    api.responseFactory = [](const QByteArray &, int) { return LocalApi::httpResponse(200, QByteArrayLiteral("[]")); };
    config.settings.setLastAutomaticUpdateAttempt(QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs));
    config.settings.save();

    kdockw::ReleaseUpdateChecker checker(&config.settings, QStringLiteral("0.3.0"), api.url());
    checker.checkAutomaticallyIfDue();
    QTest::qWait(50);
    CHECK(api.requestCount == 0);

    checker.setAutomaticChecksEnabled(false);
    CHECK_FALSE(checker.automaticChecksEnabled());
    checker.checkManually();
    QTRY_COMPARE_WITH_TIMEOUT(checker.status(), kdockw::ReleaseUpdateChecker::UpToDate, 5000);
    CHECK(api.requestCount == 1);

    KDockWSettings restarted;
    restarted.setSharedConfig(KSharedConfig::openConfig(config.directory.filePath(QStringLiteral("kdockwrc")), KConfig::SimpleConfig));
    restarted.load();
    CHECK_FALSE(restarted.checkForUpdatesAutomatically());
    CHECK_FALSE(restarted.lastSuccessfulUpdateCheck().isEmpty());
}

TEST_CASE("Notification preference suppresses then announces a cached release once", "[updates][notifications]")
{
    TemporarySettings config;
    LocalApi api;
    api.responseFactory = [](const QByteArray &, int) {
        return LocalApi::httpResponse(200, jsonArray({release(QStringLiteral("0.3.1"))}));
    };
    config.settings.setNotifyAboutUpdates(false);
    kdockw::ReleaseUpdateChecker checker(&config.settings, QStringLiteral("0.3.0"), api.url());
    QSignalSpy notificationSpy(&checker, &kdockw::ReleaseUpdateChecker::newReleaseAvailable);

    checker.checkManually();
    QTRY_COMPARE_WITH_TIMEOUT(checker.status(), kdockw::ReleaseUpdateChecker::UpdateAvailable, 5000);
    CHECK(notificationSpy.count() == 0);
    CHECK(config.settings.lastNotifiedReleaseVersion().isEmpty());

    checker.setNotificationsEnabled(true);
    CHECK(notificationSpy.count() == 1);
    CHECK(config.settings.lastNotifiedReleaseVersion() == QLatin1String("0.3.1"));
    checker.checkManually();
    QTRY_COMPARE_WITH_TIMEOUT(api.requestCount, 2, 5000);
    CHECK(notificationSpy.count() == 1);
}

TEST_CASE("Update checker announces a later release once after the previous version", "[updates][notifications]")
{
    TemporarySettings config;
    LocalApi api;
    api.responseFactory = [](const QByteArray &, int index) {
        const QString version = index == 0 ? QStringLiteral("0.3.1") : QStringLiteral("0.3.2");
        return LocalApi::httpResponse(200, jsonArray({release(version)}));
    };
    kdockw::ReleaseUpdateChecker checker(&config.settings, QStringLiteral("0.3.0"), api.url());
    QSignalSpy notificationSpy(&checker, &kdockw::ReleaseUpdateChecker::newReleaseAvailable);

    checker.checkManually();
    QTRY_COMPARE_WITH_TIMEOUT(checker.latestReleaseVersion(), QStringLiteral("0.3.1"), 5000);
    CHECK(notificationSpy.count() == 1);
    checker.checkManually();
    QTRY_COMPARE_WITH_TIMEOUT(checker.latestReleaseVersion(), QStringLiteral("0.3.2"), 5000);
    CHECK(notificationSpy.count() == 2);
    CHECK(config.settings.lastNotifiedReleaseVersion() == QLatin1String("0.3.2"));
}

TEST_CASE("Update checker reports API failures without treating them as successful checks", "[updates][http]")
{
    TemporarySettings config;
    LocalApi api;
    api.responseFactory = [](const QByteArray &, int) { return LocalApi::httpResponse(200, QByteArrayLiteral("not json")); };
    kdockw::ReleaseUpdateChecker checker(&config.settings, QStringLiteral("0.3.0"), api.url());
    checker.checkManually();
    QTRY_COMPARE_WITH_TIMEOUT(checker.status(), kdockw::ReleaseUpdateChecker::Failed, 5000);
    CHECK(config.settings.lastSuccessfulUpdateCheck().isEmpty());
}

TEST_CASE("Update checker times out and safely cancels an outstanding request", "[updates][http]")
{
    TemporarySettings config;
    LocalApi api;
    api.responseFactory = [](const QByteArray &, int) { return QByteArray{}; };
    auto checker = std::make_unique<kdockw::ReleaseUpdateChecker>(&config.settings, QStringLiteral("0.3.0"), api.url(), nullptr, 100);
    checker->checkManually();
    QTRY_COMPARE_WITH_TIMEOUT(checker->status(), kdockw::ReleaseUpdateChecker::Failed, 3000);
    checker->checkManually();
    CHECK(checker->checking());
    checker.reset(); // The pending QNetworkReply is aborted with the checker.
    QTest::qWait(50);
}

TEST_CASE("Update checker bounds response size", "[updates][http]")
{
    TemporarySettings config;
    LocalApi api;
    const QByteArray oversized(1024 * 1024 + 64, ' ');
    api.responseFactory = [&oversized](const QByteArray &, int) { return LocalApi::httpResponse(200, oversized); };
    kdockw::ReleaseUpdateChecker checker(&config.settings, QStringLiteral("0.3.0"), api.url());
    checker.checkManually();
    QTRY_COMPARE_WITH_TIMEOUT(checker.status(), kdockw::ReleaseUpdateChecker::Failed, 5000);
    CHECK(config.settings.lastSuccessfulUpdateCheck().isEmpty());
}

TEST_CASE("Diagnostic update mock selects 0.3.1 and 0.3.2 and records the safe release action", "[updates][diagnostic]")
{
#ifdef KDOCKW_DIAGNOSTIC_BUILD
    TemporarySettings config;
    QTemporaryDir logDirectory;
    REQUIRE(logDirectory.isValid());
    const QString openLogPath = logDirectory.filePath(QStringLiteral("opened-release-urls.log"));
    LocalApi api;
    api.responseFactory = [](const QByteArray &request, int) {
        const QString version = QString::fromLatin1(requestHeader(request, QByteArrayLiteral("X-KDockW-Diagnostic-Release")));
        if (version != QLatin1String("0.3.1") && version != QLatin1String("0.3.2")) {
            return LocalApi::httpResponse(400);
        }
        const QByteArray etag = '"' + QByteArrayLiteral("mock-") + version.toUtf8() + '"';
        if (requestHeader(request, QByteArrayLiteral("If-None-Match")) == etag) {
            return LocalApi::httpResponse(304, {}, {{QByteArrayLiteral("ETag"), etag}});
        }
        return LocalApi::httpResponse(200, jsonArray({release(version)}), {{QByteArrayLiteral("ETag"), etag}});
    };

    kdockw::ReleaseUpdateChecker checker(&config.settings, QStringLiteral("0.3.0"), api.url(), nullptr, 5000, true, openLogPath);
    QSignalSpy notificationSpy(&checker, &kdockw::ReleaseUpdateChecker::newReleaseAvailable);
    CHECK(checker.diagnosticMode());
    CHECK(checker.diagnosticReleaseVersion() == QLatin1String("0.3.1"));

    checker.checkManually();
    QTRY_COMPARE_WITH_TIMEOUT(checker.latestReleaseVersion(), QStringLiteral("0.3.1"), 5000);
    CHECK(notificationSpy.count() == 1);
    checker.openReleasePage();
    QFile openedLog(openLogPath);
    REQUIRE(openedLog.open(QIODevice::ReadOnly | QIODevice::Text));
    CHECK(QString::fromUtf8(openedLog.readAll()).contains(QStringLiteral("https://github.com/thicking/kdockw/releases/tag/kdockw-v0.3.1")));
    openedLog.close();

    checker.checkManually();
    QTRY_COMPARE_WITH_TIMEOUT(api.requestCount, 2, 5000);
    CHECK(notificationSpy.count() == 1);

    checker.setDiagnosticReleaseVersion(QStringLiteral("0.3.2"));
    CHECK(checker.diagnosticReleaseVersion() == QLatin1String("0.3.2"));
    checker.checkManually();
    QTRY_COMPARE_WITH_TIMEOUT(checker.latestReleaseVersion(), QStringLiteral("0.3.2"), 5000);
    CHECK(notificationSpy.count() == 2);
    checker.openReleasePage();
    REQUIRE(openedLog.open(QIODevice::ReadOnly | QIODevice::Text));
    const QString lines = QString::fromUtf8(openedLog.readAll());
    CHECK(lines.count(QStringLiteral("https://github.com/thicking/kdockw/releases/tag/kdockw-v0.3.1")) == 1);
    CHECK(lines.count(QStringLiteral("https://github.com/thicking/kdockw/releases/tag/kdockw-v0.3.2")) == 1);
    checker.openReleasePageForVersion(QStringLiteral("0.3.2"), QUrl(QStringLiteral("https://example.org/")));
    CHECK(openedLog.size() == lines.toUtf8().size());

    KDockWSettings restarted;
    restarted.setSharedConfig(KSharedConfig::openConfig(config.directory.filePath(QStringLiteral("kdockwrc")), KConfig::SimpleConfig));
    restarted.load();
    CHECK(restarted.lastNotifiedReleaseVersion() == QLatin1String("0.3.2"));
    CHECK(restarted.releasesApiETag() == QLatin1String("\"mock-0.3.2\""));
#else
    TemporarySettings config;
    kdockw::ReleaseUpdateChecker checker(&config.settings, QStringLiteral("0.3.0"));
    CHECK_FALSE(checker.diagnosticMode());
#endif
}

TEST_CASE("Production update checker cannot enable diagnostic mock mode", "[updates][diagnostic]")
{
#ifndef KDOCKW_DIAGNOSTIC_BUILD
    TemporarySettings config;
    kdockw::ReleaseUpdateChecker checker(&config.settings);
    CHECK_FALSE(checker.diagnosticMode());
    checker.setDiagnosticReleaseVersion(QStringLiteral("0.3.2"));
    CHECK(checker.diagnosticReleaseVersion() == QLatin1String("0.3.1"));
#else
    SUCCEED("Diagnostic mock controls are compiled only into diagnostic builds");
#endif
}
