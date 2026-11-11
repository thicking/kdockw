// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

#pragma once

#include <QCollator>
#include <QSortFilterProxyModel>
#include <QUrl>

class KDirModel;

namespace kdockw
{

/** Asynchronous file listing and navigation for one visible Folder Stack. */
class FolderStackModel : public QSortFilterProxyModel
{
    Q_OBJECT
    Q_PROPERTY(QUrl rootUrl READ rootUrl NOTIFY rootUrlChanged)
    Q_PROPERTY(QUrl currentUrl READ currentUrl NOTIFY currentUrlChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY errorMessageChanged)
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)

public:
    enum Role {
        FileUrlRole = Qt::UserRole + 1,
        IconNameRole,
        IsDirectoryRole,
        IsSymbolicLinkRole,
    };
    Q_ENUM(Role)

    explicit FolderStackModel(QObject *parent = nullptr);

    [[nodiscard]] QUrl rootUrl() const;
    [[nodiscard]] QUrl currentUrl() const;
    [[nodiscard]] QString errorMessage() const;
    [[nodiscard]] bool loading() const;

    [[nodiscard]] QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    [[nodiscard]] QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE bool openFolder(const QUrl &rootUrl);
    Q_INVOKABLE bool openItem(int row);
    Q_INVOKABLE void goUp();
    Q_INVOKABLE void openCurrentFolder();
    Q_INVOKABLE void close();

Q_SIGNALS:
    void rootUrlChanged();
    void currentUrlChanged();
    void errorMessageChanged();
    void loadingChanged();
    void itemOpenFailed(const QString &message);

protected:
    [[nodiscard]] bool lessThan(const QModelIndex &left, const QModelIndex &right) const override;

private:
    [[nodiscard]] static bool isLocalFolderUrl(const QUrl &url);
    void navigateTo(const QUrl &url);
    void setErrorMessage(const QString &message);
    void setLoading(bool loading);
    void openUrlWithDefaultApplication(const QUrl &url);
    void reportJobError(int errorCode, const QString &errorString);

    KDirModel *m_dirModel = nullptr;
    QCollator m_collator;
    QUrl m_rootUrl;
    QUrl m_currentUrl;
    QString m_errorMessage;
    bool m_loading = false;
};

} // namespace kdockw
