// SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
// SPDX-License-Identifier: LGPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtLocation as QtLocation
import QtPositioning
import org.kde.coreaddons as CoreAddons
import org.kde.guiaddons as GuiAddons
import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.components as Components
import org.kde.kpublictransport as KPublicTransport
import org.kde.kpublictransport.ui as KPublicTransport
import org.kde.itinerary

/** Turn-by-turn walking navigation to a stop, with the map following the current position and spoken instructions. */
Kirigami.Page {
    id: root

    /** The journey whose leading walk to the departure stop to navigate, if any. */
    property var journey
    /** Where to walk to. */
    property var destination

    title: i18nc("@title walking navigation, %1 is a stop", "Walk to %1", root.destination.name)
    padding: 0

    /** No walking route could be found. */
    property bool noRoute: false
    /** Keep the map centered on the current position, until the user moves the map. */
    property bool followPosition: true

    function requestRoute(latitude: real, longitude: real): void {
        root.noRoute = false;
        routeModel.request = controller.walkingRequest(latitude, longitude, root.destination);
    }

    WalkingNavigationController {
        id: controller
        destination: root.destination
        onRerouteRequested: (latitude, longitude) => root.requestRoute(latitude, longitude)
        Component.onCompleted: {
            if (root.journey) {
                controller.path = controller.walkingPath(root.journey);
            }
        }
    }

    KPublicTransport.JourneyQueryModel {
        id: routeModel
        manager: LiveDataManager.publicTransportManager
        onLoadingChanged: {
            if (routeModel.loading) {
                return;
            }
            if (routeModel.rowCount() > 0) {
                controller.path = controller.walkingPath(routeModel.data(routeModel.index(0, 0), KPublicTransport.JourneyQueryModel.JourneyRole));
            } else if (!controller.hasRoute) {
                root.noRoute = true;
            }
        }
    }

    LocationPermission {
        id: locationPermission
        accuracy: LocationPermission.Precise
        availability: LocationPermission.WhenInUse
    }

    PositionSource {
        id: positionSource
        active: locationPermission.status === Qt.Granted
        updateInterval: 1000
        preferredPositioningMethods: PositionSource.SatellitePositioningMethods
        onPositionChanged: {
            const pos = positionSource.position;
            if (!pos.latitudeValid || !pos.longitudeValid) {
                return;
            }
            controller.updatePosition(pos.coordinate.latitude, pos.coordinate.longitude, pos.horizontalAccuracyValid ? pos.horizontalAccuracy : 0);
            if (root.followPosition) {
                map.center = pos.coordinate;
            }
        }
    }

    // keep the screen on while navigating
    GuiAddons.SystemInhibitor {
        window: root.QQC2.ApplicationWindow.window
        types: GuiAddons.SystemInhibitor.Idle
        enabled: root.visible
        reason: i18nc("@info reason for keeping the screen on", "Walking navigation")
    }

    Component.onCompleted: {
        if (locationPermission.status !== Qt.Granted) {
            locationPermission.request();
        }
    }

    header: QQC2.Control {
        padding: Kirigami.Units.largeSpacing

        Kirigami.Theme.inherit: false
        Kirigami.Theme.colorSet: Kirigami.Theme.Header

        background: Rectangle {
            color: controller.offRoute ? Kirigami.Theme.neutralBackgroundColor : Kirigami.Theme.backgroundColor
        }

        contentItem: RowLayout {
            spacing: Kirigami.Units.largeSpacing

            Kirigami.Icon {
                source: controller.instructionIconName
                isMask: true
                Layout.preferredWidth: Kirigami.Units.iconSizes.large
                Layout.preferredHeight: Kirigami.Units.iconSizes.large
            }

            ColumnLayout {
                spacing: 0
                Layout.fillWidth: true

                Kirigami.Heading {
                    level: 2
                    text: {
                        if (!controller.hasPosition) {
                            return i18nc("@info walking navigation", "Waiting for your location…");
                        }
                        if (controller.offRoute || (!controller.hasRoute && !root.noRoute)) {
                            return i18nc("@info walking navigation", "Looking for a route…");
                        }
                        if (root.noRoute) {
                            return i18nc("@info walking navigation", "No walking route found");
                        }
                        return controller.instruction;
                    }
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
                QQC2.Label {
                    text: CoreAddons.Format.formatDistance(controller.distanceToInstruction, Settings.distanceFormat)
                    visible: controller.hasRoute && controller.hasPosition && !controller.arrived && !controller.offRoute
                    font.bold: true
                }
            }
        }
    }

    MapView {
        id: map
        anchors.fill: parent
        zoomLevel: 18

        onUserInteractingChanged: {
            if (map.userInteracting) {
                root.followPosition = false;
            }
        }

        QtLocation.MapPolyline {
            id: routeLine
            line.width: 6
            // hardcoded Breeze black, can't use Kirigami theme colors as we need contrast to OSM tiles here, also in dark mode
            line.color: "#232629"
            path: KPublicTransport.MapUtils.polyline(controller.path)
        }

        // the destination
        MapCircle {
            visible: root.destination.hasCoordinate
            coordinate {
                latitude: root.destination.latitude
                longitude: root.destination.longitude
            }
            color: routeLine.line.color
            textColor: "#eff0f1"
            iconName: "flag"
            size: 24
        }

        // the current position
        QtLocation.MapQuickItem {
            visible: positionSource.valid && controller.hasPosition
            coordinate: positionSource.position.coordinate
            anchorPoint.x: positionMarker.width / 2
            anchorPoint.y: positionMarker.height / 2
            sourceItem: Rectangle {
                id: positionMarker
                width: Kirigami.Units.gridUnit
                height: width
                radius: width / 2
                color: Kirigami.Theme.highlightColor
                border.color: "white"
                border.width: 3
            }
        }
    }

    Components.FloatingButton {
        icon.name: "mark-location-symbolic"
        text: i18nc("@action:button", "Follow my location")
        visible: !root.followPosition
        onClicked: {
            root.followPosition = true;
            if (positionSource.valid) {
                map.center = positionSource.position.coordinate;
            }
        }
        anchors {
            right: parent.right
            bottom: parent.bottom
            margins: Kirigami.Units.largeSpacing
        }
    }

    footer: QQC2.ToolBar {
        contentItem: RowLayout {
            QQC2.Label {
                text: controller.hasRoute && controller.hasPosition
                    ? i18nc("@info remaining walking distance", "%1 to go", CoreAddons.Format.formatDistance(controller.distanceRemaining, Settings.distanceFormat))
                    : ""
                Layout.fillWidth: true
            }
            QQC2.ToolButton {
                icon.name: controller.speechEnabled ? "audio-volume-high" : "audio-volume-muted"
                text: i18nc("@action:button", "Voice guidance")
                display: QQC2.AbstractButton.IconOnly
                checkable: true
                checked: controller.speechEnabled
                onToggled: controller.speechEnabled = checked
            }
            QQC2.ToolButton {
                icon.name: "map-symbolic"
                text: i18nc("@action:button", "Open in Map Application")
                display: QQC2.AbstractButton.IconOnly
                visible: root.destination.hasCoordinate
                onClicked: NavigationController.walkTo(root.destination.latitude, root.destination.longitude, root.destination.name)
            }
            QQC2.ToolButton {
                icon.name: "dialog-close"
                text: i18nc("@action:button end walking navigation", "End")
                onClicked: root.QQC2.ApplicationWindow.window.pageStack.layers.pop()
            }
        }
    }
}
