// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.formcard as FormCard

SettingsPage {
    title: i18n("General")
    subtitle: i18n("General settings and application language")

    FormCard.FormHeader {
        title: i18n("Language")
    }

    FormCard.FormCard {
        FormCard.FormComboBoxDelegate {
            text: i18n("Language")
            description: i18n("Choose the language used by KDockW. System default follows the KDE and Qt locale settings.")
            displayMode: FormCard.FormComboBoxDelegate.Dialog
            model: [i18n("System default"), i18n("Русский"), i18n("English")]
            currentIndex: DockSettings.language === "ru" ? 1 : DockSettings.language === "en" ? 2 : 0
            onActivated: function(index) {
                DockSettings.language = ["system", "ru", "en"][index]
            }
        }
    }
}
