/*
    SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

#ifndef JOURNEYREQUESTHISTORYMODEL_H
#define JOURNEYREQUESTHISTORYMODEL_H

#include <KPublicTransport/Location>

#include <QAbstractListModel>
#include <QDateTime>

#include <vector>

/** Previously searched journey departure/arrival pairs.
 *  Sorted by how often they were searched, most frequent first.
 */
class JourneyRequestHistoryModel : public QAbstractListModel
{
    Q_OBJECT
public:
    enum Role {
        FromRole = Qt::UserRole,
        ToRole,
        UseCountRole,
        LastUsedRole,
    };
    Q_ENUM(Role)

    explicit JourneyRequestHistoryModel(QObject *parent = nullptr);
    ~JourneyRequestHistoryModel() override;

    /** Record a journey search from @p from to @p to. */
    Q_INVOKABLE void addJourneyRequest(const KPublicTransport::Location &from, const KPublicTransport::Location &to);
    Q_INVOKABLE void removeEntry(int row);

    [[nodiscard]] int rowCount(const QModelIndex &parent = {}) const override;
    [[nodiscard]] QVariant data(const QModelIndex &index, int role) const override;
    [[nodiscard]] QHash<int, QByteArray> roleNames() const override;

private:
    struct Entry {
        KPublicTransport::Location from;
        KPublicTransport::Location to;
        int useCount = 0;
        QDateTime lastUsed;
    };

    void load();
    void save() const;
    void sortAndTrim();

    std::vector<Entry> m_entries;
};

#endif // JOURNEYREQUESTHISTORYMODEL_H
