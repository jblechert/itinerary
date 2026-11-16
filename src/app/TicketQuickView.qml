// SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
// SPDX-License-Identifier: LGPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.formcard as FormCard
import org.kde.pkpass as KPkPass
import org.kde.kitinerary
import org.kde.itinerary
import './pkpass' as PkPass

/** Ready-to-present view of a single ticket or pass, for visual and barcode inspection.
 *  Besides the barcode this shows continuously moving content, which is what ticket
 *  inspectors commonly look for to tell a live ticket from a screenshot.
 */
ColumnLayout {
    id: root

    /** The pass or ticket to show, as provided by PassManager. */
    required property var pass
    /** PassManager identifier of @p pass. */
    required property string passId
    /** PassManager.PassType of @p pass. */
    required property int type
    /** Human-readable validity time range. */
    required property string validRangeLabel

    readonly property string pkPassId: PkPassManager.passId(root.pass)
    readonly property KPkPass.Pass pkPass: PkPassManager.pass(root.pkPassId)
    readonly property string name: {
        if (root.type === PassManager.PkPass) {
            return root.pkPass.description !== "" ? root.pkPass.description : root.pkPass.logoText;
        }
        return root.pass.name;
    }

    spacing: 0

    CardPageTitle {
        emojiIcon: "🎫"
        text: root.name
    }

    FormCard.FormCard {
        BarcodeContainer {
            id: barcodeContainer

            Layout.alignment: Qt.AlignCenter
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.largeSpacing
            Layout.bottomMargin: Kirigami.Units.largeSpacing

            visible: root.type === PassManager.Ticket && barcodeContainer.hasContent
            barcodeType: root.type === PassManager.Ticket ? root.pass.ticketTokenType : Ticket.Unknown
            barcodeContent: root.type === PassManager.Ticket ? root.pass.ticketTokenData : ""
        }

        Loader {
            Layout.alignment: Qt.AlignCenter
            Layout.topMargin: Kirigami.Units.largeSpacing
            Layout.bottomMargin: Kirigami.Units.largeSpacing

            active: root.type === PassManager.PkPass && root.pkPass !== null
            visible: active
            sourceComponent: PkPass.Barcode {
                pass: root.pkPass
                maximumWidth: root.width - 2 * Kirigami.Units.largeSpacing
            }
        }

        // continuously moving logo, to show this is not a screenshot
        Item {
            id: liveBand

            Layout.fillWidth: true
            implicitHeight: Kirigami.Units.gridUnit * 3
            clip: true

            Rectangle {
                id: mover

                readonly property bool hasLogo: logo.status === Image.Ready

                y: (liveBand.height - height) / 2
                width: (hasLogo ? logo.width : fallbackIcon.width) + 2 * Kirigami.Units.smallSpacing
                height: liveBand.height - 2 * Kirigami.Units.smallSpacing
                radius: Kirigami.Units.cornerRadius
                // pkpass logos are made for a fixed background, so don't follow the theme here
                color: hasLogo ? "white" : "transparent"

                Image {
                    id: logo

                    anchors.centerIn: parent
                    height: parent.height - 2 * Kirigami.Units.smallSpacing
                    width: implicitHeight > 0 ? height * implicitWidth / implicitHeight : 0
                    source: root.pkPassId !== "" ? "image://org.kde.pkpass/" + root.pkPassId + "/logo" : ""
                    fillMode: Image.PreserveAspectFit
                }

                Kirigami.Icon {
                    id: fallbackIcon

                    anchors.centerIn: parent
                    height: parent.height - 2 * Kirigami.Units.smallSpacing
                    width: height
                    visible: !mover.hasLogo
                    source: ReservationHelper.defaultIconName(root.pass)
                }

                XAnimator on x {
                    from: -mover.width
                    to: liveBand.width
                    duration: Math.max(1, liveBand.width + mover.width) / Kirigami.Units.gridUnit * 250
                    loops: Animation.Infinite
                    running: liveBand.visible && liveBand.width > 0
                }
            }
        }

        FormCard.FormDelegateSeparator {}

        FormCard.FormTextDelegate {
            id: clockDelegate

            property date now: new Date()

            text: i18nc("@label current date and time", "Now")
            description: clockDelegate.now.toLocaleString(Qt.locale(), Locale.LongFormat)

            Timer {
                interval: 1000
                repeat: true
                running: clockDelegate.visible
                onTriggered: clockDelegate.now = new Date()
            }
        }
    }

    FormCard.FormCard {
        Layout.topMargin: Kirigami.Units.largeSpacing

        FormCard.FormTextDelegate {
            text: i18n("Name")
            description: root.type === PassManager.Ticket ? root.pass.underName.name : ""
            visible: description !== ""
        }

        FormCard.FormTextDelegate {
            text: i18nc("@label ticket validity time range", "Valid")
            description: root.validRangeLabel
            visible: description !== ""
        }

        FormCard.FormTextDelegate {
            text: i18n("Number")
            description: root.type === PassManager.Ticket ? root.pass.ticketNumber : ""
            visible: description !== ""
        }

        PassDelegate {
            pass: root.pass
            passId: root.passId
            type: root.type
            validRangeLabel: root.validRangeLabel

            icon.name: "view-list-details"
            text: i18nc("@action:button", "Show Details")
            description: ""
        }
    }
}
