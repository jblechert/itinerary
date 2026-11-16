// SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
// SPDX-License-Identifier: LGPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kitemmodels
import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.formcard as FormCard
import org.kde.itinerary

/** Quick access to the currently valid tickets and passes.
 *  A single ticket is shown right away, with multiple ones there is a list to pick from.
 */
FormCard.FormCardPage {
    id: root

    title: i18nc("@title", "Tickets")

    data: BarcodeScanModeButton {
        page: root
        visible: ticketRepeater.count === 1
    }

    readonly property KSortFilterProxyModel ticketModel: KSortFilterProxyModel {
        sourceModel: PassManager
        filterRowCallback: function(source_row, source_parent) {
            const idx = sourceModel.index(source_row, 0, source_parent);
            return sourceModel.data(idx, PassManager.StateRole) === "valid"
                && sourceModel.data(idx, PassManager.PassTypeRole) !== PassManager.ProgramMembership;
        }
    }

    Component {
        id: ticketPageComponent

        FormCard.FormCardPage {
            id: ticketPage

            property var pass
            property string passId
            property int type
            property string validRangeLabel

            title: view.name

            data: BarcodeScanModeButton {
                page: ticketPage
            }

            TicketQuickView {
                id: view

                pass: ticketPage.pass
                passId: ticketPage.passId
                type: ticketPage.type
                validRangeLabel: ticketPage.validRangeLabel
            }
        }
    }

    // no tickets
    FormCard.FormCard {
        Layout.topMargin: Kirigami.Units.largeSpacing
        visible: ticketRepeater.count === 0

        FormCard.FormPlaceholderMessageDelegate {
            icon.name: "wallet-open"
            text: i18n("No valid tickets or flat rate passes found.")
        }

        FormCard.FormDelegateSeparator {}

        FormCard.FormButtonDelegate {
            text: i18nc("@action:button", "Manage your Passes")
            onClicked: root.QQC2.ApplicationWindow.window.pageStack.push(Qt.createComponent("org.kde.itinerary", "PassPage"))
        }
    }

    // exactly one ticket, show it right away
    Repeater {
        id: ticketRepeater

        model: root.ticketModel
        delegate: Loader {
            id: ticketLoader

            required property var pass
            required property string passId
            required property int type
            required property string validRangeLabel

            Layout.fillWidth: true
            active: ticketRepeater.count === 1
            visible: active
            sourceComponent: TicketQuickView {
                pass: ticketLoader.pass
                passId: ticketLoader.passId
                type: ticketLoader.type
                validRangeLabel: ticketLoader.validRangeLabel
            }
        }
    }

    // multiple tickets, let the user choose
    FormCard.FormCard {
        Layout.topMargin: Kirigami.Units.largeSpacing
        visible: ticketRepeater.count > 1

        Repeater {
            model: ticketRepeater.count > 1 ? root.ticketModel : null
            delegate: PassDelegate {
                id: ticketDelegate

                showDetailsOnClick: false
                onClicked: root.QQC2.ApplicationWindow.window.pageStack.push(ticketPageComponent, {
                    pass: ticketDelegate.pass,
                    passId: ticketDelegate.passId,
                    type: ticketDelegate.type,
                    validRangeLabel: ticketDelegate.validRangeLabel,
                })
            }
        }
    }
}
