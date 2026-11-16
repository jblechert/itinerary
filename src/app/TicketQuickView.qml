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

    /** Image assets of the Apple Wallet pass that can be shown as moving image, in order of preference. */
    readonly property list<var> availableImages: {
        if (!root.pkPass) {
            return [];
        }
        return [
            { name: "thumbnail", label: i18nc("pkpass image type", "Thumbnail"), available: root.pkPass.hasThumbnail },
            { name: "logo", label: i18nc("pkpass image type", "Logo"), available: root.pkPass.hasLogo },
            { name: "icon", label: i18nc("pkpass image type", "Icon"), available: root.pkPass.hasIcon },
            { name: "strip", label: i18nc("pkpass image type", "Strip"), available: root.pkPass.hasStrip },
            { name: "footer", label: i18nc("pkpass image type", "Footer"), available: root.pkPass.hasFooter },
            { name: "background", label: i18nc("pkpass image type", "Background"), available: root.pkPass.hasBackground },
        ].filter(image => image.available);
    }
    /** Index in availableImages of the image to show.
     *  The choice is remembered per pass type, so it survives e.g. monthly renewals of a subscription.
     */
    property int imageIndex: {
        if (!root.pkPass) {
            return -1;
        }
        const name = Settings.ticketViewImage(root.pkPass.passTypeIdentifier);
        return Math.max(0, root.availableImages.findIndex(image => image.name === name));
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

                onWidthChanged: moveAnimation.restart()

                Image {
                    id: logo

                    anchors.centerIn: parent
                    height: parent.height - 2 * Kirigami.Units.smallSpacing
                    width: implicitHeight > 0 ? height * implicitWidth / implicitHeight : 0
                    source: root.imageIndex >= 0 && root.imageIndex < root.availableImages.length ? "image://org.kde.pkpass/" + root.pkPassId + "/" + root.availableImages[root.imageIndex].name : ""
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

                NumberAnimation on x {
                    id: moveAnimation

                    from: -mover.width
                    to: liveBand.width
                    duration: (liveBand.width + mover.width) / Kirigami.Units.gridUnit * 250
                    loops: Animation.Infinite
                    running: liveBand.visible && liveBand.width > 0
                }
            }

            // the animation doesn't pick up geometry changes while running
            onWidthChanged: moveAnimation.restart()
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

        FormCard.FormComboBoxDelegate {
            text: i18nc("@label:listbox", "Moving image")
            visible: root.availableImages.length > 1
            model: root.availableImages
            textRole: "label"
            valueRole: "name"
            currentIndex: root.imageIndex
            onActivated: {
                root.imageIndex = currentIndex;
                Settings.setTicketViewImage(root.pkPass.passTypeIdentifier, currentValue);
            }
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
