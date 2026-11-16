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
import org.kde.coreaddons as CoreAddons
import org.kde.kpublictransport as KPublicTransport
import org.kde.kpublictransport.ui as KPublicTransportUi
import org.kde.itinerary

/** A map centered on the current location, with optional overlays for marked hiking, cycling and
 *  mountain bike routes, and routes on foot, by bike or by car to any place picked on the map.
 *  Tapping a marked route shows its course and elevation profile, and allows to follow it.
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
    onOverlayChanged: {
        markedRoutes.clearRoute();
        root.applyOverlay();
    }
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

    MarkedRouteController {
        id: markedRoutes
        routeType: root.overlay === "" ? "hiking" : root.overlay
        onRouteChanged: {
            if (markedRoutes.hasRoute && !root.routeShown) {
                root.routeShown = true;
                root.followPosition = false;
                map.fitViewportToGeoShape(QtPositioning.path(KPublicTransportUi.MapUtils.polyline(markedRoutes.path)), Kirigami.Units.gridUnit * 2);
            }
        }
    }
    /** The loaded marked route has been brought into view. */
    property bool routeShown: false
    /** The list of routes at a tapped place is shown. */
    property bool routeListShown: false

    function followRoute(): void {
        const path = KPublicTransportUi.MapUtils.polyline(markedRoutes.path);
        const end = path[path.length - 1];
        root.QQC2.ApplicationWindow.window.pageStack.layers.push(Qt.createComponent("org.kde.itinerary", "WalkingNavigationPage"), {
            destination: helper.locationAt(end.latitude, end.longitude, markedRoutes.routeName),
            travelMode: root.overlay === "hiking" ? KPublicTransport.IndividualTransport.Walk : KPublicTransport.IndividualTransport.Bike,
            trail: markedRoutes.path,
        });
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

        // the marked route shown
        QtLocation.MapPolyline {
            visible: markedRoutes.hasRoute
            line.width: 8
            line.color: Kirigami.Theme.highlightColor
            path: KPublicTransportUi.MapUtils.polyline(markedRoutes.path)
            z: 5
        }

        TapHandler {
            onTapped: (eventPoint) => {
                if (root.overlay === "" || markedRoutes.hasRoute) {
                    return;
                }
                // routes within a finger's width
                const coord = map.toCoordinate(eventPoint.position);
                const radius = coord.distanceTo(map.toCoordinate(Qt.point(eventPoint.position.x + Kirigami.Units.gridUnit * 1.5, eventPoint.position.y)));
                root.routeListShown = true;
                markedRoutes.findRoutes(coord.latitude, coord.longitude, radius);
            }
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
            // fade out other routes, so the selected one stands out
            opacity: markedRoutes.hasRoute ? 0.3 : 1.0
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

    // routes at a tapped place, or the selected route
    QQC2.Pane {
        id: routePane
        visible: root.routeListShown || markedRoutes.hasRoute
        z: map.z + 3
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        Kirigami.Theme.colorSet: Kirigami.Theme.View
        Kirigami.Theme.inherit: false

        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                Image {
                    source: markedRoutes.routeSymbolUrl
                    visible: markedRoutes.hasRoute && markedRoutes.routeSymbolUrl !== ""
                    sourceSize.height: Kirigami.Units.iconSizes.medium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                    fillMode: Image.PreserveAspectFit
                }
                Kirigami.Heading {
                    level: 3
                    text: markedRoutes.hasRoute ? markedRoutes.routeName : i18nc("@title", "Marked Routes Here")
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                QQC2.BusyIndicator {
                    running: markedRoutes.loading
                    visible: running
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                }
                QQC2.ToolButton {
                    icon.name: "window-close-symbolic"
                    text: i18nc("@action:button", "Close")
                    display: QQC2.AbstractButton.IconOnly
                    onClicked: {
                        markedRoutes.clearRoute();
                        root.routeListShown = false;
                        root.routeShown = false;
                    }
                }
            }

            QQC2.Label {
                text: markedRoutes.errorMessage
                visible: text !== ""
                wrapMode: Text.WordWrap
                color: Kirigami.Theme.negativeTextColor
                Layout.fillWidth: true
            }
            QQC2.Label {
                text: i18nc("@info", "No marked routes here. Tap on a route on the map.")
                visible: !markedRoutes.hasRoute && !markedRoutes.loading && markedRoutes.routes.length === 0 && markedRoutes.errorMessage === ""
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            // the routes at the tapped place
            ListView {
                visible: !markedRoutes.hasRoute
                model: markedRoutes.routes
                clip: true
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, root.height * 0.35)
                delegate: QQC2.ItemDelegate {
                    id: routeDelegate
                    required property var modelData
                    width: ListView.view.width
                    contentItem: RowLayout {
                        spacing: Kirigami.Units.largeSpacing
                        Image {
                            source: routeDelegate.modelData.symbolUrl
                            sourceSize.height: Kirigami.Units.iconSizes.medium
                            Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                            Layout.preferredWidth: Kirigami.Units.iconSizes.medium * 1.5
                            fillMode: Image.PreserveAspectFit
                        }
                        ColumnLayout {
                            spacing: 0
                            Layout.fillWidth: true
                            QQC2.Label {
                                text: routeDelegate.modelData.name !== "" ? routeDelegate.modelData.name : routeDelegate.modelData.ref
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            QQC2.Label {
                                text: routeDelegate.modelData.itinerary
                                visible: text !== ""
                                elide: Text.ElideRight
                                font: Kirigami.Theme.smallFont
                                opacity: 0.7
                                Layout.fillWidth: true
                            }
                        }
                    }
                    onClicked: markedRoutes.loadRoute(routeDelegate.modelData.id)
                }
            }

            // the selected route
            QQC2.Label {
                visible: markedRoutes.hasRoute
                text: {
                    const length = CoreAddons.Format.formatDistance(markedRoutes.length, Settings.distanceFormat);
                    if (isNaN(markedRoutes.ascent)) {
                        return length;
                    }
                    return i18nc("@info route length, total ascent and descent", "%1 · ↑ %2 m · ↓ %3 m", length, Math.round(markedRoutes.ascent), Math.round(markedRoutes.descent));
                }
                Layout.fillWidth: true
            }
            QQC2.Label {
                visible: markedRoutes.hasRoute && text !== ""
                text: markedRoutes.routeDescription
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                opacity: 0.7
                Layout.fillWidth: true
            }
            ElevationProfile {
                visible: markedRoutes.hasRoute && markedRoutes.elevationProfile.length >= 2
                profile: markedRoutes.elevationProfile
                minElevation: markedRoutes.minElevation
                maxElevation: markedRoutes.maxElevation
                Layout.fillWidth: true
            }
            RowLayout {
                visible: markedRoutes.hasRoute
                Layout.fillWidth: true
                QQC2.Button {
                    icon.name: "mark-location-symbolic"
                    text: i18nc("@action:button", "Follow Route")
                    onClicked: root.followRoute()
                }
                QQC2.ToolButton {
                    icon.name: "exchange-positions"
                    text: i18nc("@action:button", "Reverse")
                    onClicked: markedRoutes.reverseRoute()
                }
                Item { Layout.fillWidth: true }
                QQC2.ToolButton {
                    icon.name: "internet-services"
                    text: i18nc("@action:button", "Website")
                    display: QQC2.AbstractButton.IconOnly
                    onClicked: Qt.openUrlExternally(markedRoutes.routeWebUrl)
                }
            }
        }
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
            bottom: routePane.visible ? routePane.top : parent.bottom
            margins: Kirigami.Units.largeSpacing
            bottomMargin: routePane.visible ? Kirigami.Units.largeSpacing : Kirigami.Units.gridUnit * 5
        }
    }
}
