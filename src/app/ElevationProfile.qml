// SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
// SPDX-License-Identifier: LGPL-2.0-or-later

import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

/** Elevation along a route, as a filled curve with the lowest and highest point labeled. */
Item {
    id: root

    /** Points of distance from the start (x) and elevation (y), in meters. */
    property var profile: []
    /** Computed from the profile if not set. */
    property real minElevation: NaN
    property real maxElevation: NaN
    /** Distance from the start to mark as the current position, NaN for none. */
    property real position: NaN

    readonly property real lowest: !isNaN(root.minElevation) ? root.minElevation : root.profile.reduce((m, p) => Math.min(m, p.y), Infinity)
    readonly property real highest: !isNaN(root.maxElevation) ? root.maxElevation : root.profile.reduce((m, p) => Math.max(m, p.y), -Infinity)

    implicitHeight: Kirigami.Units.gridUnit * 5
    visible: root.profile.length >= 2

    onProfileChanged: canvas.requestPaint()
    onPositionChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        anchors.leftMargin: maxLabel.width + Kirigami.Units.smallSpacing

        onPaint: {
            const ctx = canvas.getContext("2d");
            ctx.reset();
            const profile = root.profile;
            if (profile.length < 2) {
                return;
            }
            const length = profile[profile.length - 1].x;
            // leave some room, and show at least 50 m of elevation difference, flat routes shouldn't look steep
            const range = Math.max(root.highest - root.lowest, 50);
            const base = root.lowest - range * 0.1;
            const scaleY = canvas.height / (range * 1.2);
            const scaleX = canvas.width / Math.max(length, 1);

            ctx.beginPath();
            ctx.moveTo(0, canvas.height);
            for (let i = 0; i < profile.length; ++i) {
                ctx.lineTo(profile[i].x * scaleX, canvas.height - (profile[i].y - base) * scaleY);
            }
            ctx.lineTo(canvas.width, canvas.height);
            ctx.closePath();
            ctx.fillStyle = Qt.alpha(Kirigami.Theme.highlightColor, 0.3);
            ctx.fill();

            ctx.beginPath();
            for (let i = 0; i < profile.length; ++i) {
                const x = profile[i].x * scaleX;
                const y = canvas.height - (profile[i].y - base) * scaleY;
                if (i === 0) {
                    ctx.moveTo(x, y);
                } else {
                    ctx.lineTo(x, y);
                }
            }
            ctx.strokeStyle = Kirigami.Theme.highlightColor;
            ctx.lineWidth = 2;
            ctx.stroke();

            if (!isNaN(root.position) && root.position >= 0 && root.position <= length) {
                const x = root.position * scaleX;
                ctx.beginPath();
                ctx.moveTo(x, 0);
                ctx.lineTo(x, canvas.height);
                ctx.strokeStyle = Kirigami.Theme.textColor;
                ctx.lineWidth = 2;
                ctx.stroke();
            }
        }
    }

    QQC2.Label {
        id: maxLabel
        anchors.top: parent.top
        anchors.left: parent.left
        text: i18nc("@info elevation in meters", "%1 m", Math.round(root.highest))
        font: Kirigami.Theme.smallFont
        opacity: 0.7
    }
    QQC2.Label {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        text: i18nc("@info elevation in meters", "%1 m", Math.round(root.lowest))
        font: Kirigami.Theme.smallFont
        opacity: 0.7
    }
}
