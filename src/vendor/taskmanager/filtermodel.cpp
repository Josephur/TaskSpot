/*
    SPDX-FileCopyrightText: 2026 Josephur <Josephur@users.noreply.github.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "filtermodel.h"

#include <taskmanager/abstracttasksmodel.h>

namespace TaskSpot
{

TaskFilterProxyModel::TaskFilterProxyModel(QObject *parent)
    : QAbstractProxyModel(parent)
{
}

TaskFilterProxyModel::~TaskFilterProxyModel() = default;

QString TaskFilterProxyModel::filter() const
{
    return m_filter;
}

void TaskFilterProxyModel::setFilter(const QString &filter)
{
    if (m_filter == filter) {
        return;
    }
    m_filter = filter;
    Q_EMIT filterChanged();
    rebuild();
}

QModelIndex TaskFilterProxyModel::groupIndex() const
{
    return m_groupIndex;
}

bool TaskFilterProxyModel::fallbackToUnfiltered() const
{
    return m_fallbackToUnfiltered;
}

void TaskFilterProxyModel::setFallbackToUnfiltered(bool fallback)
{
    if (m_fallbackToUnfiltered == fallback) {
        return;
    }
    m_fallbackToUnfiltered = fallback;
    Q_EMIT fallbackToUnfilteredChanged();
    rebuild();
}

bool TaskFilterProxyModel::showingUnfiltered() const
{
    return m_showingUnfiltered;
}

int TaskFilterProxyModel::groupRow() const
{
    return m_groupRow;
}

void TaskFilterProxyModel::setGroupRow(int row)
{
    if (m_groupRow == row) {
        return;
    }
    // Only store the row; rebuild() performs all resolution against the
    // source model, so property-binding evaluation order (sourceModel vs
    // groupRow) never matters.
    m_groupRow = row;
    Q_EMIT groupRowChanged();
    rebuild();
}

QVariantList TaskFilterProxyModel::sourceRows() const
{
    QVariantList rows;
    rows.reserve(m_rows.count());
    for (int row : m_rows) {
        rows.append(row);
    }
    return rows;
}

void TaskFilterProxyModel::setSourceModel(QAbstractItemModel *source)
{
    if (this->sourceModel() == source) {
        return;
    }
    if (const auto *previous = this->sourceModel()) {
        disconnect(previous, nullptr, this, nullptr);
    }
    QAbstractProxyModel::setSourceModel(source);
    if (source) {
        connect(source, &QAbstractItemModel::modelReset, this, &TaskFilterProxyModel::rebuild);
        connect(source, &QAbstractItemModel::rowsInserted, this, &TaskFilterProxyModel::rebuild);
        connect(source, &QAbstractItemModel::rowsRemoved, this, &TaskFilterProxyModel::rebuild);
        connect(source, &QAbstractItemModel::dataChanged, this, &TaskFilterProxyModel::rebuild);
        connect(source, &QAbstractItemModel::layoutChanged, this, &TaskFilterProxyModel::rebuild);
    }
    rebuild();
}

void TaskFilterProxyModel::rebuild()
{
    // Locate the group task. The int row seeds the first resolution;
    // afterwards the group is re-located by its AppId (one group task per
    // app), which survives the tasks model's activation-driven re-sorting
    // and window churn that invalidates both the row and the persistent
    // index. If no AppId is known yet, trust the row. This must be
    // total: any path that leaves the group unresolved renders the whole
    // popup empty (#12).
    m_groupIndex = QPersistentModelIndex();
    if (sourceModel() && m_groupRow >= 0 && m_groupRow < sourceModel()->rowCount()) {
        int locatedRow = -1;
        if (!m_groupAppId.isEmpty()) {
            for (int r = 0; r < sourceModel()->rowCount(); ++r) {
                const QModelIndex idx = sourceModel()->index(r, 0);
                if (idx.data(TaskManager::AbstractTasksModel::AppId).toString() == m_groupAppId
                    && sourceModel()->rowCount(idx) > 0) {
                    locatedRow = r;
                    break;
                }
            }
        }
        if (locatedRow < 0) {
            const QModelIndex candidate = sourceModel()->index(m_groupRow, 0);
            const QString candidateAppId = candidate.data(TaskManager::AbstractTasksModel::AppId).toString();
            if (m_groupAppId.isEmpty() || candidateAppId == m_groupAppId) {
                locatedRow = m_groupRow;
            }
        }
        if (locatedRow >= 0) {
            m_groupIndex = QPersistentModelIndex(sourceModel()->index(locatedRow, 0));
            m_groupAppId = m_groupIndex.data(TaskManager::AbstractTasksModel::AppId).toString();
        }
    }
    QList<int> newRows;
    bool showingUnfiltered = false;
    if (const QAbstractItemModel *source = sourceModel(); source && m_groupIndex.isValid()) {
        const int count = source->rowCount(m_groupIndex);
        newRows.reserve(count);
        for (int row = 0; row < count; ++row) {
            if (m_filter.isEmpty()) {
                newRows.append(row);
                continue;
            }
            const QString title =
                source->index(row, 0, m_groupIndex).data(Qt::DisplayRole).toString();
            if (title.contains(m_filter, Qt::CaseInsensitive)) {
                newRows.append(row);
            }
        }
        // TaskSpot (#12): a filter that matches nothing falls back to the
        // full child list instead of an empty popup, when enabled.
        if (newRows.isEmpty() && m_fallbackToUnfiltered) {
            for (int row = 0; row < count; ++row) {
                newRows.append(row);
            }
            showingUnfiltered = true;
        }
    }

    // TaskSpot (#12): the tasks model emits dataChanged constantly (active
    // window flips, titles tick). A full reset for every one of those tore
    // the card delegates down faster than their PipeWire thumbnail streams
    // could establish, leaving only fallback icons. When the row set is
    // unchanged, refresh roles in place instead of resetting.
    if (newRows == m_rows) {
        if (!newRows.isEmpty()) {
            Q_EMIT dataChanged(index(0, 0), index(newRows.count() - 1, 0),
                               QVector<int>() << Qt::DisplayRole);
        }
    } else {
        beginResetModel();
        m_rows = newRows;
        endResetModel();
    }
    Q_EMIT sourceRowsChanged();
    if (showingUnfiltered != m_showingUnfiltered) {
        m_showingUnfiltered = showingUnfiltered;
        Q_EMIT showingUnfilteredChanged();
    }
}

int TaskFilterProxyModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) {
        return 0;
    }
    return m_rows.count();
}

int TaskFilterProxyModel::columnCount(const QModelIndex &parent) const
{
    // The tasks model is single-column; this proxy is flat.
    return parent.isValid() ? 0 : 1;
}

QModelIndex TaskFilterProxyModel::index(int row, int column, const QModelIndex &parent) const
{
    if (parent.isValid() || row < 0 || row >= m_rows.count() || column != 0) {
        return QModelIndex();
    }
    return createIndex(row, column);
}

QModelIndex TaskFilterProxyModel::parent(const QModelIndex &child) const
{
    Q_UNUSED(child);
    return QModelIndex();
}

QVariant TaskFilterProxyModel::data(const QModelIndex &proxyIndex, int role) const
{
    if (role == SourceRowRole) {
        if (!proxyIndex.isValid() || proxyIndex.row() >= m_rows.count()) {
            return -1;
        }
        return m_rows.at(proxyIndex.row());
    }
    // Forward explicitly: the QAbstractProxyModel base behavior combined
    // with a transiently invalid group index surfaced as undefined roles
    // in the card delegates ("undefined" window titles — #12).
    const QModelIndex sourceIndex = mapToSource(proxyIndex);
    return sourceIndex.isValid() && sourceModel()
        ? sourceModel()->data(sourceIndex, role)
        : QVariant();
}

QHash<int, QByteArray> TaskFilterProxyModel::roleNames() const
{
    QHash<int, QByteArray> roles;
    if (const QAbstractItemModel *source = sourceModel()) {
        roles = source->roleNames();
    }
    roles[SourceRowRole] = "sourceRow";
    return roles;
}

QModelIndex TaskFilterProxyModel::mapToSource(const QModelIndex &proxyIndex) const
{
    if (!proxyIndex.isValid() || proxyIndex.row() >= m_rows.count() || !m_groupIndex.isValid()
        || !sourceModel()) {
        return QModelIndex();
    }
    return sourceModel()->index(m_rows.at(proxyIndex.row()), 0, m_groupIndex);
}

QModelIndex TaskFilterProxyModel::mapFromSource(const QModelIndex &sourceIndex) const
{
    if (!sourceIndex.isValid() || sourceIndex.parent() != static_cast<QModelIndex>(m_groupIndex)) {
        return QModelIndex();
    }
    const int proxyRow = m_rows.indexOf(sourceIndex.row());
    if (proxyRow < 0) {
        return QModelIndex();
    }
    return index(proxyRow, 0);
}

} // namespace TaskSpot

#include "moc_filtermodel.cpp"
