/*
    SPDX-FileCopyrightText: 2026 Janis Blechert <janis@blechert.at>
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

#include "journeyrequesthistorymodel.h"

#include "jsonio.h"
#include "logging.h"

#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonObject>
#include <QStandardPaths>

#include <algorithm>

using namespace Qt::Literals;

// enough for regular trips, without the list becoming unwieldy
constexpr inline std::size_t MaximumEntries = 30;

static QString historyFilePath()
{
    return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + "/journey-request-history.json"_L1;
}

JourneyRequestHistoryModel::JourneyRequestHistoryModel(QObject *parent)
    : QAbstractListModel(parent)
{
    load();
}

JourneyRequestHistoryModel::~JourneyRequestHistoryModel() = default;

void JourneyRequestHistoryModel::addJourneyRequest(const KPublicTransport::Location &from, const KPublicTransport::Location &to)
{
    if (from.isEmpty() || to.isEmpty()) {
        return;
    }

    beginResetModel();
    auto it = std::find_if(m_entries.begin(), m_entries.end(), [&from, &to](const auto &entry) {
        return KPublicTransport::Location::isSame(entry.from, from) && KPublicTransport::Location::isSame(entry.to, to);
    });
    if (it == m_entries.end()) {
        m_entries.push_back({.from = from, .to = to});
        it = std::prev(m_entries.end());
    } else {
        // keep the most recent location data, e.g. for changed stop identifiers
        it->from = from;
        it->to = to;
    }
    ++it->useCount;
    it->lastUsed = QDateTime::currentDateTime();
    sortAndTrim();
    endResetModel();

    save();
}

void JourneyRequestHistoryModel::removeEntry(int row)
{
    if (row < 0 || row >= rowCount()) {
        return;
    }

    beginRemoveRows({}, row, row);
    m_entries.erase(m_entries.begin() + row);
    endRemoveRows();

    save();
}

int JourneyRequestHistoryModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) {
        return 0;
    }
    return static_cast<int>(m_entries.size());
}

QVariant JourneyRequestHistoryModel::data(const QModelIndex &index, int role) const
{
    if (!checkIndex(index, QAbstractItemModel::CheckIndexOption::IndexIsValid)) {
        return {};
    }

    const auto &entry = m_entries[index.row()];
    switch (role) {
    case Qt::DisplayRole:
        return u"%1 → %2"_s.arg(entry.from.name(), entry.to.name());
    case FromRole:
        return QVariant::fromValue(entry.from);
    case ToRole:
        return QVariant::fromValue(entry.to);
    case UseCountRole:
        return entry.useCount;
    case LastUsedRole:
        return entry.lastUsed;
    }
    return {};
}

QHash<int, QByteArray> JourneyRequestHistoryModel::roleNames() const
{
    auto r = QAbstractListModel::roleNames();
    r.insert(FromRole, "from");
    r.insert(ToRole, "to");
    r.insert(UseCountRole, "useCount");
    r.insert(LastUsedRole, "lastUsed");
    return r;
}

void JourneyRequestHistoryModel::load()
{
    QFile f(historyFilePath());
    if (!f.exists()) {
        return;
    }
    if (!f.open(QFile::ReadOnly)) {
        qCWarning(Log) << "Failed to load journey request history:" << f.errorString() << f.fileName();
        return;
    }

    const auto entries = JsonIO::read(f.readAll()).toArray();
    m_entries.reserve(entries.size());
    for (const auto &v : entries) {
        const auto obj = v.toObject();
        Entry entry{
            .from = KPublicTransport::Location::fromJson(obj.value("from"_L1).toObject()),
            .to = KPublicTransport::Location::fromJson(obj.value("to"_L1).toObject()),
            .useCount = obj.value("useCount"_L1).toInt(),
            .lastUsed = QDateTime::fromString(obj.value("lastUsed"_L1).toString(), Qt::ISODate),
        };
        if (entry.from.isEmpty() || entry.to.isEmpty() || entry.useCount <= 0) {
            continue;
        }
        m_entries.push_back(std::move(entry));
    }
    sortAndTrim();
}

void JourneyRequestHistoryModel::save() const
{
    QJsonArray entries;
    for (const auto &entry : m_entries) {
        entries.push_back(QJsonObject{
            {"from"_L1, KPublicTransport::Location::toJson(entry.from)},
            {"to"_L1, KPublicTransport::Location::toJson(entry.to)},
            {"useCount"_L1, entry.useCount},
            {"lastUsed"_L1, entry.lastUsed.toString(Qt::ISODate)},
        });
    }

    const auto path = historyFilePath();
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile f(path);
    if (!f.open(QFile::WriteOnly)) {
        qCWarning(Log) << "Failed to save journey request history:" << f.errorString() << f.fileName();
        return;
    }
    f.write(JsonIO::write(entries));
}

void JourneyRequestHistoryModel::sortAndTrim()
{
    std::stable_sort(m_entries.begin(), m_entries.end(), [](const auto &lhs, const auto &rhs) {
        if (lhs.useCount != rhs.useCount) {
            return lhs.useCount > rhs.useCount;
        }
        return lhs.lastUsed > rhs.lastUsed;
    });
    if (m_entries.size() > MaximumEntries) {
        m_entries.resize(MaximumEntries);
    }
}

#include "moc_journeyrequesthistorymodel.cpp"
