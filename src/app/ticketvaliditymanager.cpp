/*
    SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

#include "ticketvaliditymanager.h"

#include "logging.h"

#include <KCountry>
#include <KCountrySubdivision>
#include <KLocalizedString>

#include <QCoreApplication>
#include <QGeoPositionInfo>
#include <QGeoPositionInfoSource>
#include <QPermissions>
#include <QRegularExpression>
#include <QSettings>

using namespace Qt::Literals;

static QString settingsGroup(const QString &passId)
{
    return u"TicketValidity/"_s + passId;
}

/** Passes with a well-known validity area, recognized by their name. */
static QVariantMap knownValidityArea(const QString &passName)
{
    // the Deutschlandticket is valid on local public transport in all of Germany
    static const QRegularExpression deutschlandticket(u"deutschland-?ticket|\\bd-ticket\\b"_s, QRegularExpression::CaseInsensitiveOption);
    if (passName.contains(deutschlandticket)) {
        return {
            {u"type"_s, TicketValidityManager::CountryArea},
            {u"automatic"_s, true},
            {u"country"_s, u"DE"_s},
        };
    }
    return {};
}

TicketValidityManager::TicketValidityManager(QObject *parent)
    : QObject(parent)
{
}

TicketValidityManager::~TicketValidityManager() = default;

bool TicketValidityManager::hasPosition() const
{
    return m_position.isValid();
}

QString TicketValidityManager::countryCode() const
{
    return m_countryCode;
}

QString TicketValidityManager::locationName() const
{
    return m_locationName;
}

void TicketValidityManager::updatePosition()
{
    QLocationPermission permission;
    permission.setAccuracy(QLocationPermission::Approximate);
    switch (qApp->checkPermission(permission)) {
    case Qt::PermissionStatus::Undetermined:
        qApp->requestPermission(permission, this, [this](const QPermission &permission) {
            if (permission.status() == Qt::PermissionStatus::Granted) {
                updatePosition();
            }
        });
        return;
    case Qt::PermissionStatus::Denied:
        qCDebug(Log) << "no location permission, can't check where tickets are valid";
        return;
    case Qt::PermissionStatus::Granted:
        break;
    }

    if (!m_positionSource) {
        m_positionSource = QGeoPositionInfoSource::createDefaultSource(this);
        if (!m_positionSource) {
            qCDebug(Log) << "no position source available";
            return;
        }
        connect(m_positionSource, &QGeoPositionInfoSource::positionUpdated, this, [this](const QGeoPositionInfo &info) {
            setPosition(info.coordinate());
        });
        connect(m_positionSource, &QGeoPositionInfoSource::errorOccurred, this, [](QGeoPositionInfoSource::Error error) {
            qCDebug(Log) << "failed to determine position:" << error;
        });
    }

    // show something right away if we know where we were recently, the new position follows
    if (const auto last = m_positionSource->lastKnownPosition(); last.isValid()) {
        setPosition(last.coordinate());
    }
    m_positionSource->requestUpdate(30000);
}

void TicketValidityManager::setPosition(const QGeoCoordinate &coord)
{
    if (!coord.isValid()) {
        return;
    }
    m_position = coord;

    const auto country = KCountry::fromLocation(coord.latitude(), coord.longitude());
    const auto subdivision = KCountrySubdivision::fromLocation(coord.latitude(), coord.longitude());
    m_countryCode = country.alpha2();
    if (subdivision.isValid() && country.isValid()) {
        m_locationName = i18nc("region, country", "%1, %2", subdivision.name(), country.name());
    } else {
        m_locationName = country.name();
    }
    Q_EMIT positionChanged();
}

QVariantMap TicketValidityManager::validityArea(const QString &passId, const QString &passName) const
{
    if (auto area = knownValidityArea(passName); !area.isEmpty()) {
        return area;
    }

    QSettings settings;
    settings.beginGroup(settingsGroup(passId));
    const auto type = settings.value(u"type"_s, NoArea).toInt();
    return {
        {u"type"_s, type},
        {u"automatic"_s, false},
        {u"country"_s, settings.value(u"country"_s).toString()},
        {u"latitude"_s, settings.value(u"latitude"_s).toDouble()},
        {u"longitude"_s, settings.value(u"longitude"_s).toDouble()},
        {u"radius"_s, settings.value(u"radius"_s).toDouble()},
    };
}

void TicketValidityManager::setValidityCountry(const QString &passId, const QString &countryCode)
{
    QSettings settings;
    settings.remove(settingsGroup(passId));
    settings.beginGroup(settingsGroup(passId));
    settings.setValue(u"type"_s, CountryArea);
    settings.setValue(u"country"_s, countryCode);
    Q_EMIT validityAreasChanged();
}

void TicketValidityManager::setValidityAreaHere(const QString &passId, double radius)
{
    if (!m_position.isValid()) {
        return;
    }
    QSettings settings;
    settings.remove(settingsGroup(passId));
    settings.beginGroup(settingsGroup(passId));
    settings.setValue(u"type"_s, RadiusArea);
    settings.setValue(u"country"_s, m_countryCode);
    settings.setValue(u"latitude"_s, m_position.latitude());
    settings.setValue(u"longitude"_s, m_position.longitude());
    settings.setValue(u"radius"_s, radius);
    Q_EMIT validityAreasChanged();
}

void TicketValidityManager::clearValidityArea(const QString &passId)
{
    QSettings settings;
    settings.remove(settingsGroup(passId));
    Q_EMIT validityAreasChanged();
}

TicketValidityManager::Validity TicketValidityManager::validity(const QString &passId, const QString &passName) const
{
    const auto area = validityArea(passId, passName);
    const auto type = area.value(u"type"_s).toInt();
    if (type == NoArea || !m_position.isValid()) {
        return Unknown;
    }

    if (type == CountryArea) {
        return area.value(u"country"_s).toString() == m_countryCode ? ValidInCountry : NotValidHere;
    }

    const QGeoCoordinate center(area.value(u"latitude"_s).toDouble(), area.value(u"longitude"_s).toDouble());
    const auto radius = area.value(u"radius"_s).toDouble() * 1000.0;
    return center.isValid() && center.distanceTo(m_position) <= radius ? ValidInArea : NotValidHere;
}

#include "moc_ticketvaliditymanager.cpp"
