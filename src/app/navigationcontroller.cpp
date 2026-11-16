/*
    SPDX-FileCopyrightText: 2019 Volker Krause <vkrause@kde.org>

    SPDX-License-Identifier: LGPL-2.0-or-later
*/

#include "navigationcontroller.h"
#include "logging.h"

#include <KItinerary/LocationUtil>
#include <KItinerary/Place>

#include <KLocalizedString>

#include <QCoreApplication>
#include <QDateTime>
#include <QDebug>
#include <QDesktopServices>
#include <QGeoPositionInfo>
#include <QGeoPositionInfoSource>
#include <QPermissions>
#include <QUrl>
#include <QUrlQuery>

#ifdef Q_OS_ANDROID
#include "kandroidextras/activity.h"
#include "kandroidextras/intent.h"
#endif

#include <memory>

using namespace KItinerary;

#ifdef Q_OS_ANDROID
static bool startActivity(const QUrl &url)
{
    using namespace KAndroidExtras;

    Intent intent;
    intent.setAction(Intent::ACTION_VIEW);
    intent.setData(url);
    return Activity::startActivity(intent, 0);
}

static QString coordinateString(double latitude, double longitude)
{
    return QString::number(latitude, 'f', 6) + QLatin1Char(',') + QString::number(longitude, 'f', 6);
}

/** geo: URI showing a location with a label, understood by most map applications. */
static QUrl geoUrl(double latitude, double longitude, const QString &name)
{
    QUrl url;
    url.setScheme(QStringLiteral("geo"));
    url.setPath(coordinateString(latitude, longitude));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("q"), coordinateString(latitude, longitude) + (name.isEmpty() ? QString() : (QLatin1Char('(') + name + QLatin1Char(')'))));
    url.setQuery(query);
    return url;
}

/** Walking directions in Google Maps, from the current position. */
static QUrl googleMapsWalkingUrl(double latitude, double longitude)
{
    QUrl url;
    url.setScheme(QStringLiteral("google.navigation"));
    url.setPath(QLatin1StringView("q=") + coordinateString(latitude, longitude) + QLatin1StringView("&mode=w"));
    return url;
}

/** Walking directions in Organic Maps.
 *  Organic Maps requires exactly these parameters in this order, including the start position.
 */
static QUrl organicMapsWalkingUrl(const QGeoCoordinate &from, double latitude, double longitude, const QString &name)
{
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("sll"), coordinateString(from.latitude(), from.longitude()));
    query.addQueryItem(QStringLiteral("saddr"), i18nc("start of walking directions", "Current location"));
    query.addQueryItem(QStringLiteral("dll"), coordinateString(latitude, longitude));
    query.addQueryItem(QStringLiteral("daddr"), name);
    query.addQueryItem(QStringLiteral("type"), QStringLiteral("pedestrian"));
    QUrl url;
    url.setScheme(QStringLiteral("om"));
    url.setHost(QStringLiteral("route"));
    url.setQuery(query);
    return url;
}

static void walkFrom(const QGeoPositionInfo &from, double latitude, double longitude, const QString &name)
{
    if (from.isValid() && startActivity(organicMapsWalkingUrl(from.coordinate(), latitude, longitude, name))) {
        return;
    }
    if (startActivity(googleMapsWalkingUrl(latitude, longitude))) {
        return;
    }
    startActivity(geoUrl(latitude, longitude, name));
}
#endif

void NavigationController::showOnMap(const QVariant &place)
{
    if (place.isNull()) {
        return;
    }

    const auto geo = LocationUtil::geo(place);
    if (geo.isValid()) {
        // zoom out further from airports, they are larger and you usually want to go further away from them
        showOnMap(geo.latitude(), geo.longitude(), place.userType() == qMetaTypeId<Airport>() ? 12 : 17);
        return;
    }

    const auto addr = LocationUtil::address(place);
    if (!addr.isEmpty()) {
        QDesktopServices::openUrl(LocationUtil::geoUri(place));
    }
}

void NavigationController::showOnMap(double latitude, double longitude, int zoom)
{
    QUrl url;
    url.setScheme(QStringLiteral("geo"));
    url.setPath(QString::number(latitude) + QLatin1Char(',') + QString::number(longitude));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("z"), QString::number(zoom));
    url.setQuery(query);
    QDesktopServices::openUrl(url);
}

void NavigationController::showOnWheelmap(double latitude, double longitude)
{
    QUrl url;
    url.setScheme(QStringLiteral("https"));
    url.setHost(QStringLiteral("wheelmap.org"));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("lat"), QString::number(latitude));
    query.addQueryItem(QStringLiteral("lon"), QString::number(longitude));
    url.setQuery(query);
    QDesktopServices::openUrl(url);
}

bool NavigationController::canNavigateTo(const QVariant &place)
{
    if (place.isNull()) {
        return false;
    }

    if (LocationUtil::geo(place).isValid()) {
        return true;
    }

#ifdef Q_OS_ANDROID
    return !LocationUtil::address(place).isEmpty();
#else
    return false;
#endif
}

void NavigationController::navigateTo(const QVariant &place)
{
    if (place.isNull()) {
        return;
    }

#ifdef Q_OS_ANDROID
    const auto geo = LocationUtil::geo(place);
    ;
    const auto addr = LocationUtil::address(place);

    QUrl url;
    url.setScheme(QStringLiteral("google.navigation"));
    if (geo.isValid()) {
        url.setPath(QLatin1StringView("q=") + QString::number(geo.latitude()) + QLatin1Char(',') + QString::number(geo.longitude()));
    } else if (!addr.isEmpty()) {
        url.setPath(QLatin1StringView("q=") + addr.streetAddress() + QLatin1StringView(", ") + addr.postalCode() + QLatin1Char(' ') + addr.addressLocality()
                    + QLatin1StringView(", ") + addr.addressCountry());
    } else {
        return;
    }
    // without Google Maps, at least show the destination in any other map application
    if (!startActivity(url) && geo.isValid()) {
        startActivity(geoUrl(geo.latitude(), geo.longitude(), LocationUtil::name(place)));
    }

#else
    if (m_pendingNavigation) {
        return;
    }

    if (!m_positionSource) {
        m_positionSource = QGeoPositionInfoSource::createDefaultSource(QCoreApplication::instance());
        if (!m_positionSource) {
            qWarning() << "no geo position info source available";
            return;
        }
    }

    if (m_positionSource->lastKnownPosition().isValid()) {
        navigateTo(m_positionSource->lastKnownPosition(), place);
    } else {
        m_pendingNavigation = QObject::connect(m_positionSource, &QGeoPositionInfoSource::positionUpdated, [this, place](const QGeoPositionInfo &pos) {
            navigateTo(pos, place);
        });
        m_positionSource->requestUpdate();
    }
#endif
}

#ifndef Q_OS_ANDROID
void NavigationController::navigateTo(const QGeoPositionInfo &from, const QVariant &to)
{
    qCDebug(Log) << from.coordinate() << from.isValid();
    QObject::disconnect(m_pendingNavigation);
    if (!from.isValid()) {
        return;
    }

    const auto geo = LocationUtil::geo(to);
    if (geo.isValid()) {
        QUrl url;
        url.setScheme(QStringLiteral("https"));
        url.setHost(QStringLiteral("www.openstreetmap.org"));
        url.setPath(QStringLiteral("/directions"));
        QUrlQuery query;
        query.addQueryItem(QLatin1StringView("route"),
                           QString::number(from.coordinate().latitude()) + QLatin1Char(',') + QString::number(from.coordinate().longitude()) + QLatin1Char(';')
                               + QString::number(geo.latitude()) + QLatin1Char(',') + QString::number(geo.longitude()));
        url.setQuery(query);
        QDesktopServices::openUrl(url);
        return;
    }
}
#endif

void NavigationController::navigateTo(const QVariant &from, const QVariant &to)
{
    const auto fromGeo = LocationUtil::geo(from);
    const auto toGeo = LocationUtil::geo(to);
    if (!fromGeo.isValid() || !toGeo.isValid()) {
        navigateTo(to);
        return;
    }

#ifdef Q_OS_ANDROID
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("start_lat"), QString::number(fromGeo.latitude()));
    query.addQueryItem(QStringLiteral("start_lon"), QString::number(fromGeo.longitude()));
    query.addQueryItem(QStringLiteral("dest_lat"), QString::number(toGeo.latitude()));
    query.addQueryItem(QStringLiteral("dest_lon"), QString::number(toGeo.longitude()));
    query.addQueryItem(QStringLiteral("start_name"), LocationUtil::name(from));
    query.addQueryItem(QStringLiteral("dest_name"), LocationUtil::name(to));
    QUrl url;
    url.setScheme(QStringLiteral("osmand.api"));
    url.setHost(QStringLiteral("navigate"));
    url.setQuery(query);
    if (!startActivity(url)) {
        navigateTo(to);
    }

#else
    QUrl url;
    url.setScheme(QStringLiteral("https"));
    url.setHost(QStringLiteral("www.openstreetmap.org"));
    url.setPath(QStringLiteral("/directions"));
    QUrlQuery query;
    query.addQueryItem(QLatin1StringView("route"),
                       QString::number(fromGeo.latitude()) + QLatin1Char(',') + QString::number(fromGeo.longitude()) + QLatin1Char(';')
                           + QString::number(toGeo.latitude()) + QLatin1Char(',') + QString::number(toGeo.longitude()));
    url.setQuery(query);
    QDesktopServices::openUrl(url);
#endif
}

#include "moc_navigationcontroller.cpp"

#ifdef Q_OS_ANDROID
static void requestWalkingDirections(double latitude, double longitude, const QString &name)
{
    QLocationPermission permission;
    permission.setAccuracy(QLocationPermission::Precise);
    switch (qApp->checkPermission(permission)) {
    case Qt::PermissionStatus::Undetermined:
        qApp->requestPermission(permission, qApp, [latitude, longitude, name](const QPermission &permission) {
            if (permission.status() == Qt::PermissionStatus::Granted) {
                requestWalkingDirections(latitude, longitude, name);
            } else {
                walkFrom({}, latitude, longitude, name);
            }
        });
        return;
    case Qt::PermissionStatus::Denied:
        walkFrom({}, latitude, longitude, name);
        return;
    case Qt::PermissionStatus::Granted:
        break;
    }

    static QGeoPositionInfoSource *positionSource = QGeoPositionInfoSource::createDefaultSource(qApp);
    if (!positionSource) {
        walkFrom({}, latitude, longitude, name);
        return;
    }

    // a recent known position is good enough, walking directions get updated while walking anyway
    const auto lastPosition = positionSource->lastKnownPosition();
    if (lastPosition.isValid() && lastPosition.timestamp().secsTo(QDateTime::currentDateTime()) < 120) {
        walkFrom(lastPosition, latitude, longitude, name);
        return;
    }

    auto updateConnection = std::make_shared<QMetaObject::Connection>();
    auto errorConnection = std::make_shared<QMetaObject::Connection>();
    *updateConnection = QObject::connect(positionSource, &QGeoPositionInfoSource::positionUpdated, qApp,
        [updateConnection, errorConnection, latitude, longitude, name](const QGeoPositionInfo &position) {
            QObject::disconnect(*updateConnection);
            QObject::disconnect(*errorConnection);
            walkFrom(position, latitude, longitude, name);
        });
    *errorConnection = QObject::connect(positionSource, &QGeoPositionInfoSource::errorOccurred, qApp,
        [updateConnection, errorConnection, latitude, longitude, name](QGeoPositionInfoSource::Error error) {
            qCDebug(Log) << "no position for walking directions:" << error;
            QObject::disconnect(*updateConnection);
            QObject::disconnect(*errorConnection);
            walkFrom({}, latitude, longitude, name);
        });
    positionSource->requestUpdate(10000);
}
#endif

void NavigationController::walkTo(double latitude, double longitude, const QString &name)
{
#ifdef Q_OS_ANDROID
    requestWalkingDirections(latitude, longitude, name);
#else
    Q_UNUSED(name);
    QUrl url;
    url.setScheme(QStringLiteral("https"));
    url.setHost(QStringLiteral("www.openstreetmap.org"));
    url.setPath(QStringLiteral("/directions"));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("engine"), QStringLiteral("fossgis_osrm_foot"));
    query.addQueryItem(QStringLiteral("route"), QLatin1Char(';') + QString::number(latitude) + QLatin1Char(',') + QString::number(longitude));
    url.setQuery(query);
    QDesktopServices::openUrl(url);
#endif
}
