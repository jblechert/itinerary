/*
    SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

#ifndef MARKEDROUTECONTROLLER_H
#define MARKEDROUTECONTROLLER_H

#include <KPublicTransport/Path>

#include <QObject>
#include <QPointF>
#include <QPointer>
#include <QQmlEngine>
#include <QVariantList>

#include <functional>

class QNetworkAccessManager;
class QNetworkReply;

/** Marked hiking, cycling and mountain bike routes from OpenStreetMap, as provided by
 *  Waymarked Trails (https://waymarkedtrails.org): the routes at a place, and the course and
 *  elevation profile of a route, to show it and to follow it.
 */
class MarkedRouteController : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    /** "hiking", "cycling" or "mtb". */
    Q_PROPERTY(QString routeType MEMBER m_routeType NOTIFY routeTypeChanged)
    /** Routes found by findRoutes(), with the keys id, name, ref, itinerary and symbolUrl. */
    Q_PROPERTY(QVariantList routes READ routes NOTIFY routesChanged)
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY errorMessageChanged)

    /** The route loaded by loadRoute(). */
    Q_PROPERTY(bool hasRoute READ hasRoute NOTIFY routeChanged)
    Q_PROPERTY(QString routeName READ routeName NOTIFY routeChanged)
    Q_PROPERTY(QString routeDescription READ routeDescription NOTIFY routeChanged)
    Q_PROPERTY(QString routeSymbolUrl READ routeSymbolUrl NOTIFY routeChanged)
    Q_PROPERTY(QString routeWebUrl READ routeWebUrl NOTIFY routeChanged)
    Q_PROPERTY(KPublicTransport::Path path READ path NOTIFY routeChanged)
    /** Length of the route in meters. */
    Q_PROPERTY(double length READ length NOTIFY routeChanged)
    /** Total ascent and descent in meters, NaN if unknown. */
    Q_PROPERTY(double ascent READ ascent NOTIFY routeChanged)
    Q_PROPERTY(double descent READ descent NOTIFY routeChanged)
    /** Elevation along the route, as points of distance from the start (x) and elevation (y), in meters. */
    Q_PROPERTY(QVariantList elevationProfile READ elevationProfile NOTIFY routeChanged)
    Q_PROPERTY(double minElevation READ minElevation NOTIFY routeChanged)
    Q_PROPERTY(double maxElevation READ maxElevation NOTIFY routeChanged)

public:
    explicit MarkedRouteController(QObject *parent = nullptr);
    ~MarkedRouteController() override;

    static void setNetworkAccessManagerFactory(const std::function<QNetworkAccessManager *()> &namFactory);

    /** Look up the routes at the given place, within @p radius meters. */
    Q_INVOKABLE void findRoutes(double latitude, double longitude, double radius);
    /** Load course and elevation profile of the route with the given OSM relation id. */
    Q_INVOKABLE void loadRoute(qint64 relationId);
    /** Follow the loaded route in the opposite direction. */
    Q_INVOKABLE void reverseRoute();
    Q_INVOKABLE void clearRoute();

    [[nodiscard]] QVariantList routes() const;
    [[nodiscard]] bool loading() const;
    [[nodiscard]] QString errorMessage() const;
    [[nodiscard]] bool hasRoute() const;
    [[nodiscard]] QString routeName() const;
    [[nodiscard]] QString routeDescription() const;
    [[nodiscard]] QString routeSymbolUrl() const;
    [[nodiscard]] QString routeWebUrl() const;
    [[nodiscard]] KPublicTransport::Path path() const;
    [[nodiscard]] double length() const;
    [[nodiscard]] double ascent() const;
    [[nodiscard]] double descent() const;
    [[nodiscard]] QVariantList elevationProfile() const;
    [[nodiscard]] double minElevation() const;
    [[nodiscard]] double maxElevation() const;

    /** Total ascent and descent of an elevation profile, ignoring changes below @p threshold meters,
     *  which are mostly noise of the elevation model. Exposed for testing.
     */
    static std::pair<double, double> ascentDescent(const std::vector<QPointF> &profile, double threshold = 5.0);

Q_SIGNALS:
    void routeTypeChanged();
    void routesChanged();
    void loadingChanged();
    void errorMessageChanged();
    void routeChanged();

private:
    struct Way {
        qint64 id = 0;
        QPolygonF points; // x longitude, y latitude, in the direction of travel
    };

    [[nodiscard]] QUrl apiUrl(const QString &path) const;
    QNetworkReply *get(const QUrl &url);
    void setLoading(bool loading);
    void setError(const QString &message);
    void parseRouteDetails(const QByteArray &data, qint64 relationId);
    void parseElevation(const QByteArray &data);
    void updateRoute();

    QString m_routeType = QStringLiteral("hiking");
    QVariantList m_routes;
    int m_pendingReplies = 0;
    QString m_errorMessage;
    QPointer<QNetworkReply> m_searchReply;

    QString m_routeName;
    QString m_routeDescription;
    QString m_routeSymbolUrl;
    QString m_routeWebUrl;
    std::vector<Way> m_ways;
    std::vector<QPointF> m_profile;
    KPublicTransport::Path m_path;
    double m_length = 0.0;
    double m_ascent = NAN;
    double m_descent = NAN;
    qint64 m_loadingRelation = 0;

    QNetworkAccessManager *m_nam = nullptr;
    static std::function<QNetworkAccessManager *()> s_namFactory;
};

#endif
