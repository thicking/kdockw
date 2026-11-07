// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

import QtQuick
import org.kde.kirigamiaddons.delegates as Delegates
import org.kde.kirigamiaddons.formcard as FormCard
import com.thicking.kdockw 1.0

SettingsPage {
    id: rootPage

    readonly property var languageIds: ["system", "ru", "en"]

    title: i18n("General")
    subtitle: i18n("General settings and application language")

    function languageLabel(index) {
        switch (index) {
        case 0: return i18n("System default")
        case 1: return i18n("Русский")
        case 2: return i18n("English")
        default: return ""
        }
    }

    function languageIndex(language) {
        const index = languageIds.indexOf(language)
        return index >= 0 ? index : 0
    }

    FormCard.FormHeader {
        objectName: "languageSectionHeader"
        title: i18n("Language")
    }

    FormCard.FormCard {
        FormCard.FormComboBoxDelegate {
            id: languageSelector
            objectName: "languageSelector"
            text: i18n("Language")
            description: i18n("Choose the language used by KDockW. System default follows the KDE and Qt locale settings.")
            displayMode: FormCard.FormComboBoxDelegate.ComboBox
            comboBoxDelegate: Delegates.RoundedItemDelegate {
                required property int index
                text: rootPage.languageLabel(index)
                highlighted: languageSelector.highlightedIndex === index
            }
            // Keep option identity stable across KI18n retranslation. If
            // translated labels are the model itself, replacing that array
            // can reset ComboBox.currentIndex and overwrite the preference.
            model: rootPage.languageIds
            displayText: rootPage.languageLabel(rootPage.languageIndex(DockSettings.language))
            currentIndex: rootPage.languageIndex(DockSettings.language)
            onActivated: index => {
                if (index < 0 || index >= rootPage.languageIds.length) {
                    return
                }
                const language = rootPage.languageIds[index]
                DockSettings.language = language
            }
        }
    }

}
