/*
    SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

#ifndef WALKINGNAVIGATIONCONTROLLER_H
#define WALKINGNAVIGATIONCONTROLLER_H

#include "speechoutput.h"

#include <KPublicTransport/Journey>
#include <KPublicTransport/JourneyRequest>
#include <KPublicTransport/Location>
#include <KPublicTransport/Path>

#include <QDateTime>
#include <QObject>
#include <QQmlEngine>

#include <vector>

/** Turn-by-turn navigation on foot, by bike or by car along a KPublicTransport path, e.g. to a departure stop.
 *
 *  Feed it the current position, and it tracks progress along the path, provides the upcoming instruction,
 *  announces instructions by voice, detects arrival, and asks for a new route when the user left the path.
 */
class WalkingNavigationController : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    /** The path to follow. */
    Q_PROPERTY(KPublicTransport::Path path READ path WRITE setPath NOTIFY pathChanged)
    /** The destination, e.g. the departure stop. */
    Q_PROPERTY(KPublicTransport::Location destination READ destination WRITE setDestination NOTIFY destinationChanged)
    /** How we travel, a KPublicTransport::IndividualTransport::Mode. Determines routing and when instructions are announced. */
    Q_PROPERTY(int travelMode READ travelMode WRITE setTravelMode NOTIFY travelModeChanged)
    /** A route to follow, such as a marked hiking trail. When away from it, routes are found to its
     *  nearest point and continue along it, see rejoinLocation() and joinTrail().
     */
    Q_PROPERTY(KPublicTransport::Path trail READ trail WRITE setTrail NOTIFY trailChanged)
    /** Announce instructions by voice. */
    Q_PROPERTY(bool speechEnabled MEMBER m_speechEnabled NOTIFY speechEnabledChanged)

    Q_PROPERTY(bool hasRoute READ hasRoute NOTIFY pathChanged)
    Q_PROPERTY(bool hasPosition READ hasPosition NOTIFY progressChanged)
    /** The instruction for the next maneuver. */
    Q_PROPERTY(QString instruction READ instruction NOTIFY progressChanged)
    /** Icon of the next maneuver. */
    Q_PROPERTY(QString instructionIconName READ instructionIconName NOTIFY progressChanged)
    /** Distance to the next maneuver, in meters. */
    Q_PROPERTY(double distanceToInstruction READ distanceToInstruction NOTIFY progressChanged)
    /** Remaining distance to the destination along the path, in meters. */
    Q_PROPERTY(double distanceRemaining READ distanceRemaining NOTIFY progressChanged)
    Q_PROPERTY(bool offRoute READ offRoute NOTIFY progressChanged)
    Q_PROPERTY(bool arrived READ arrived NOTIFY progressChanged)

public:
    explicit WalkingNavigationController(QObject *parent = nullptr);
    ~WalkingNavigationController() override;

    [[nodiscard]] KPublicTransport::Path path() const;
    void setPath(const KPublicTransport::Path &path);
    [[nodiscard]] KPublicTransport::Location destination() const;
    void setDestination(const KPublicTransport::Location &destination);
    [[nodiscard]] int travelMode() const;
    void setTravelMode(int mode);
    [[nodiscard]] KPublicTransport::Path trail() const;
    void setTrail(const KPublicTransport::Path &trail);

    [[nodiscard]] bool hasRoute() const;
    [[nodiscard]] bool hasPosition() const;
    [[nodiscard]] QString instruction() const;
    [[nodiscard]] QString instructionIconName() const;
    [[nodiscard]] double distanceToInstruction() const;
    [[nodiscard]] double distanceRemaining() const;
    [[nodiscard]] bool offRoute() const;
    [[nodiscard]] bool arrived() const;

    /** Update the current position. @p accuracy in meters, 0 if unknown. */
    Q_INVOKABLE void updatePosition(double latitude, double longitude, double accuracy);

    /** A request for a direct journey with the current travel mode from the given position to @p destination. */
    Q_INVOKABLE [[nodiscard]] KPublicTransport::JourneyRequest routeRequest(double latitude, double longitude, const KPublicTransport::Location &destination) const;
    /** The path to follow for a journey, i.e. the paths of its leading sections not using public transport combined. */
    Q_INVOKABLE [[nodiscard]] static KPublicTransport::Path routePath(const KPublicTransport::Journey &journey);
    /** A location at the given coordinate, e.g. for a destination picked on a map. */
    Q_INVOKABLE [[nodiscard]] static KPublicTransport::Location locationAt(double latitude, double longitude, const QString &name);
    /** The point of the trail closest to the given position, to find a route to. */
    Q_INVOKABLE [[nodiscard]] KPublicTransport::Location rejoinLocation(double latitude, double longitude);
    /** @p approach followed by the trail from the point returned by the last call of rejoinLocation(). */
    Q_INVOKABLE [[nodiscard]] KPublicTransport::Path joinTrail(const KPublicTransport::Path &approach) const;

Q_SIGNALS:
    void pathChanged();
    void destinationChanged();
    void travelModeChanged();
    void trailChanged();
    void speechEnabledChanged();
    void progressChanged();
    /** A new route from the given position is needed, as there is none or the user left it. */
    void rerouteRequested(double latitude, double longitude);

private:
    struct Point {
        double latitude;
        double longitude;
        double distance; ///< along the path from its start, in meters
    };

    void rebuildGeometry();
    void processPosition(double latitude, double longitude, double accuracy);
    void speak(const QString &text);
    /** Keep the navigation notification (and the foreground service behind it on Android) up to date. */
    void updateNotification();
    void stopNotification();

    /** Distances (in meters) for announcements and route tracking, depending on the travel mode. */
    struct Thresholds {
        double announceAhead;
        double announceNow;
        double arrival;
        double offRoute;
        double backOnRoute;
    };
    [[nodiscard]] Thresholds thresholds() const;

    KPublicTransport::Path m_path;
    KPublicTransport::Location m_destination;
    bool m_speechEnabled = true;
    int m_travelMode = 0; // KPublicTransport::IndividualTransport::Walk

    std::vector<Point> m_points;
    std::vector<double> m_sectionStartDistance; ///< for each path section
    double m_totalDistance = 0.0;

    bool m_hasPosition = false;
    double m_distanceAlong = 0.0;
    int m_currentSection = -1;
    bool m_offRoute = false;
    int m_offRouteCount = 0;
    bool m_arrived = false;
    QDateTime m_lastRerouteRequest;

    int m_announcedSection = -1; ///< next section whose instruction was announced in advance
    int m_announcedNowSection = -1; ///< next section whose instruction was announced when reaching it
    bool m_announcedStart = false;

    SpeechOutput m_speech;
    KPublicTransport::Path m_trail;
    // where to rejoin the trail: section, index of the segment's first point, and the point itself
    int m_rejoinSection = 0;
    qsizetype m_rejoinSegment = 0;
    QPointF m_rejoinPoint;
    bool m_notificationShown = false;
    /** The position has been on the current route, so leaving it is worth an announcement. */
    bool m_beenOnRoute = false;
    QString m_notificationText;
};

#endif // WALKINGNAVIGATIONCONTROLLER_H
