// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

#include "folderstackmodel.h"

#include <KDirModel>
#include <KDirLister>
#include <KCoreDirLister>
#include <KFileItem>
#include <KIO/Global>
#include <KIO/Job>
#include <KIO/OpenUrlJob>
#include <KJob>
#include <KLocalizedString>

#include <QDir>

namespace kdockw
{

FolderStackModel::FolderStackModel(QObject *parent)
    : QSortFilterProxyModel(parent)
    , m_dirModel(new KDirModel(this))
{
    m_collator.setCaseSensitivity(Qt::CaseInsensitive);
    m_collator.setNumericMode(true);

    m_dirModel->dirLister()->setAutoErrorHandlingEnabled(false);
    setSourceModel(m_dirModel);
    setDynamicSortFilter(true);
    setSortRole(Qt::DisplayRole);
    sort(0, Qt::AscendingOrder);

    connect(m_dirModel->dirLister(), &KCoreDirLister::started, this, [this]() {
        setLoading(true);
    });
    connect(m_dirModel->dirLister(), &KCoreDirLister::completed, this, [this]() {
        setLoading(false);
    });
    connect(m_dirModel->dirLister(), &KCoreDirLister::jobError, this, [this](KIO::Job *job) {
        setLoading(false);
        reportJobError(job->error(), job->errorString());
    });
}

QUrl FolderStackModel::rootUrl() const
{
    return m_rootUrl;
}

QUrl FolderStackModel::currentUrl() const
{
    return m_currentUrl;
}

QString FolderStackModel::errorMessage() const
{
    return m_errorMessage;
}

bool FolderStackModel::loading() const
{
    return m_loading;
}

QVariant FolderStackModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.column() != 0) {
        return {};
    }

    const QModelIndex sourceIndex = mapToSource(index);
    if (!sourceIndex.isValid()) {
        return {};
    }
    const KFileItem item = m_dirModel->itemForIndex(sourceIndex);
    switch (role) {
    case FileUrlRole:
        return item.url();
    case IconNameRole:
        return item.iconName();
    case IsDirectoryRole:
        return item.isDir();
    case IsSymbolicLinkRole:
        return item.isLink();
    default:
        return QSortFilterProxyModel::data(index, role);
    }
}

QHash<int, QByteArray> FolderStackModel::roleNames() const
{
    QHash<int, QByteArray> roles = QSortFilterProxyModel::roleNames();
    roles.insert(FileUrlRole, "fileUrl");
    roles.insert(IconNameRole, "iconName");
    roles.insert(IsDirectoryRole, "isDirectory");
    roles.insert(IsSymbolicLinkRole, "isSymbolicLink");
    return roles;
}

bool FolderStackModel::openFolder(const QUrl &rootUrl)
{
    if (!isLocalFolderUrl(rootUrl)) {
        reportJobError(KIO::ERR_UNSUPPORTED_ACTION, QString{});
        return false;
    }

    if (m_rootUrl != rootUrl) {
        m_rootUrl = rootUrl;
        Q_EMIT rootUrlChanged();
    }
    navigateTo(m_rootUrl);
    return true;
}

bool FolderStackModel::openItem(int row)
{
    const QModelIndex itemIndex = index(row, 0);
    if (!itemIndex.isValid()) {
        return false;
    }
    const QUrl url = data(itemIndex, FileUrlRole).toUrl();
    if (data(itemIndex, IsDirectoryRole).toBool()) {
        navigateTo(url);
    } else {
        openUrlWithDefaultApplication(url);
    }
    return true;
}

void FolderStackModel::goUp()
{
    if (!m_currentUrl.isLocalFile() || !m_rootUrl.isLocalFile()) {
        return;
    }

    const QString currentPath = QDir::cleanPath(m_currentUrl.toLocalFile());
    const QString rootPath = QDir::cleanPath(m_rootUrl.toLocalFile());
    if (currentPath == rootPath) {
        return;
    }

    QDir parent(currentPath);
    if (!parent.cdUp()) {
        return;
    }
    const QString parentPath = QDir::cleanPath(parent.absolutePath());
    const QString relativeParent = QDir(rootPath).relativeFilePath(parentPath);
    if (relativeParent == QLatin1String("..") || relativeParent.startsWith(QLatin1String("../")) || QDir::isAbsolutePath(relativeParent)) {
        return;
    }
    navigateTo(QUrl::fromLocalFile(parentPath));
}

void FolderStackModel::openCurrentFolder()
{
    if (!m_currentUrl.isEmpty()) {
        openUrlWithDefaultApplication(m_currentUrl);
    }
}

void FolderStackModel::close()
{
    m_dirModel->dirLister()->stop();
    setLoading(false);
}

bool FolderStackModel::lessThan(const QModelIndex &left, const QModelIndex &right) const
{
    const KFileItem leftItem = m_dirModel->itemForIndex(left);
    const KFileItem rightItem = m_dirModel->itemForIndex(right);
    if (leftItem.isDir() != rightItem.isDir()) {
        return leftItem.isDir();
    }
    return m_collator.compare(leftItem.name(), rightItem.name()) < 0;
}

bool FolderStackModel::isLocalFolderUrl(const QUrl &url)
{
    return url.isValid() && url.isLocalFile() && url.host().isEmpty() && url.path().startsWith(QLatin1Char('/')) && url.query().isEmpty()
        && url.fragment().isEmpty();
}

void FolderStackModel::navigateTo(const QUrl &url)
{
    if (!isLocalFolderUrl(url)) {
        reportJobError(KIO::ERR_UNSUPPORTED_ACTION, QString{});
        return;
    }
    if (m_currentUrl != url) {
        m_currentUrl = url;
        Q_EMIT currentUrlChanged();
    }
    setErrorMessage({});
    setLoading(true);
    m_dirModel->openUrl(url, KDirModel::Reload);
}

void FolderStackModel::setErrorMessage(const QString &message)
{
    if (m_errorMessage == message) {
        return;
    }
    m_errorMessage = message;
    Q_EMIT errorMessageChanged();
}

void FolderStackModel::setLoading(bool loading)
{
    if (m_loading == loading) {
        return;
    }
    m_loading = loading;
    Q_EMIT loadingChanged();
}

void FolderStackModel::openUrlWithDefaultApplication(const QUrl &url)
{
    auto *job = new KIO::OpenUrlJob(url, this);
    connect(job, &KJob::result, this, [this, job](KJob *) {
        if (job->error() != KJob::NoError) {
            const QString message = i18n("Could not open this item");
            setErrorMessage(message);
            Q_EMIT itemOpenFailed(message);
        }
    });
    job->start();
}

void FolderStackModel::reportJobError(int errorCode, const QString &)
{
    QString message;
    if (errorCode == KIO::ERR_DOES_NOT_EXIST || errorCode == KIO::ERR_CANNOT_ENTER_DIRECTORY) {
        message = i18n("This folder is no longer available");
    } else if (errorCode == KIO::ERR_ACCESS_DENIED) {
        message = i18n("You do not have permission to view this folder");
    } else {
        message = i18n("Could not read this folder");
    }
    setErrorMessage(message);
}

} // namespace kdockw
