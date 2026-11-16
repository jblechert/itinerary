// SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
// SPDX-License-Identifier: LGPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtLocation as QtLocation
import QtPositioning
import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.components as Components
import org.kde.kpublictransport as KPublicTransport
import org.kde.itinerary

/** A map centered on the current location, with optional overlays for marked hiking, cycling and
 *  mountain bike routes, and routes on foot, by bike or by car to any place picked on the map.
 */
Kirigami.Page {
    id: root

    title: i18nc("@title", "Map")
    padding: 0
    Kirigami.ColumnView.preventStealing: true

    /** Marked routes shown on top of the map: "", "hiking", "cycling" or "mtb". */
    property string overlay: Settings.read("MapPage/Overlay", "")
    property QtLocation.Map overlayMap
    /** Keep the map centered on the current position, until the user moves the map. */
    property bool followPosition: true
    /** The place picked on the map, to go to. */
    property var pickedCoordinate

    // the plugin of a map can't be changed once set, so the overlay map is recreated when the overlay changes
    onOverlayChanged: root.applyOverlay()
    function applyOverlay(): void {
        if (root.overlayMap) {
            root.overlayMap.destroy();
        }
        root.overlayMap = overlayMapComponent.createObject(map.parent);
        root.overlayMap.plugin = root.overlay === "" ? emptyOverlayPlugin : trailsPluginComponent.createObject(root.overlayMap);
        root.overlayMap.activeMapType = root.overlayMap.supportedMapTypes[root.overlayMap.supportedMapTypes.length - 1];
        Settings.write("MapPage/Overlay", root.overlay);
    }

    Component.onCompleted: {
        root.applyOverlay();
        if (locationPermission.status !== Qt.Granted) {
            locationPermission.request();
        }
    }

    function startNavigation(mode: int): void {
        root.QQC2.ApplicationWindow.window.pageStack.layers.push(Qt.createComponent("org.kde.itinerary", "WalkingNavigationPage"), {
            destination: helper.locationAt(root.pickedCoordinate.latitude, root.pickedCoordinate.longitude, i18nc("@info a place picked on the map", "Selected place")),
            travelMode: mode,
        });
    }

    // only used for its helper functions
    WalkingNavigationController {
        id: helper
    }

    QQC2.ActionGroup { id: overlayGroup }
    actions: [
        Kirigami.Action {
            text: i18nc("@action:inmenu map overlay", "Map Only")
            checkable: true
            checked: root.overlay === ""
            QQC2.ActionGroup.group: overlayGroup
            displayHint: Kirigami.DisplayHint.AlwaysHide
            onTriggered: root.overlay = ""
        },
        Kirigami.Action {
            text: i18nc("@action:inmenu map overlay", "Hiking Routes")
            checkable: true
            checked: root.overlay === "hiking"
            QQC2.ActionGroup.group: overlayGroup
            displayHint: Kirigami.DisplayHint.AlwaysHide
            onTriggered: root.overlay = "hiking"
        },
        Kirigami.Action {
            text: i18nc("@action:inmenu map overlay", "Cycling Routes")
            checkable: true
            checked: root.overlay === "cycling"
            QQC2.ActionGroup.group: overlayGroup
            displayHint: Kirigami.DisplayHint.AlwaysHide
            onTriggered: root.overlay = "cycling"
        },
        Kirigami.Action {
            text: i18nc("@action:inmenu map overlay", "Mountain Bike Routes")
            checkable: true
            checked: root.overlay === "mtb"
            QQC2.ActionGroup.group: overlayGroup
            displayHint: Kirigami.DisplayHint.AlwaysHide
            onTriggered: root.overlay = "mtb"
        }
    ]

    LocationPermission {
        id: locationPermission
        accuracy: LocationPermission.Precise
        availability: LocationPermission.WhenInUse
    }

    PositionSource {
        id: positionSource
        active: locationPermission.status === Qt.Granted && root.visible
        updateInterval: 2000
        onPositionChanged: {
            if (root.followPosition && positionSource.position.latitudeValid && positionSource.position.longitudeValid) {
                map.center = positionSource.position.coordinate;
            }
        }
    }

    MapView {
        id: map
        anchors.fill: parent
        zoomLevel: 15

        onUserInteractingChanged: {
            if (map.userInteracting) {
                root.followPosition = false;
            }
        }

        // the current position
        QtLocation.MapQuickItem {
            visible: positionSource.valid && positionSource.position.latitudeValid
            coordinate: positionSource.position.coordinate
            anchorPoint.x: positionMarker.width / 2
            anchorPoint.y: positionMarker.height / 2
            z: 10
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

        // the picked place
        MapCircle {
            visible: root.pickedCoordinate !== undefined
            coordinate: root.pickedCoordinate ?? QtPositioning.coordinate()
            color: "#232629"
            textColor: "#eff0f1"
            iconName: "flag"
            size: 24
        }

        TapHandler {
            onLongPressed: {
                root.pickedCoordinate = map.toCoordinate(point.position);
                routeMenu.popup();
            }
        }
    }

    QQC2.Menu {
        id: routeMenu
        QQC2.MenuItem {
            icon.name: "mark-location-symbolic"
            text: i18nc("@action:inmenu", "Walk Here")
            onTriggered: root.startNavigation(KPublicTransport.IndividualTransport.Walk)
        }
        QQC2.MenuItem {
            icon.name: "mark-location-symbolic"
            text: i18nc("@action:inmenu", "Cycle Here")
            onTriggered: root.startNavigation(KPublicTransport.IndividualTransport.Bike)
        }
        QQC2.MenuItem {
            icon.name: "mark-location-symbolic"
            text: i18nc("@action:inmenu", "Drive Here")
            onTriggered: root.startNavigation(KPublicTransport.IndividualTransport.Car)
        }
    }

    QtLocation.Plugin {
        id: emptyOverlayPlugin
        name: "itemsoverlay"
    }

    // marked routes from Waymarked Trails, https://waymarkedtrails.org
    Component {
        id: trailsPluginComponent
        QtLocation.Plugin {
            name: "osm"
            QtLocation.PluginParameter { name: "osm.useragent"; value: ApplicationController.userAgent }
            QtLocation.PluginParameter { name: "osm.mapping.custom.host"; value: "https://tile.waymarkedtrails.org/" + root.overlay + "/%z/%x/%y.png" }
            QtLocation.PluginParameter { name: "osm.mapping.providersrepository.disabled"; value: true }
            QtLocation.PluginParameter { name: "osm.mapping.custom.datacopyright"; value: "OpenStreetMap contributors" }
            QtLocation.PluginParameter { name: "osm.mapping.custom.mapcopyright"; value: "Waymarked Trails" }
            QtLocation.PluginParameter { name: "osm.mapping.cache.directory"; value: Util.cacheLocation("QtLocation-WaymarkedTrails/" + root.overlay) }
        }
    }

    Component {
        id: overlayMapComponent
        QtLocation.Map {
            anchors.fill: map
            center: map.center
            color: "transparent"
            minimumZoomLevel: map.minimumZoomLevel
            maximumZoomLevel: map.maximumZoomLevel
            zoomLevel: map.zoomLevel
            tilt: map.tilt
            bearing: map.bearing
            fieldOfView: map.fieldOfView
            copyrightsVisible: false
            z: map.z + 1
            // let input through to the map below
            enabled: false
        }
    }

    QQC2.Label {
        anchors {
            left: parent.left
            top: parent.top
            margins: Kirigami.Units.largeSpacing
        }
        visible: root.overlay !== ""
        text: i18nc("@info attribution of the hiking/cycling route overlay", "Routes: <a href=\"https://waymarkedtrails.org\">Waymarked Trails</a> (CC BY-SA)")
        textFormat: Text.RichText
        onLinkActivated: (link) => Qt.openUrlExternally(link)
        z: map.z + 2
        background: Rectangle {
            color: "#B0ffffff"
            radius: Kirigami.Units.cornerRadius
        }
        color: "#232629"
        padding: Kirigami.Units.smallSpacing
    }

    Components.FloatingButton {
        icon.name: "mark-location-symbolic"
        text: i18nc("@action:button", "Follow my location")
        visible: !root.followPosition
        z: map.z + 2
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
            bottomMargin: Kirigami.Units.gridUnit * 5
        }
    }
}
