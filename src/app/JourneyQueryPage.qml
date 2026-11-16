/*
    SPDX-FileCopyrightText: 2019-2021 Volker Krause <vkrause@kde.org>
    SPDX-FileCopyrightText: 2023 Carl Schwan <carl@carlschwan.eu>

    SPDX-License-Identifier: LGPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kitemmodels
import org.kde.kpublictransport
import org.kde.itinerary
import org.kde.kirigamiaddons.formcard as FormCard

Kirigami.ScrollablePage {
    id: root

    /** The journey selected by the user on this page. */
    property var journey
    /** The journey to query for. */
    property alias journeyRequest: journeyModel.request
    property alias publicTransportManager: journeyModel.manager
    /** Label of the button for selecting a journey, describing what selecting it does. */
    property string selectText: i18n("Select")

    /** Showing results for an arrival query. */
    readonly property bool isArrival: root.journeyRequest.dateTimeMode == JourneyRequest.Arrival

    /** Also show journeys departing before the requested time.
     *  Backends tend to include a few of those, which aren't useful unless explicitly asked for.
     */
    property bool showEarlierJourneys: false
    onShowEarlierJourneysChanged: sortedJourneyModel.invalidateFilter()

    /** Show the results on a time axis rather than as a list.
     *  The timeline shows the entire day, including journeys that already departed.
     */
    readonly property bool showTimeline: Settings.journeyResultsAsTimeline
    onShowTimelineChanged: {
        sortedJourneyModel.invalidateFilter();
        Qt.callLater(root.loadRestOfDay);
    }

    // state for loadRestOfDay()
    readonly property double dayMs: 24 * 60 * 60 * 1000
    /** The time range to load journeys for in timeline mode.
     *  Initially the service day of the requested time, which like for the railways runs from 03:00 to 03:00.
     */
    property double loadRangeStart: 0
    property double loadRangeEnd: 0
    property int dayLoadQueries: 0
    property double lastEarliestDeparture: 0
    property double lastLatestDeparture: 0

    function initLoadRange(): void {
        const start = new Date(root.journeyRequest.dateTime);
        if (start.getHours() < 3) {
            start.setDate(start.getDate() - 1);
        }
        start.setHours(3, 0, 0, 0);
        root.loadRangeStart = start.getTime();
        root.loadRangeEnd = start.getTime() + root.dayMs;
    }

    /** Extend the time range to load by one day, earlier or later. */
    function extendLoadRange(earlier: bool): void {
        if (journeyModel.loading || (earlier ? !journeyModel.canQueryPrevious : !journeyModel.canQueryNext)) {
            return;
        }
        if (earlier) {
            root.loadRangeStart -= root.dayMs;
            root.lastEarliestDeparture = 0;
        } else {
            root.loadRangeEnd += root.dayMs;
            root.lastLatestDeparture = 0;
        }
        root.dayLoadQueries = 0;
        root.loadRestOfDay();
    }

    /** In timeline mode, load further journeys until the time range to load is covered.
     *  One query at a time, and only as long as queries actually extend the covered time range.
     */
    function loadRestOfDay(): void {
        if (!root.showTimeline || journeyModel.loading || root.dayLoadQueries >= 20) {
            return;
        }
        if (root.loadRangeEnd === 0) {
            root.initLoadRange();
        }
        let earliest = Number.MAX_VALUE;
        let latest = 0;
        for (let row = 0; row < journeyModel.rowCount(); ++row) {
            const departure = journeyModel.data(journeyModel.index(row, 0), JourneyQueryModel.JourneyRole).scheduledDepartureTime.getTime();
            earliest = Math.min(earliest, departure);
            latest = Math.max(latest, departure);
        }
        if (latest === 0) {
            return;
        }
        if (journeyModel.canQueryPrevious && earliest > root.loadRangeStart && earliest !== root.lastEarliestDeparture) {
            root.lastEarliestDeparture = earliest;
            ++root.dayLoadQueries;
            journeyModel.queryPrevious();
        } else if (journeyModel.canQueryNext && latest < root.loadRangeEnd && latest !== root.lastLatestDeparture) {
            root.lastLatestDeparture = latest;
            ++root.dayLoadQueries;
            journeyModel.queryNext();
        }
    }

    // load the next or previous day when scrolling to the end of the timeline
    Connections {
        target: journeyView
        enabled: root.showTimeline
        function onAtYEndChanged(): void {
            if (journeyView.atYEnd && journeyView.moving) {
                root.extendLoadRange(false);
            }
        }
        function onAtYBeginningChanged(): void {
            if (journeyView.atYBeginning && journeyView.moving) {
                root.extendLoadRange(true);
            }
        }
    }

    Connections {
        target: journeyModel
        function onLoadingChanged(): void {
            if (!journeyModel.loading) {
                Qt.callLater(root.loadRestOfDay);
            }
        }
    }

    actions: [
        Kirigami.Action {
            icon.name: root.showTimeline ? "view-list-details" : "view-calendar-day"
            text: root.showTimeline ? i18nc("@action:button", "Show as List") : i18nc("@action:button", "Show as Timeline")
            onTriggered: Settings.journeyResultsAsTimeline = !Settings.journeyResultsAsTimeline
        }
    ]

    /** Details of a single journey, with the actions for it. */
    component JourneyDetailsLayout: ColumnLayout {
        id: detailsLayout

        required property var journey
        required property string selectText

        signal selected()

        spacing: 0

        Repeater {
            id: sectionRepeater
            delegate: JourneySectionDelegate {
                Layout.fillWidth: true
                modelLength: sectionRepeater.count - 1
            }
            model: detailsLayout.journey.sections
        }

        FormCard.FormDelegateSeparator {
            above: bookButton
            visible: bookButton.visible
        }
        FormCard.FormButtonDelegate {
            id: bookButton
            text: i18nc("purchase a ticket", "Book")
            icon.name: "view-financial-account-cash-symbolic"
            visible: detailsLayout.journey.bookingUrl != "" && detailsLayout.journey.disruptionEffect !== Disruption.NoService
            onClicked: Qt.openUrlExternally(detailsLayout.journey.bookingUrl)
        }

        FormCard.FormDelegateSeparator {
            above: selectButton
        }

        FormCard.FormButtonDelegate {
            id: selectButton

            text: detailsLayout.selectText
            icon.name: "checkmark"
            enabled: detailsLayout.journey.disruptionEffect !== Disruption.NoService
            onClicked: detailsLayout.selected()
        }
    }

    readonly property KSortFilterProxyModel journeyProxyModel: KSortFilterProxyModel {
        id: sortedJourneyModel

        sourceModel: JourneyQueryModel {
            id: journeyModel
        }
        sortRole: JourneyQueryModel.ScheduledDepartureTime
        dynamicSortFilter: true
        filterRowCallback: function(sourceRow, sourceParent) {
            if (root.isArrival || root.showEarlierJourneys || root.showTimeline) {
                return true;
            }
            const journey = sourceModel.data(sourceModel.index(sourceRow, 0, sourceParent), JourneyQueryModel.JourneyRole);
            // what matters is when the first train, bus, etc. leaves, not when walking to it would have to start
            let departing = journey;
            for (const section of journey.sections) {
                if (section.mode === JourneySection.PublicTransport) {
                    departing = section;
                    break;
                }
            }
            const departure = departing.hasExpectedDepartureTime ? departing.expectedDepartureTime : departing.scheduledDepartureTime;
            // the requested time is picked with minute precision, so compare with that
            const requested = new Date(root.journeyRequest.dateTime);
            requested.setSeconds(0, 0);
            return departure.getTime() >= requested.getTime();
        }
        Component.onCompleted: Util.sortModel(sortedJourneyModel, 0, Qt.Ascending)
    }

    Component {
        id: journeyDetailsPage

        FormCard.FormCardPage {
            id: detailsPage

            property var journey

            title: i18nc("@title", "Connection Details")

            FormCard.FormCard {
                Layout.topMargin: Kirigami.Units.largeSpacing

                JourneyDetailsLayout {
                    journey: detailsPage.journey
                    selectText: root.selectText
                    onSelected: root.journey = detailsPage.journey
                }
            }
        }
    }

    Component {
        id: earlierButtonComponent

        VerticalNavigationButton {
            visible: journeyModel.canQueryPrevious
            width: journeyView.width
            text: i18nc("@action:button", "Load earlier connections")
            iconName: "go-up-symbolic"
            onClicked: {
                root.showEarlierJourneys = true;
                journeyModel.queryPrevious();
            }
        }
    }

    Component {
        id: timelineComponent

        JourneyTimelineView {
            width: journeyView.width
            journeys: sortedJourneyModel
            verticalFlickable: journeyView
            focusTime: root.journeyRequest.dateTime
            canQueryPrevious: journeyModel.canQueryPrevious
            canQueryNext: journeyModel.canQueryNext
            onQueryPrevious: {
                root.showEarlierJourneys = true;
                journeyModel.queryPrevious();
            }
            onQueryNext: journeyModel.queryNext()
            onJourneyClicked: (journey) => root.QQC2.ApplicationWindow.window.pageStack.push(journeyDetailsPage, { journey: journey })
        }
    }

    Kirigami.Theme.inherit: false
    Kirigami.Theme.colorSet: Kirigami.Theme.Window

    // summary of what we are searching for, so it's clear which results these are
    header: QQC2.Control {
        visible: root.journeyRequest.from.name !== "" && root.journeyRequest.to.name !== ""
        padding: Kirigami.Units.largeSpacing

        Kirigami.Theme.inherit: false
        Kirigami.Theme.colorSet: Kirigami.Theme.Header

        background: Rectangle {
            color: Kirigami.Theme.backgroundColor

            Kirigami.Separator {
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }
            }
        }

        contentItem: ColumnLayout {
            spacing: 0

            QQC2.Label {
                text: i18nc("journey from departure to arrival stop", "%1 → %2", root.journeyRequest.from.name, root.journeyRequest.to.name)
                font.bold: true
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            QQC2.Label {
                readonly property string dateTime: root.journeyRequest.dateTime.toLocaleString(Qt.locale(), Locale.ShortFormat)
                text: root.isArrival ? i18nc("@info journey search, arrival time", "Arriving by %1", dateTime)
                                     : i18nc("@info journey search, departure time", "Departing from %1", dateTime)
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.disabledTextColor
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }
    }

    ListView {
        id: journeyView

        clip: true
        reuseItems: true
        cacheBuffer: height

        delegate: root.showTimeline ? timelineComponent : listDelegate

        Component {
            id: listDelegate

            FormCard.FormCard {
                id: topDelegate

                required property int index
                required property var journey
                width: ListView.view.width
                height: loader.status === Loader.Ready ? loader.item.implicitHeight : 100 // TODO can we predict the height accurately?

                Loader {
                    id: loader
                    Layout.fillWidth: true

                    Rectangle {
                        id: loadingAnimationItem
                        color: Kirigami.Theme.backgroundColor
                        anchors.fill: parent

                        z: 1000

                        OpacityAnimator {
                            target: loadingAnimationItem
                            from: 1
                            to: 0
                            duration: Kirigami.Units.shortDuration
                            running: loader.status === Loader.Ready
                        }
                    }

                    visible: loader.status === Loader.Ready
                    asynchronous: true
                    sourceComponent: Loader {
                        Layout.fillWidth: true

                        Component {
                            id: expanded

                            JourneyDetailsLayout {
                                journey: topDelegate.journey
                                selectText: root.selectText
                                onSelected: root.journey = topDelegate.journey
                            }
                        }

                        Component {
                            id: compact

                            JourneySummaryDelegate {
                                id: summaryButton

                                journey: topDelegate.journey

                                onClicked: journeyView.currentIndex = topDelegate.index

                                Layout.fillWidth: true
                            }
                        }

                        sourceComponent: journeyView.currentIndex == topDelegate.index ? expanded : compact
                    }
                }
            }
        }

        section {
            property: root.showTimeline ? "" : (root.isArrival ? "scheduledArrivalDate" : "scheduledDepartureDate")
            delegate: TimelineSectionDelegate {
                required property string section
                day: section
            }
        }

        // the timeline is a single item showing all journeys
        model: root.showTimeline ? 1 : sortedJourneyModel

        spacing: Kirigami.Units.largeSpacing

        header: root.showTimeline ? null : earlierButtonComponent

        footer: ColumnLayout {
            width: journeyView.width
            spacing: 0

            VerticalNavigationButton {
                visible: journeyModel.canQueryNext && !root.showTimeline
                Layout.fillWidth: true
                iconName: "go-down-symbolic"
                text: i18nc("@action:button", "Load later connections")
                onClicked: journeyModel.queryNext()
            }

            FormCard.FormCard {
                visible: journeyModel.attributions.length > 0

                FormCard.FormTextDelegate {
                    text: i18n("Data providers:")
                    description: PublicTransport.attributionSummary(journeyModel.attributions)
                    onLinkActivated: (link) => { Qt.openUrlExternally(link); }
                }
            }
        }

        Kirigami.LoadingPlaceholder {
            text: if (journeyModel.loading) {
                return i18nc("@info:placeholder", "Loading");
            } else if (journeyModel.errorMessage.length > 0) {
                return i18nc("@info:status", "Error")
            } else {
                return i18nc("@info:placeholder", "No journeys found")
            }
            visible: sortedJourneyModel.count === 0

            icon.name: journeyModel.errorMessage.length > 0 ? "network-disconnect-symbolic" : ""
            explanation: journeyModel.errorMessage
            progressBar.visible: journeyModel.loading
            anchors.centerIn: parent
            width: parent.width - Kirigami.Units.gridUnit * 4
        }

        // when searching for arrivals the closest result is at the bottom of the list
        // so jump there once the first result batch has been added
        // ideally we'd want to automatically move there also for subsequent batches *unless*
        // the user has meanwhile altered the scroll position manually, but that's hard to detect reliably
        property int previousCount: 0
        onCountChanged: {
            if (root.isArrival && previousCount === 0) {
                Qt.callLater(positionViewAtEnd);
            }
            previousCount = count;
        }
    }

    footer: ColumnLayout {
        spacing: 0
        height: indicator.running ? layout.implicitHeight : 0
        visible: journeyModel.loading && sortedJourneyModel.count !== 0

        Behavior on height {
            NumberAnimation { duration: Kirigami.Units.shortDuration }
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        RowLayout {
            id: layout

            QQC2.BusyIndicator {
                id: indicator
                running: journeyModel.loading && sortedJourneyModel.count !== 0
            }

            QQC2.Label {
                text: i18n("Still fetching results…")
            }

            Item {
                Layout.fillWidth: true
            }
        }
    }
}
