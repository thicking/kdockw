// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#pragma once

#include <QByteArray>
#include <QDateTime>
#include <QNetworkAccessManager>
#include <QObject>
#include <QPointer>
#include <QUrl>

#include <optional>

class KDockWSettings;
class QNetworkReply;

namespace kdockw
{

struct StableRelease {
    QString version;
    QUrl url;
};

struct ReleaseCatalogResult {
    bool valid = false;
    std::optional<StableRelease> latest;
    QString error;
};

/// Parse the supported x.y.z and x.y.z-dev forms and compare numerically.
[[nodiscard]] bool isValidInstalledVersion(const QString &version);
[[nodiscard]] std::optional<int> compareVersions(const QString &left, const QString &right);

/// Validate a GitHub Releases API array and select the numerically newest
/// stable KDockW release, regardless of the order returned by GitHub.
[[nodiscard]] ReleaseCatalogResult parseReleaseCatalog(const QByteArray &json);
[[nodiscard]] QUrl canonicalReleaseUrl(const QString &version);

class ReleaseUpdateChecker final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool automaticChecksEnabled READ automaticChecksEnabled WRITE setAutomaticChecksEnabled NOTIFY automaticChecksEnabledChanged)
    Q_PROPERTY(bool notificationsEnabled READ notificationsEnabled WRITE setNotificationsEnabled NOTIFY notificationsEnabledChanged)
    Q_PROPERTY(bool checking READ checking NOTIFY statusChanged)
    Q_PROPERTY(Status status READ status NOTIFY statusChanged)
    Q_PROPERTY(QString statusMessage READ statusMessage NOTIFY statusChanged)
    Q_PROPERTY(QString installedVersion READ installedVersion CONSTANT)
    Q_PROPERTY(QString latestReleaseVersion READ latestReleaseVersion NOTIFY releaseChanged)
    Q_PROPERTY(QUrl latestReleaseUrl READ latestReleaseUrl NOTIFY releaseChanged)
    Q_PROPERTY(bool updateAvailable READ updateAvailable NOTIFY releaseChanged)
    Q_PROPERTY(QString lastSuccessfulCheck READ lastSuccessfulCheck NOTIFY lastSuccessfulCheckChanged)
    Q_PROPERTY(bool diagnosticMode READ diagnosticMode CONSTANT)
    Q_PROPERTY(QString diagnosticReleaseVersion READ diagnosticReleaseVersion NOTIFY diagnosticReleaseVersionChanged)
    Q_PROPERTY(QString diagnosticReleaseOpenLogPath READ diagnosticReleaseOpenLogPath CONSTANT)

public:
    enum Status {
        NotChecked,
        Checking,
        UpToDate,
        UpdateAvailable,
        Failed,
    };
    Q_ENUM(Status)

    explicit ReleaseUpdateChecker(KDockWSettings *settings,
                                  QString installedVersion = QStringLiteral(KDOCKW_VERSION_STRING),
                                  QUrl apiEndpoint = releasesApiUrl(),
                                  QObject *parent = nullptr,
                                  int transferTimeoutMs = 15000,
                                  bool diagnosticTestMode = false,
                                  QString diagnosticReleaseOpenLogPath = {});
    ~ReleaseUpdateChecker() override;

    [[nodiscard]] static QUrl releasesApiUrl();
    [[nodiscard]] bool automaticChecksEnabled() const;
    void setAutomaticChecksEnabled(bool enabled);
    [[nodiscard]] bool notificationsEnabled() const;
    void setNotificationsEnabled(bool enabled);
    [[nodiscard]] bool checking() const;
    [[nodiscard]] Status status() const;
    [[nodiscard]] QString statusMessage() const;
    [[nodiscard]] QString installedVersion() const;
    [[nodiscard]] QString latestReleaseVersion() const;
    [[nodiscard]] QUrl latestReleaseUrl() const;
    [[nodiscard]] bool updateAvailable() const;
    [[nodiscard]] QString lastSuccessfulCheck() const;
    [[nodiscard]] bool diagnosticMode() const;
    [[nodiscard]] QString diagnosticReleaseVersion() const;
    [[nodiscard]] QString diagnosticReleaseOpenLogPath() const;

    Q_INVOKABLE void checkManually();
    Q_INVOKABLE void openReleasePage();
    void openReleasePageForVersion(const QString &version, const QUrl &url);
    Q_INVOKABLE void setDiagnosticReleaseVersion(const QString &version);

    /// Starts at most one automatic request per 24 hours. Called once during
    /// application startup; a failed request is retried on a later startup.
    void checkAutomaticallyIfDue();

Q_SIGNALS:
    void automaticChecksEnabledChanged();
    void notificationsEnabledChanged();
    void statusChanged();
    void releaseChanged();
    void lastSuccessfulCheckChanged();
    void diagnosticReleaseVersionChanged();
    void newReleaseAvailable(const QString &version, const QUrl &url);

private:
    void startCheck(bool automatic);
    void consumeReplyData();
    void finishReply();
    void setStatus(Status status);
    void acceptSuccessfulCheck(const std::optional<StableRelease> &release, const QByteArray &etag);
    void setCachedRelease(const std::optional<StableRelease> &release);
    void maybeNotifyAboutRelease();
    void openValidatedReleasePage(const QUrl &url);
    [[nodiscard]] std::optional<QDateTime> storedDateTime(const QString &value) const;
    void persistRetryAfter(QNetworkReply *reply);

    KDockWSettings *m_settings;
    const QString m_installedVersion;
    const QUrl m_apiEndpoint;
    const bool m_diagnosticTestMode;
    const QString m_diagnosticReleaseOpenLogPath;
    QNetworkAccessManager m_network;
    QPointer<QNetworkReply> m_reply;
    QByteArray m_response;
    bool m_responseTooLarge = false;
    Status m_status = NotChecked;
    QString m_latestVersion;
    QUrl m_latestUrl;
    QString m_diagnosticReleaseVersion = QStringLiteral("0.3.1");
};

} // namespace kdockw
