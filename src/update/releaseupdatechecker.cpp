// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#include "releaseupdatechecker.h"

#include "kdockw.h"

#include <KLocalizedString>

#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QLocale>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QTimeZone>

#include <array>

namespace kdockw
{
namespace
{

constexpr qsizetype kMaximumResponseSize = 1024 * 1024;
constexpr int kTransferTimeoutMs = 15000;
constexpr qint64 kAutomaticCheckIntervalSeconds = 24 * 60 * 60;
const QRegularExpression kVersionPattern(QStringLiteral(R"(^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-dev)?$)"));
const QRegularExpression kReleaseTagPattern(QStringLiteral(R"(^kdockw-v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$)"));

struct ParsedVersion {
    std::array<QString, 3> components;
    bool development = false;
};

std::optional<ParsedVersion> parseVersion(const QString &version)
{
    const auto match = kVersionPattern.match(version);
    if (!match.hasMatch()) {
        return std::nullopt;
    }
    return ParsedVersion{{match.captured(1), match.captured(2), match.captured(3)}, !match.captured(4).isEmpty()};
}

int compareNumericComponent(const QString &left, const QString &right)
{
    if (left.size() != right.size()) {
        return left.size() < right.size() ? -1 : 1;
    }
    const int lexical = QString::compare(left, right, Qt::CaseSensitive);
    return lexical < 0 ? -1 : (lexical > 0 ? 1 : 0);
}

bool isSafeApiEndpoint(const QUrl &url)
{
    if (url == ReleaseUpdateChecker::releasesApiUrl()) {
        return true;
    }
    // Loopback endpoints are accepted only so automated tests can exercise
    // the real asynchronous HTTP client without contacting an external host.
    return url.scheme() == QLatin1String("http") && (url.host() == QLatin1String("127.0.0.1") || url.host() == QLatin1String("::1"));
}

std::optional<QUrl> parseReleaseUrl(const QString &value, const QString &version)
{
    const QUrl url(value, QUrl::StrictMode);
    const QUrl expected = canonicalReleaseUrl(version);
    if (!url.isValid() || expected.isEmpty() || url != expected || !url.query().isEmpty() || !url.fragment().isEmpty()) {
        return std::nullopt;
    }
    return expected;
}

} // namespace

bool isValidInstalledVersion(const QString &version)
{
    return parseVersion(version).has_value();
}

std::optional<int> compareVersions(const QString &left, const QString &right)
{
    const auto lhs = parseVersion(left);
    const auto rhs = parseVersion(right);
    if (!lhs || !rhs) {
        return std::nullopt;
    }
    for (size_t i = 0; i < lhs->components.size(); ++i) {
        const int comparison = compareNumericComponent(lhs->components[i], rhs->components[i]);
        if (comparison != 0) {
            return comparison;
        }
    }
    if (lhs->development != rhs->development) {
        return lhs->development ? -1 : 1;
    }
    return 0;
}

QUrl canonicalReleaseUrl(const QString &version)
{
    if (!parseVersion(version) || version.endsWith(QLatin1String("-dev"))) {
        return {};
    }
    return QUrl(QStringLiteral("https://github.com/thicking/kdockw/releases/tag/kdockw-v%1").arg(version));
}

ReleaseCatalogResult parseReleaseCatalog(const QByteArray &json)
{
    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(json, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isArray()) {
        return {false, std::nullopt, QStringLiteral("Invalid JSON release catalog")};
    }

    std::optional<StableRelease> latest;
    for (const QJsonValue &value : document.array()) {
        if (!value.isObject()) {
            return {false, std::nullopt, QStringLiteral("Unexpected release entry")};
        }
        const QJsonObject object = value.toObject();
        const QString tag = object.value(QStringLiteral("tag_name")).toString();
        const auto tagMatch = kReleaseTagPattern.match(tag);
        if (!tagMatch.hasMatch()) {
            continue; // Historical Krema tags and unrelated repositories/releases.
        }

        const QJsonValue draftValue = object.value(QStringLiteral("draft"));
        const QJsonValue prereleaseValue = object.value(QStringLiteral("prerelease"));
        const QJsonValue htmlUrlValue = object.value(QStringLiteral("html_url"));
        if (!draftValue.isBool() || !prereleaseValue.isBool() || !htmlUrlValue.isString()) {
            return {false, std::nullopt, QStringLiteral("Release entry is missing required fields")};
        }
        if (draftValue.toBool() || prereleaseValue.toBool()) {
            continue;
        }

        const QString version = tag.mid(QStringLiteral("kdockw-v").size());
        const auto validatedUrl = parseReleaseUrl(htmlUrlValue.toString(), version);
        if (!validatedUrl) {
            return {false, std::nullopt, QStringLiteral("Release URL does not match the KDockW release tag")};
        }

        if (!latest || compareVersions(version, latest->version).value_or(-1) > 0) {
            latest = StableRelease{version, *validatedUrl};
        }
    }
    return {true, latest, {}};
}

QUrl ReleaseUpdateChecker::releasesApiUrl()
{
    return QUrl(QStringLiteral("https://api.github.com/repos/thicking/kdockw/releases"));
}

ReleaseUpdateChecker::ReleaseUpdateChecker(KDockWSettings *settings,
                                           QString installedVersion,
                                           QUrl apiEndpoint,
                                           QObject *parent,
                                           int transferTimeoutMs,
                                           bool diagnosticTestMode,
                                           QString diagnosticReleaseOpenLogPath)
    : QObject(parent)
    , m_settings(settings)
    , m_installedVersion(std::move(installedVersion))
    , m_apiEndpoint(std::move(apiEndpoint))
#ifdef KDOCKW_DIAGNOSTIC_BUILD
    , m_diagnosticTestMode(diagnosticTestMode)
    , m_diagnosticReleaseOpenLogPath(std::move(diagnosticReleaseOpenLogPath))
#else
    , m_diagnosticTestMode(false)
    , m_diagnosticReleaseOpenLogPath()
#endif
    , m_network(this)
{
#ifndef KDOCKW_DIAGNOSTIC_BUILD
    Q_UNUSED(diagnosticTestMode);
    Q_UNUSED(diagnosticReleaseOpenLogPath);
#endif
    Q_ASSERT(m_settings);
    Q_ASSERT(isValidInstalledVersion(m_installedVersion));
    Q_ASSERT(m_apiEndpoint.isEmpty() || isSafeApiEndpoint(m_apiEndpoint));
    m_network.setTransferTimeout(transferTimeoutMs > 0 ? transferTimeoutMs : kTransferTimeoutMs);

    const QString cachedVersion = m_settings->cachedReleaseVersion();
    const QUrl cachedUrl = canonicalReleaseUrl(cachedVersion);
    if (!cachedUrl.isEmpty()) {
        m_latestVersion = cachedVersion;
        m_latestUrl = cachedUrl;
        if (updateAvailable()) {
            m_status = UpdateAvailable;
        } else {
            m_status = UpToDate;
        }
    }
}

ReleaseUpdateChecker::~ReleaseUpdateChecker()
{
    if (m_reply) {
        m_reply->abort();
    }
}

bool ReleaseUpdateChecker::automaticChecksEnabled() const
{
    return m_settings->checkForUpdatesAutomatically();
}

void ReleaseUpdateChecker::setAutomaticChecksEnabled(bool enabled)
{
    if (enabled == automaticChecksEnabled()) {
        return;
    }
    m_settings->setCheckForUpdatesAutomatically(enabled);
    Q_EMIT automaticChecksEnabledChanged();
}

bool ReleaseUpdateChecker::notificationsEnabled() const
{
    return m_settings->notifyAboutUpdates();
}

void ReleaseUpdateChecker::setNotificationsEnabled(bool enabled)
{
    if (enabled == notificationsEnabled()) {
        return;
    }
    m_settings->setNotifyAboutUpdates(enabled);
    Q_EMIT notificationsEnabledChanged();
    if (enabled) {
        maybeNotifyAboutRelease();
    }
}

bool ReleaseUpdateChecker::checking() const
{
    return !m_reply.isNull();
}

ReleaseUpdateChecker::Status ReleaseUpdateChecker::status() const
{
    return m_status;
}

QString ReleaseUpdateChecker::statusMessage() const
{
    switch (m_status) {
    case Checking:
        return i18n("Checking…");
    case UpToDate:
        return i18n("You are using the latest version");
    case UpdateAvailable:
        return i18n("Version %1 is available", m_latestVersion);
    case Failed:
        return i18n("Could not check for updates");
    case NotChecked:
    default:
        return i18n("Update check has not been run");
    }
}

QString ReleaseUpdateChecker::installedVersion() const
{
    return m_installedVersion;
}

QString ReleaseUpdateChecker::latestReleaseVersion() const
{
    return m_latestVersion;
}

QUrl ReleaseUpdateChecker::latestReleaseUrl() const
{
    return m_latestUrl;
}

bool ReleaseUpdateChecker::updateAvailable() const
{
    const auto comparison = compareVersions(m_latestVersion, m_installedVersion);
    return comparison && *comparison > 0;
}

QString ReleaseUpdateChecker::lastSuccessfulCheck() const
{
    const auto dateTime = storedDateTime(m_settings->lastSuccessfulUpdateCheck());
    if (!dateTime) {
        return i18n("Never");
    }
    return QLocale().toString(dateTime->toLocalTime(), QLocale::ShortFormat);
}

bool ReleaseUpdateChecker::diagnosticMode() const
{
    return m_diagnosticTestMode;
}

QString ReleaseUpdateChecker::diagnosticReleaseVersion() const
{
    return m_diagnosticReleaseVersion;
}

QString ReleaseUpdateChecker::diagnosticReleaseOpenLogPath() const
{
    return m_diagnosticReleaseOpenLogPath;
}

void ReleaseUpdateChecker::setDiagnosticReleaseVersion(const QString &version)
{
    if (!m_diagnosticTestMode || (version != QLatin1String("0.3.1") && version != QLatin1String("0.3.2"))
        || version == m_diagnosticReleaseVersion) {
        return;
    }
    m_diagnosticReleaseVersion = version;
    Q_EMIT diagnosticReleaseVersionChanged();
}

void ReleaseUpdateChecker::checkManually()
{
    startCheck(false);
}

void ReleaseUpdateChecker::checkAutomaticallyIfDue()
{
    maybeNotifyAboutRelease();
    if (!automaticChecksEnabled() || checking()) {
        return;
    }
    const QDateTime now = QDateTime::currentDateTimeUtc();
    const auto lastAttempt = storedDateTime(m_settings->lastAutomaticUpdateAttempt());
    if (lastAttempt && lastAttempt->secsTo(now) < kAutomaticCheckIntervalSeconds) {
        return;
    }
    m_settings->setLastAutomaticUpdateAttempt(now.toString(Qt::ISODateWithMs));
    m_settings->save();
    startCheck(true);
}

void ReleaseUpdateChecker::startCheck(bool automatic)
{
    Q_UNUSED(automatic);
    if (checking()) {
        return;
    }
    if (m_apiEndpoint.isEmpty()) {
        setStatus(Failed);
        return;
    }
    if (!isSafeApiEndpoint(m_apiEndpoint)) {
        setStatus(Failed);
        return;
    }
    const auto retryAt = storedDateTime(m_settings->releaseApiRetryAfter());
    if (retryAt && retryAt->secsTo(QDateTime::currentDateTimeUtc()) < 0) {
        setStatus(Failed);
        return;
    }

    QNetworkRequest request(m_apiEndpoint);
    request.setRawHeader(QByteArrayLiteral("Accept"), QByteArrayLiteral("application/vnd.github+json"));
    request.setRawHeader(QByteArrayLiteral("User-Agent"), QByteArrayLiteral("KDockW/") + m_installedVersion.toUtf8());
    request.setRawHeader(QByteArrayLiteral("X-GitHub-Api-Version"), QByteArrayLiteral("2022-11-28"));
#ifdef KDOCKW_DIAGNOSTIC_BUILD
    if (m_diagnosticTestMode) {
        if (m_apiEndpoint.host() != QLatin1String("127.0.0.1") && m_apiEndpoint.host() != QLatin1String("::1")) {
            setStatus(Failed);
            return;
        }
        request.setRawHeader(QByteArrayLiteral("X-KDockW-Diagnostic-Release"), m_diagnosticReleaseVersion.toUtf8());
    }
#endif
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::SameOriginRedirectPolicy);
    if (!m_settings->releasesApiETag().isEmpty()) {
        request.setRawHeader(QByteArrayLiteral("If-None-Match"), m_settings->releasesApiETag().toUtf8());
    }

    m_response.clear();
    m_responseTooLarge = false;
    setStatus(Checking);
    m_reply = m_network.get(request);
    connect(m_reply, &QIODevice::readyRead, this, &ReleaseUpdateChecker::consumeReplyData);
    connect(m_reply, &QNetworkReply::finished, this, &ReleaseUpdateChecker::finishReply);
}

void ReleaseUpdateChecker::consumeReplyData()
{
    if (!m_reply) {
        return;
    }
    if (m_response.size() + m_reply->bytesAvailable() > kMaximumResponseSize) {
        m_responseTooLarge = true;
        m_reply->abort();
        return;
    }
    const QByteArray chunk = m_reply->readAll();
    if (m_response.size() + chunk.size() > kMaximumResponseSize) {
        m_responseTooLarge = true;
        m_reply->abort();
        return;
    }
    m_response.append(chunk);
}

void ReleaseUpdateChecker::finishReply()
{
    QPointer<QNetworkReply> reply = m_reply;
    if (!reply) {
        setStatus(Failed);
        return;
    }
    consumeReplyData();
    m_reply = nullptr;

    const int statusCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    if (m_responseTooLarge) {
        setStatus(Failed);
    } else if (statusCode == 304) {
        const QString cachedVersion = m_settings->cachedReleaseVersion();
        const QUrl cachedUrl = canonicalReleaseUrl(cachedVersion);
        if (cachedUrl.isEmpty() && m_settings->lastSuccessfulUpdateCheck().isEmpty()) {
            setStatus(Failed);
        } else {
            if (cachedUrl.isEmpty()) {
                acceptSuccessfulCheck(std::nullopt, {});
            } else {
                acceptSuccessfulCheck(StableRelease{cachedVersion, cachedUrl}, {});
            }
        }
    } else if (statusCode == 403 || statusCode == 429) {
        persistRetryAfter(reply);
        setStatus(Failed);
    } else if (statusCode != 200 || reply->error() != QNetworkReply::NoError) {
        setStatus(Failed);
    } else {
        const ReleaseCatalogResult catalog = parseReleaseCatalog(m_response);
        if (!catalog.valid) {
            setStatus(Failed);
        } else {
            if (reply->rawHeader(QByteArrayLiteral("ETag")).isEmpty()) {
                m_settings->setReleasesApiETag(QString());
            }
            acceptSuccessfulCheck(catalog.latest, reply->rawHeader(QByteArrayLiteral("ETag")));
        }
    }

    m_response.clear();
    reply->deleteLater();
}

void ReleaseUpdateChecker::setStatus(Status status)
{
    if (m_status == status) {
        return;
    }
    m_status = status;
    Q_EMIT statusChanged();
}

void ReleaseUpdateChecker::acceptSuccessfulCheck(const std::optional<StableRelease> &release, const QByteArray &etag)
{
    setCachedRelease(release);
    if (!etag.isEmpty()) {
        m_settings->setReleasesApiETag(QString::fromUtf8(etag));
    }
    m_settings->setLastSuccessfulUpdateCheck(QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs));
    m_settings->setReleaseApiRetryAfter(QString());
    m_settings->save();
    Q_EMIT lastSuccessfulCheckChanged();
    setStatus(updateAvailable() ? UpdateAvailable : UpToDate);
    maybeNotifyAboutRelease();
}

void ReleaseUpdateChecker::setCachedRelease(const std::optional<StableRelease> &release)
{
    const QString version = release ? release->version : QString();
    const QUrl url = release ? release->url : QUrl();
    if (version == m_latestVersion && url == m_latestUrl) {
        return;
    }
    m_latestVersion = version;
    m_latestUrl = url;
    m_settings->setCachedReleaseVersion(version);
    m_settings->setCachedReleaseUrl(url.toString(QUrl::FullyEncoded));
    Q_EMIT releaseChanged();
}

void ReleaseUpdateChecker::maybeNotifyAboutRelease()
{
    if (!notificationsEnabled() || !updateAvailable() || m_latestUrl != canonicalReleaseUrl(m_latestVersion)
        || m_settings->lastNotifiedReleaseVersion() == m_latestVersion) {
        return;
    }
    m_settings->setLastNotifiedReleaseVersion(m_latestVersion);
    m_settings->save();
    Q_EMIT newReleaseAvailable(m_latestVersion, m_latestUrl);
}

std::optional<QDateTime> ReleaseUpdateChecker::storedDateTime(const QString &value) const
{
    if (value.isEmpty()) {
        return std::nullopt;
    }
    const QDateTime dateTime = QDateTime::fromString(value, Qt::ISODateWithMs);
    if (!dateTime.isValid()) {
        return std::nullopt;
    }
    return dateTime.toUTC();
}

void ReleaseUpdateChecker::persistRetryAfter(QNetworkReply *reply)
{
    const QDateTime now = QDateTime::currentDateTimeUtc();
    QDateTime retryAt;
    const QByteArray retryAfter = reply->rawHeader(QByteArrayLiteral("Retry-After")).trimmed();
    bool isSeconds = false;
    const qint64 seconds = retryAfter.toLongLong(&isSeconds);
    if (isSeconds && seconds >= 0 && seconds <= 7 * 24 * 60 * 60) {
        retryAt = now.addSecs(seconds);
    } else if (!retryAfter.isEmpty()) {
        retryAt = QDateTime::fromString(QString::fromLatin1(retryAfter), Qt::RFC2822Date).toUTC();
    }
    if (!retryAt.isValid()) {
        bool resetOk = false;
        const qint64 reset = reply->rawHeader(QByteArrayLiteral("X-RateLimit-Reset")).toLongLong(&resetOk);
        if (resetOk && reset > now.toSecsSinceEpoch() && reset - now.toSecsSinceEpoch() <= 7 * 24 * 60 * 60) {
            retryAt = QDateTime::fromSecsSinceEpoch(reset, QTimeZone::UTC);
        }
    }
    if (!retryAt.isValid()) {
        retryAt = now.addSecs(60 * 60);
    }
    if (retryAt.isValid()) {
        m_settings->setReleaseApiRetryAfter(retryAt.toString(Qt::ISODateWithMs));
        m_settings->save();
    }
}

void ReleaseUpdateChecker::openReleasePage()
{
    const QUrl validated = canonicalReleaseUrl(m_latestVersion);
    if (updateAvailable() && !validated.isEmpty() && validated == m_latestUrl) {
        openValidatedReleasePage(validated);
    }
}

void ReleaseUpdateChecker::openReleasePageForVersion(const QString &version, const QUrl &url)
{
    const QUrl validated = canonicalReleaseUrl(version);
    if (!validated.isEmpty() && validated == url) {
        openValidatedReleasePage(validated);
    }
}

void ReleaseUpdateChecker::openValidatedReleasePage(const QUrl &validated)
{
#ifdef KDOCKW_DIAGNOSTIC_BUILD
    if (m_diagnosticTestMode) {
        if (m_diagnosticReleaseOpenLogPath.isEmpty() || !QFileInfo(m_diagnosticReleaseOpenLogPath).isAbsolute()) {
            return;
        }
        QDir().mkpath(QFileInfo(m_diagnosticReleaseOpenLogPath).absolutePath());
        QFile log(m_diagnosticReleaseOpenLogPath);
        if (log.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text)) {
            const QByteArray line = QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs).toUtf8() + ' '
                + validated.toString(QUrl::FullyEncoded).toUtf8() + '\n';
            log.write(line);
        }
        return;
    }
#endif
    QDesktopServices::openUrl(validated);
}

} // namespace kdockw
