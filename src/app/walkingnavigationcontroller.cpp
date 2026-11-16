/*
    SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

#include "walkingnavigationcontroller.h"

#include "logging.h"

#include <KLocalizedString>

#include <cmath>

using namespace Qt::Literals;

// distances in meters
constexpr inline double AnnounceAheadDistance = 40.0;
constexpr inline double AnnounceNowDistance = 10.0;
constexpr inline double ArrivalDistance = 15.0;
constexpr inline double OffRouteDistance = 35.0;
constexpr inline double BackOnRouteDistance = 20.0;
constexpr inline int OffRouteUpdates = 3; // consecutive position updates
constexpr inline int RerouteIntervalSecs = 20;
constexpr inline double EarthRadius = 6371000.0;

static double toRadians(double degrees)
{
    return degrees * M_PI / 180.0;
}

static double haversineDistance(double lat1, double lon1, double lat2, double lon2)
{
    const auto dLat = toRadians(lat2 - lat1);
    const auto dLon = toRadians(lon2 - lon1);
    const auto a = std::sin(dLat / 2) * std::sin(dLat / 2) + std::cos(toRadians(lat1)) * std::cos(toRadians(lat2)) * std::sin(dLon / 2) * std::sin(dLon / 2);
    return 2.0 * EarthRadius * std::atan2(std::sqrt(a), std::sqrt(1.0 - a));
}

WalkingNavigationController::WalkingNavigationController(QObject *parent)
    : QObject(parent)
{
}

WalkingNavigationController::~WalkingNavigationController() = default;

KPublicTransport::Path WalkingNavigationController::path() const
{
    return m_path;
}

void WalkingNavigationController::setPath(const KPublicTransport::Path &path)
{
    m_path = path;
    m_offRoute = false;
    m_offRouteCount = 0;
    m_announcedSection = -1;
    m_announcedNowSection = -1;
    m_currentSection = -1;
    rebuildGeometry();
    Q_EMIT pathChanged();
    Q_EMIT progressChanged();
}

KPublicTransport::Location WalkingNavigationController::destination() const
{
    return m_destination;
}

void WalkingNavigationController::setDestination(const KPublicTransport::Location &destination)
{
    m_destination = destination;
    Q_EMIT destinationChanged();
}

void WalkingNavigationController::rebuildGeometry()
{
    m_points.clear();
    m_sectionStartDistance.clear();
    m_totalDistance = 0.0;

    for (const auto &section : m_path.sections()) {
        m_sectionStartDistance.push_back(m_totalDistance);
        for (const auto &p : section.path()) {
            // the polygons use x for the longitude and y for the latitude
            if (!m_points.empty()) {
                const auto &prev = m_points.back();
                const auto d = haversineDistance(prev.latitude, prev.longitude, p.y(), p.x());
                if (d < 0.01) {
                    continue; // section boundaries repeat the point
                }
                m_totalDistance += d;
            }
            m_points.push_back({p.y(), p.x(), m_totalDistance});
        }
    }
}

bool WalkingNavigationController::hasRoute() const
{
    return m_points.size() >= 2;
}

bool WalkingNavigationController::hasPosition() const
{
    return m_hasPosition;
}

QString WalkingNavigationController::instruction() const
{
    if (!hasRoute()) {
        return {};
    }
    if (m_arrived) {
        return i18nc("@info walking navigation", "You have arrived at %1", m_destination.name());
    }
    const auto next = m_currentSection + 1;
    if (next >= 1 && next < (int)m_path.sections().size()) {
        const auto description = m_path.sections()[next].description();
        if (!description.isEmpty()) {
            return description;
        }
        return i18nc("@info walking navigation", "Continue");
    }
    if (m_currentSection < 0 && !m_path.sections().empty()) {
        return m_path.sections().front().description();
    }
    return i18nc("@info walking navigation", "Walk to %1", m_destination.name());
}

QString WalkingNavigationController::instructionIconName() const
{
    if (m_arrived || !hasRoute()) {
        return u"flag"_s;
    }
    const auto next = m_currentSection + 1;
    if (next >= 1 && next < (int)m_path.sections().size()) {
        return m_path.sections()[next].iconName();
    }
    return u"flag"_s;
}

double WalkingNavigationController::distanceToInstruction() const
{
    const auto next = m_currentSection + 1;
    if (next >= 1 && next < (int)m_sectionStartDistance.size()) {
        return std::max(0.0, m_sectionStartDistance[next] - m_distanceAlong);
    }
    return distanceRemaining();
}

double WalkingNavigationController::distanceRemaining() const
{
    return std::max(0.0, m_totalDistance - m_distanceAlong);
}

bool WalkingNavigationController::offRoute() const
{
    return m_offRoute;
}

bool WalkingNavigationController::arrived() const
{
    return m_arrived;
}

void WalkingNavigationController::speak(const QString &text)
{
    if (m_speechEnabled && !text.isEmpty()) {
        m_speech.speak(text);
    }
}

void WalkingNavigationController::updatePosition(double latitude, double longitude, double accuracy)
{
    const bool firstPosition = !m_hasPosition;
    m_hasPosition = true;

    if (!hasRoute()) {
        if (firstPosition || m_lastRerouteRequest.secsTo(QDateTime::currentDateTime()) >= RerouteIntervalSecs) {
            m_lastRerouteRequest = QDateTime::currentDateTime();
            Q_EMIT rerouteRequested(latitude, longitude);
        }
        Q_EMIT progressChanged();
        return;
    }

    // closest point on the path, using a local equirectangular projection around the current position
    const auto cosLat = std::cos(toRadians(latitude));
    const auto toX = [&](double lon) { return toRadians(lon - longitude) * cosLat * EarthRadius; };
    const auto toY = [&](double lat) { return toRadians(lat - latitude) * EarthRadius; };
    double bestDistance = std::numeric_limits<double>::max();
    double bestAlong = 0.0;
    for (std::size_t i = 0; i + 1 < m_points.size(); ++i) {
        const auto ax = toX(m_points[i].longitude), ay = toY(m_points[i].latitude);
        const auto bx = toX(m_points[i + 1].longitude), by = toY(m_points[i + 1].latitude);
        const auto dx = bx - ax, dy = by - ay;
        const auto lengthSquared = dx * dx + dy * dy;
        const auto t = lengthSquared > 0.0 ? std::clamp(-(ax * dx + ay * dy) / lengthSquared, 0.0, 1.0) : 0.0;
        const auto px = ax + t * dx, py = ay + t * dy;
        const auto distance = std::sqrt(px * px + py * py);
        if (distance < bestDistance) {
            bestDistance = distance;
            bestAlong = m_points[i].distance + t * (m_points[i + 1].distance - m_points[i].distance);
        }
    }

    // off the route? GPS jitter is common, so require a few updates in a row, and consider the accuracy
    const auto offRouteThreshold = std::max(OffRouteDistance, 1.5 * accuracy);
    if (bestDistance > offRouteThreshold) {
        ++m_offRouteCount;
    } else if (bestDistance < BackOnRouteDistance) {
        m_offRouteCount = 0;
        m_offRoute = false;
    }
    if (m_offRouteCount >= OffRouteUpdates || (firstPosition && bestDistance > offRouteThreshold)) {
        if (!m_offRoute && !firstPosition) {
            speak(i18nc("@info:tts walking navigation", "You left the route, looking for a new one."));
        }
        m_offRoute = true;
        if (!m_lastRerouteRequest.isValid() || m_lastRerouteRequest.secsTo(QDateTime::currentDateTime()) >= RerouteIntervalSecs) {
            m_lastRerouteRequest = QDateTime::currentDateTime();
            Q_EMIT rerouteRequested(latitude, longitude);
        }
        Q_EMIT progressChanged();
        return;
    }

    // never move backwards along the path by more than GPS jitter, e.g. where the path passes the same place twice
    m_distanceAlong = bestAlong;
    int section = 0;
    for (std::size_t i = 0; i < m_sectionStartDistance.size(); ++i) {
        if (m_sectionStartDistance[i] <= m_distanceAlong + 0.5) {
            section = (int)i;
        }
    }
    m_currentSection = section;

    if (!m_announcedStart) {
        m_announcedStart = true;
        const auto firstInstruction = m_path.sections().front().description();
        if (firstInstruction.isEmpty()) {
            speak(i18nc("@info:tts walking navigation, %1 is the destination", "Walking to %1.", m_destination.name()));
        } else {
            speak(i18nc("@info:tts walking navigation, %1 is the destination, %2 the first instruction", "Walking to %1. %2", m_destination.name(), firstInstruction));
        }
    }

    // announcements for the next maneuver
    if (!m_arrived && distanceRemaining() <= ArrivalDistance) {
        m_arrived = true;
        speak(i18nc("@info:tts walking navigation", "You have arrived at %1.", m_destination.name()));
    } else if (!m_arrived) {
        const auto next = m_currentSection + 1;
        const auto distance = distanceToInstruction();
        if (next < (int)m_path.sections().size()) {
            if (distance <= AnnounceNowDistance && m_announcedNowSection != next) {
                m_announcedNowSection = next;
                m_announcedSection = next;
                speak(instruction());
            } else if (distance <= AnnounceAheadDistance && distance > AnnounceNowDistance && m_announcedSection != next) {
                m_announcedSection = next;
                speak(i18nc("@info:tts walking navigation, %1 is a distance, %2 an instruction", "In %1 meters: %2", (int)(std::round(distance / 5.0) * 5.0), instruction()));
            }
        }
    }

    Q_EMIT progressChanged();
}

KPublicTransport::JourneyRequest WalkingNavigationController::walkingRequest(double latitude, double longitude, const KPublicTransport::Location &destination)
{
    KPublicTransport::Location from;
    from.setCoordinate(latitude, longitude);
    from.setName(i18nc("@info start of walking navigation", "Current location"));

    KPublicTransport::JourneyRequest req(from, destination);
    req.setModes(KPublicTransport::JourneySection::Walking);
    req.setIncludePaths(true);
    req.setMaximumResults(1);
    req.setDownloadAssets(false);
    return req;
}

KPublicTransport::Path WalkingNavigationController::walkingPath(const KPublicTransport::Journey &journey)
{
    std::vector<KPublicTransport::PathSection> sections;
    for (const auto &section : journey.sections()) {
        if (section.mode() != KPublicTransport::JourneySection::Walking) {
            break;
        }
        const auto pathSections = section.path().sections();
        sections.insert(sections.end(), pathSections.begin(), pathSections.end());
    }
    KPublicTransport::Path path;
    path.setSections(std::move(sections));
    return path;
}

#include "moc_walkingnavigationcontroller.cpp"
