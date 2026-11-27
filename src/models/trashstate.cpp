// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

#include "trashstate.h"

#include <KConfig>
#include <KConfigGroup>
#include <KDirWatch>
#include <KIO/DeleteOrTrashJob>
#include <KIO/JobUiDelegateFactory>
#include <KIO/OpenUrlJob>
#include <KLocalizedString>
#include <KNotification>

#include <QStandardPaths>

namespace kdockw
{

namespace
{
const QUrl kTrashUrl(QStringLiteral("trash:/"));

QString trashrcPath()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/trashrc");
}
} // namespace

TrashState::TrashState(QObject *parent)
    : QObject(parent)
    , m_watch(new KDirWatch(this))
{
    // trashrc may not exist until something is trashed for the first time;
    // KDirWatch reports its creation as well as later rewrites.
    m_watch->addFile(trashrcPath());
    connect(m_watch, &KDirWatch::dirty, this, &TrashState::refresh);
    connect(m_watch, &KDirWatch::created, this, &TrashState::refresh);
    connect(m_watch, &KDirWatch::deleted, this, &TrashState::refresh);
    refresh();
}

bool TrashState::isEmpty() const
{
    return m_empty;
}

void TrashState::refresh()
{
    const KConfig config(QStringLiteral("trashrc"), KConfig::SimpleConfig);
    const bool empty = config.group(QStringLiteral("Status")).readEntry("Empty", true);
    if (empty == m_empty) {
        return;
    }
    m_empty = empty;
    Q_EMIT emptyChanged();
}

void TrashState::open()
{
    auto *job = new KIO::OpenUrlJob(kTrashUrl, this);
    job->setUiDelegate(KIO::createDefaultJobUiDelegate(KJobUiDelegate::AutoHandlingEnabled, nullptr));
    job->start();
}

void TrashState::moveToTrash(const QList<QUrl> &urls)
{
    QList<QUrl> sources;
    sources.reserve(urls.size());
    for (const QUrl &url : urls) {
        // Items already in the trash cannot be trashed again.
        if (url.isValid() && url.scheme() != kTrashUrl.scheme()) {
            sources.append(url);
        }
    }
    if (sources.isEmpty()) {
        return;
    }
    // Asks only if the user enabled trash confirmation; records the move for Undo.
    auto *job = new KIO::DeleteOrTrashJob(sources, KIO::AskUserActionInterface::Trash, KIO::AskUserActionInterface::DefaultConfirmation, this);
    job->start();
}

void TrashState::emptyTrash()
{
    auto *job = new KIO::DeleteOrTrashJob({}, KIO::AskUserActionInterface::EmptyTrash, KIO::AskUserActionInterface::DefaultConfirmation, this);
    connect(job, &KJob::result, this, [job]() {
        if (job->error() == KJob::NoError) {
            // Plasma's standard "Trash: emptied" event, as Dolphin sends it.
            KNotification::event(QStringLiteral("Trash: emptied"),
                                 i18n("Trash Emptied"),
                                 i18n("The Trash was emptied."),
                                 QStringLiteral("user-trash"),
                                 KNotification::DefaultEvent);
        }
    });
    job->start();
}

} // namespace kdockw
