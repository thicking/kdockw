// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

#include <KApplicationTrader>
#include <KService>

#include <QCoreApplication>
#include <QFileInfo>
#include <QProcess>
#include <QStringList>

#include <iostream>

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    if (argc != 3) {
        std::cerr << "Usage: kdockw_diagnostic_metadata_check <executable> <desktop-storage-id>\n";
        return 2;
    }

    const QString executablePath = QFileInfo(QString::fromLocal8Bit(argv[1])).canonicalFilePath();
    const QString expectedStorageId = QString::fromLocal8Bit(argv[2]);
    if (executablePath.isEmpty()) {
        std::cerr << "Diagnostic executable does not resolve to a canonical path.\n";
        return 2;
    }

    // This mirrors KWin's path based metadata lookup: the first word of Exec,
    // canonicalized, must equal the Wayland client's executable path.
    const KService::List matchingServices = KApplicationTrader::query([&](const KService::Ptr &service) {
        const QStringList command = QProcess::splitCommand(service->exec());
        return !command.isEmpty() && QFileInfo(command.constFirst()).canonicalFilePath() == executablePath;
    });

    if (matchingServices.size() != 1) {
        std::cerr << "Expected exactly one KService entry matching the diagnostic executable; found "
                  << matchingServices.size() << ".\n";
        return 1;
    }

    const KService::Ptr service = matchingServices.constFirst();
    const QStringList interfaces = service->property<QStringList>(QStringLiteral("X-KDE-Wayland-Interfaces"));
    if (service->storageId() != expectedStorageId) {
        std::cerr << "KWin path lookup resolved unexpected desktop storage id: "
                  << service->storageId().toStdString() << ".\n";
        return 1;
    }
    if (!interfaces.contains(QStringLiteral("org_kde_plasma_window_management"))) {
        std::cerr << "KService metadata does not grant org_kde_plasma_window_management.\n";
        return 1;
    }
    if (!interfaces.contains(QStringLiteral("zkde_screencast_unstable_v1"))) {
        std::cerr << "KService metadata does not grant zkde_screencast_unstable_v1.\n";
        return 1;
    }

    std::cout << "KService matched " << service->storageId().toStdString()
              << " to the diagnostic executable and grants Plasma window management and KWin ScreenCast.\n";
    return 0;
}
