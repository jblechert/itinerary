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
        visible: root.shownTicketRow >= 0
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

    // bumped whenever the current location or validity areas change, to re-evaluate validity bindings
    property int validityRevision: 0
    Connections {
        target: TicketValidityManager
        function onPositionChanged(): void { ++root.validityRevision; }
        function onValidityAreasChanged(): void { ++root.validityRevision; }
    }

    function validityAt(row: int): int {
        root.validityRevision; // dependency for bindings
        const idx = root.ticketModel.index(row, 0);
        return TicketValidityManager.validity(root.ticketModel.data(idx, PassManager.PassIdRole), root.ticketModel.data(idx, PassManager.NameRole));
    }

    /** The ticket best usable at the current location: one valid in the entire country, otherwise one valid in the area. */
    readonly property int bestTicketRow: {
        root.validityRevision;
        let best = -1;
        let bestValidity = TicketValidityManager.NotValidHere;
        for (let row = 0; row < ticketRepeater.count; ++row) {
            const validity = root.validityAt(row);
            if (validity > bestValidity && validity !== TicketValidityManager.Unknown) {
                best = row;
                bestValidity = validity;
            }
        }
        return best;
    }
    readonly property int bestValidity: root.bestTicketRow >= 0 ? root.validityAt(root.bestTicketRow) : TicketValidityManager.NotValidHere
    /** The ticket shown right away: the only one, or the one best usable here. */
    readonly property int shownTicketRow: ticketRepeater.count === 1 ? 0 : root.bestTicketRow

    // where we are and whether we have a ticket for here
    FormCard.FormCard {
        Layout.topMargin: Kirigami.Units.largeSpacing
        visible: TicketValidityManager.hasPosition && ticketRepeater.count > 0

        FormCard.FormTextDelegate {
            text: TicketValidityManager.locationName
            description: switch (root.bestValidity) {
                case TicketValidityManager.ValidInCountry:
                    return i18nc("@info", "You have a ticket valid in the entire country.");
                case TicketValidityManager.ValidInArea:
                    return i18nc("@info", "You have a ticket valid in this area. Mind its zones or area limits.");
                default:
                    return i18nc("@info", "None of your tickets is known to be valid here.");
            }
            leading: Kirigami.Icon {
                source: root.bestValidity === TicketValidityManager.NotValidHere ? "dialog-cancel" : "checkmark"
                color: switch (root.bestValidity) {
                    case TicketValidityManager.ValidInCountry: return Kirigami.Theme.positiveTextColor;
                    case TicketValidityManager.ValidInArea: return Kirigami.Theme.neutralTextColor;
                    default: return Kirigami.Theme.negativeTextColor;
                }
                isMask: true
                implicitWidth: Kirigami.Units.iconSizes.large
                implicitHeight: Kirigami.Units.iconSizes.large
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

    // the only ticket or the one valid here, shown right away
    Repeater {
        id: ticketRepeater

        model: root.ticketModel
        delegate: Loader {
            id: ticketLoader

            required property int index
            required property var pass
            required property string passId
            required property int type
            required property string validRangeLabel

            Layout.fillWidth: true
            active: ticketLoader.index === root.shownTicketRow
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
    FormCard.FormHeader {
        title: i18nc("@title:group", "Other Tickets")
        visible: ticketRepeater.count > 1 && root.shownTicketRow >= 0
    }
    FormCard.FormCard {
        Layout.topMargin: root.shownTicketRow >= 0 ? 0 : Kirigami.Units.largeSpacing
        visible: ticketRepeater.count > 1

        Repeater {
            model: ticketRepeater.count > 1 ? root.ticketModel : null
            delegate: PassDelegate {
                id: ticketDelegate

                required property int index
                readonly property int validity: root.validityAt(ticketDelegate.index)

                visible: ticketDelegate.index !== root.shownTicketRow
                showDetailsOnClick: false
                trailing: Kirigami.Icon {
                    visible: ticketDelegate.validity !== TicketValidityManager.Unknown
                    source: ticketDelegate.validity === TicketValidityManager.NotValidHere ? "dialog-cancel" : "checkmark"
                    color: switch (ticketDelegate.validity) {
                        case TicketValidityManager.ValidInCountry: return Kirigami.Theme.positiveTextColor;
                        case TicketValidityManager.ValidInArea: return Kirigami.Theme.neutralTextColor;
                        default: return Kirigami.Theme.negativeTextColor;
                    }
                    isMask: true
                    implicitWidth: Kirigami.Units.iconSizes.smallMedium
                    implicitHeight: Kirigami.Units.iconSizes.smallMedium
                }
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
