/*
    SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

#include "markedroutecontroller.h"

#include "applicationcontroller.h"
#include "logging.h"

#include <KLocalizedString>

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrlQuery>

#include <cmath>

using namespace Qt::Literals;

std::function<QNetworkAccessManager *()> MarkedRouteController::s_namFactory;

static constexpr double EarthRadius = 6378137.0; // as used by Web Mercator

// Waymarked Trails uses Web Mercator (EPSG:3857) coordinates
static QPointF fromMercator(double x, double y)
{
    const auto lon = x / EarthRadius * 180.0 / M_PI;
    const auto lat = (2.0 * std::atan(std::exp(y / EarthRadius)) - M_PI / 2.0) * 180.0 / M_PI;
    return {lon, lat};
}

static QPointF toMercator(double lon, double lat)
{
    return {lon * M_PI / 180.0 * EarthRadius, std::log(std::tan((90.0 + lat) * M_PI / 360.0)) * EarthRadius};
}

static double distance(QPointF p1, QPointF p2)
{
    const auto toRad = M_PI / 180.0;
    const auto dLat = (p2.y() - p1.y()) * toRad;
    const auto dLon = (p2.x() - p1.x()) * toRad;
    const auto a = std::sin(dLat / 2) * std::sin(dLat / 2) + std::cos(p1.y() * toRad) * std::cos(p2.y() * toRad) * std::sin(dLon / 2) * std::sin(dLon / 2);
    return 2.0 * 6371000.0 * std::atan2(std::sqrt(a), std::sqrt(1.0 - a));
}

static double polylineLength(const QPolygonF &points)
{
    double length = 0.0;
    for (qsizetype i = 1; i < points.size(); ++i) {
        length += distance(points[i - 1], points[i]);
    }
    return length;
}

MarkedRouteController::MarkedRouteController(QObject *parent)
    : QObject(parent)
{
}

MarkedRouteController::~MarkedRouteController() = default;

void MarkedRouteController::setNetworkAccessManagerFactory(const std::function<QNetworkAccessManager *()> &namFactory)
{
    s_namFactory = namFactory;
}

QUrl MarkedRouteController::apiUrl(const QString &path) const
{
    return QUrl(u"https://"_s + m_routeType + u".waymarkedtrails.org/api/v1/"_s + path);
}

QNetworkReply *MarkedRouteController::get(const QUrl &url)
{
    if (!m_nam) {
        m_nam = s_namFactory ? s_namFactory() : new QNetworkAccessManager(this);
    }
    QNetworkRequest req(url);
    req.setHeader(QNetworkRequest::UserAgentHeader, ApplicationController::userAgent());
    // route names and descriptions in the user's language, where available
    req.setRawHeader("Accept-Language", QLocale().uiLanguages().join(u", "_s).toUtf8());
    return m_nam->get(req);
}

void MarkedRouteController::setLoading(bool loading)
{
    m_pendingReplies += loading ? 1 : -1;
    Q_EMIT loadingChanged();
}

void MarkedRouteController::setError(const QString &message)
{
    m_errorMessage = message;
    Q_EMIT errorMessageChanged();
}

void MarkedRouteController::findRoutes(double latitude, double longitude, double radius)
{
    if (m_searchReply) {
        m_searchReply->abort();
    }
    m_routes.clear();
    Q_EMIT routesChanged();
    setError({});

    // Web Mercator stretches distances by 1/cos(latitude)
    const auto center = toMercator(longitude, latitude);
    const auto r = radius / std::cos(latitude * M_PI / 180.0);
    QUrl url = apiUrl(u"list/by_area"_s);
    QUrlQuery query;
    query.addQueryItem(u"bbox"_s, u"%1,%2,%3,%4"_s.arg(center.x() - r, 0, 'f', 0).arg(center.y() - r, 0, 'f', 0).arg(center.x() + r, 0, 'f', 0).arg(center.y() + r, 0, 'f', 0));
    query.addQueryItem(u"limit"_s, u"20"_s);
    url.setQuery(query);

    auto reply = get(url);
    m_searchReply = reply;
    setLoading(true);
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        setLoading(false);
        if (reply->error() == QNetworkReply::OperationCanceledError) {
            return;
        }
        if (reply->error() != QNetworkReply::NoError) {
            qCWarning(Log) << "marked route search failed:" << reply->errorString();
            setError(i18nc("@info", "Marked routes could not be looked up: %1", reply->errorString()));
            return;
        }
        const auto results = QJsonDocument::fromJson(reply->readAll()).object().value("results"_L1).toArray();
        for (const auto &v : results) {
            const auto obj = v.toObject();
            if (obj.value("type"_L1).toString() != "relation"_L1) {
                continue; // way sets have no relation to follow
            }
            QStringList itinerary;
            for (const auto &place : obj.value("itinerary"_L1).toArray()) {
                itinerary.push_back(place.toString());
            }
            const auto symbolId = obj.value("symbol_id"_L1).toString();
            m_routes.push_back(QVariantMap{
                {u"id"_s, obj.value("id"_L1).toInteger()},
                {u"name"_s, obj.value("name"_L1).toString()},
                {u"ref"_s, obj.value("ref"_L1).toString()},
                {u"itinerary"_s, itinerary.join(u" – "_s)},
                {u"symbolUrl"_s, symbolId.isEmpty() ? QString() : apiUrl(u"symbols/id/"_s + symbolId + u".svg"_s).toString()},
            });
        }
        Q_EMIT routesChanged();
    });
}

void MarkedRouteController::loadRoute(qint64 relationId)
{
    clearRoute();
    setError({});
    m_loadingRelation = relationId;
    auto reply = get(apiUrl(u"details/relation/"_s + QString::number(relationId)));
    setLoading(true);
    connect(reply, &QNetworkReply::finished, this, [this, reply, relationId]() {
        reply->deleteLater();
        setLoading(false);
        if (relationId != m_loadingRelation) {
            return;
        }
        if (reply->error() != QNetworkReply::NoError) {
            qCWarning(Log) << "loading marked route failed:" << reply->errorString();
            setError(i18nc("@info", "The route could not be loaded: %1", reply->errorString()));
            return;
        }
        parseRouteDetails(reply->readAll(), relationId);
    });
}

// the course of a route is a tree of segments, the leaves list the ways in order
static void collectWays(const QJsonObject &segment, std::vector<QJsonObject> &ways)
{
    for (const auto &w : segment.value("ways"_L1).toArray()) {
        ways.push_back(w.toObject());
    }
    for (const auto &s : segment.value("main"_L1).toArray()) {
        collectWays(s.toObject(), ways);
    }
}

void MarkedRouteController::parseRouteDetails(const QByteArray &data, qint64 relationId)
{
    const auto obj = QJsonDocument::fromJson(data).object();
    m_routeName = obj.value("name"_L1).toString();
    if (const auto ref = obj.value("ref"_L1).toString(); !ref.isEmpty() && !m_routeName.contains(ref)) {
        m_routeName = m_routeName.isEmpty() ? ref : (ref + u" "_s + m_routeName);
    }
    m_routeDescription = obj.value("description"_L1).toString();
    const auto symbolId = obj.value("symbol_id"_L1).toString();
    m_routeSymbolUrl = symbolId.isEmpty() ? QString() : apiUrl(u"symbols/id/"_s + symbolId + u".svg"_s).toString();
    m_routeWebUrl = u"https://"_s + m_routeType + u".waymarkedtrails.org/#route?id="_s + QString::number(relationId);

    std::vector<QJsonObject> wayObjs;
    collectWays(obj.value("route"_L1).toObject(), wayObjs);
    m_ways.clear();
    for (const auto &wayObj : wayObjs) {
        Way way;
        way.id = wayObj.value("id"_L1).toInteger();
        for (const auto &c : wayObj.value("geometry"_L1).toObject().value("coordinates"_L1).toArray()) {
            const auto coord = c.toArray();
            way.points.push_back(fromMercator(coord.at(0).toDouble(), coord.at(1).toDouble()));
        }
        if (way.points.size() < 2) {
            continue;
        }
        // ways are listed in order, but not necessarily in the direction of travel
        if (!m_ways.empty()) {
            const auto end = m_ways.back().points.back();
            if (distance(end, way.points.back()) < distance(end, way.points.front())) {
                std::reverse(way.points.begin(), way.points.end());
            }
            if (m_ways.size() == 1) {
                // the first way's direction is only known from the second one
                auto &first = m_ways.front().points;
                const auto start = way.points.front();
                if (distance(first.front(), start) < distance(first.back(), start)) {
                    std::reverse(first.begin(), first.end());
                }
            }
        }
        m_ways.push_back(std::move(way));
    }

    if (m_ways.empty()) {
        setError(i18nc("@info", "The course of this route is not available."));
        return;
    }
    m_profile.clear();
    updateRoute();

    // elevation, with about 300 points along the route
    QUrl url = apiUrl(u"details/relation/"_s + QString::number(relationId) + u"/way-elevation"_s);
    url.setQuery(u"simplify="_s + QString::number(std::max(20, (int)(m_length / 300.0))));
    auto reply = get(url);
    setLoading(true);
    connect(reply, &QNetworkReply::finished, this, [this, reply, relationId]() {
        reply->deleteLater();
        setLoading(false);
        if (relationId != m_loadingRelation) {
            return;
        }
        if (reply->error() != QNetworkReply::NoError) {
            qCWarning(Log) << "loading elevation failed:" << reply->errorString();
            return; // the route is usable without
        }
        parseElevation(reply->readAll());
    });
}

void MarkedRouteController::parseElevation(const QByteArray &data)
{
    const auto segments = QJsonDocument::fromJson(data).object().value("segments"_L1).toObject();
    m_profile.clear();
    double offset = 0.0;
    for (const auto &way : m_ways) {
        const auto wayLength = polylineLength(way.points);
        const auto elevation = segments.value(QString::number(way.id)).toObject().value("elevation"_L1).toArray();
        if (elevation.size() >= 2) {
            const auto lastPos = elevation.last().toObject().value("pos"_L1).toDouble();
            const auto firstObj = elevation.first().toObject();
            const auto first = fromMercator(firstObj.value("x"_L1).toDouble(), firstObj.value("y"_L1).toDouble());
            const bool reversed = distance(first, way.points.back()) < distance(first, way.points.front());
            std::vector<QPointF> wayProfile;
            for (const auto &e : elevation) {
                const auto eObj = e.toObject();
                auto fraction = lastPos > 0.0 ? eObj.value("pos"_L1).toDouble() / lastPos : 0.0;
                if (reversed) {
                    fraction = 1.0 - fraction;
                }
                wayProfile.emplace_back(offset + fraction * wayLength, eObj.value("ele"_L1).toDouble());
            }
            if (reversed) {
                std::reverse(wayProfile.begin(), wayProfile.end());
            }
            m_profile.insert(m_profile.end(), wayProfile.begin(), wayProfile.end());
        }
        offset += wayLength;
    }
    updateRoute();
}

std::pair<double, double> MarkedRouteController::ascentDescent(const std::vector<QPointF> &profile, double threshold)
{
    if (profile.empty()) {
        return {NAN, NAN};
    }
    double ascent = 0.0;
    double descent = 0.0;
    auto reference = profile.front().y();
    for (const auto &p : profile) {
        const auto diff = p.y() - reference;
        if (diff >= threshold) {
            ascent += diff;
            reference = p.y();
        } else if (diff <= -threshold) {
            descent -= diff;
            reference = p.y();
        }
    }
    return {ascent, descent};
}

void MarkedRouteController::updateRoute()
{
    QPolygonF points;
    for (const auto &way : m_ways) {
        for (const auto &p : way.points) {
            if (points.isEmpty() || distance(points.back(), p) > 0.01) {
                points.push_back(p);
            }
        }
    }
    m_length = polylineLength(points);
    std::tie(m_ascent, m_descent) = ascentDescent(m_profile);

    KPublicTransport::PathSection section;
    section.setPath(points);
    section.setDescription(m_routeName);
    KPublicTransport::Path path;
    path.setSections({section});
    m_path = path;
    Q_EMIT routeChanged();
}

void MarkedRouteController::reverseRoute()
{
    std::reverse(m_ways.begin(), m_ways.end());
    for (auto &way : m_ways) {
        std::reverse(way.points.begin(), way.points.end());
    }
    for (auto &p : m_profile) {
        p.setX(m_length - p.x());
    }
    std::reverse(m_profile.begin(), m_profile.end());
    updateRoute();
}

void MarkedRouteController::clearRoute()
{
    m_loadingRelation = 0;
    m_ways.clear();
    m_profile.clear();
    m_routeName.clear();
    m_routeDescription.clear();
    m_routeSymbolUrl.clear();
    m_routeWebUrl.clear();
    m_path = {};
    m_length = 0.0;
    m_ascent = m_descent = NAN;
    Q_EMIT routeChanged();
}

QVariantList MarkedRouteController::routes() const
{
    return m_routes;
}

bool MarkedRouteController::loading() const
{
    return m_pendingReplies > 0;
}

QString MarkedRouteController::errorMessage() const
{
    return m_errorMessage;
}

bool MarkedRouteController::hasRoute() const
{
    return !m_ways.empty();
}

QString MarkedRouteController::routeName() const
{
    return m_routeName;
}

QString MarkedRouteController::routeDescription() const
{
    return m_routeDescription;
}

QString MarkedRouteController::routeSymbolUrl() const
{
    return m_routeSymbolUrl;
}

QString MarkedRouteController::routeWebUrl() const
{
    return m_routeWebUrl;
}

KPublicTransport::Path MarkedRouteController::path() const
{
    return m_path;
}

double MarkedRouteController::length() const
{
    return m_length;
}

double MarkedRouteController::ascent() const
{
    return m_ascent;
}

double MarkedRouteController::descent() const
{
    return m_descent;
}

QVariantList MarkedRouteController::elevationProfile() const
{
    QVariantList l;
    l.reserve((qsizetype)m_profile.size());
    for (const auto &p : m_profile) {
        l.push_back(p);
    }
    return l;
}

double MarkedRouteController::minElevation() const
{
    if (m_profile.empty()) {
        return NAN;
    }
    return std::min_element(m_profile.begin(), m_profile.end(), [](auto lhs, auto rhs) { return lhs.y() < rhs.y(); })->y();
}

double MarkedRouteController::maxElevation() const
{
    if (m_profile.empty()) {
        return NAN;
    }
    return std::max_element(m_profile.begin(), m_profile.end(), [](auto lhs, auto rhs) { return lhs.y() < rhs.y(); })->y();
}

#include "moc_markedroutecontroller.cpp"
