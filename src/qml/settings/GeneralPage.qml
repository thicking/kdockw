// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.delegates as Delegates
import org.kde.kirigamiaddons.formcard as FormCard

SettingsPage {
    id: rootPage

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
            model: ["system", "ru", "en"]
            displayText: languageLabel(currentIndex)
            dialogDelegate: Delegates.RoundedItemDelegate {
                required property int index
                text: languageSelector.languageLabel(index)
                highlighted: languageSelector.highlightedIndex === index

                onClicked: {
                    languageSelector.currentIndex = index
                    languageSelector.activated(index)
                    languageSelector.closeDialog()
                }
            }
            currentIndex: DockSettings.language === "ru" ? 1 : DockSettings.language === "en" ? 2 : 0
            onCurrentIndexChanged: {
                const languages = ["system", "ru", "en"]
                if (currentIndex >= 0 && currentIndex < languages.length
                        && DockSettings.language !== languages[currentIndex]) {
                    DockSettings.language = languages[currentIndex]
                }
            }
        }
    }
}
