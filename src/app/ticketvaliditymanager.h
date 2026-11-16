/*
    SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

#ifndef TICKETVALIDITYMANAGER_H
#define TICKETVALIDITYMANAGER_H

#include <QGeoCoordinate>
#include <QObject>
#include <QVariantMap>

class QGeoPositionInfoSource;

/** Where tickets and passes are valid, and whether they are valid at the current location.
 *  The current location is determined once on startup (and on request), to answer
 *  "I just woke up in Barcelona, do I have a ticket for getting around here?".
 */
class TicketValidityManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool hasPosition READ hasPosition NOTIFY positionChanged)
    /** ISO 3166-1 alpha 2 code of the country we are currently in. */
    Q_PROPERTY(QString countryCode READ countryCode NOTIFY positionChanged)
    /** Human readable name of the current location, e.g. "Catalonia, Spain". */
    Q_PROPERTY(QString locationName READ locationName NOTIFY positionChanged)

public:
    explicit TicketValidityManager(QObject *parent = nullptr);
    ~TicketValidityManager() override;

    enum Validity {
        Unknown, ///< no validity area known for this ticket
        NotValidHere,
        ValidInArea, ///< valid here, but only in a limited area such as a city
        ValidInCountry, ///< valid in the entire country we are in
    };
    Q_ENUM(Validity)

    enum AreaType {
        NoArea,
        CountryArea,
        RadiusArea,
    };
    Q_ENUM(AreaType)

    [[nodiscard]] bool hasPosition() const;
    [[nodiscard]] QString countryCode() const;
    [[nodiscard]] QString locationName() const;

    /** Determine the current position, asking for the location permission if needed. */
    Q_INVOKABLE void updatePosition();

    /** Validity of the pass @p passId at the current location.
     *  @p passName is used to recognize passes with a known validity area, such as the Deutschlandticket.
     */
    Q_INVOKABLE [[nodiscard]] TicketValidityManager::Validity validity(const QString &passId, const QString &passName) const;

    /** The validity area of a pass, with the keys type (AreaType), automatic (bool), country, latitude, longitude, radius (km). */
    Q_INVOKABLE [[nodiscard]] QVariantMap validityArea(const QString &passId, const QString &passName) const;
    /** Set the pass to be valid in the given country. */
    Q_INVOKABLE void setValidityCountry(const QString &passId, const QString &countryCode);
    /** Set the pass to be valid within @p radius kilometers of the current position. */
    Q_INVOKABLE void setValidityAreaHere(const QString &passId, double radius);
    Q_INVOKABLE void clearValidityArea(const QString &passId);

Q_SIGNALS:
    void positionChanged();
    void validityAreasChanged();

private:
    void setPosition(const QGeoCoordinate &coord);

    QGeoPositionInfoSource *m_positionSource = nullptr;
    QGeoCoordinate m_position;
    QString m_countryCode;
    QString m_locationName;
};

#endif // TICKETVALIDITYMANAGER_H
