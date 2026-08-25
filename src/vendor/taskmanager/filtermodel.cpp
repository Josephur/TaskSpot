/*
    SPDX-FileCopyrightText: 2026 Josephur <Josephur@users.noreply.github.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "filtermodel.h"

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

void TaskFilterProxyModel::setGroupIndex(const QModelIndex &groupIndex)
{
    if (m_groupIndex == groupIndex) {
        return;
    }
    m_groupIndex = QPersistentModelIndex(groupIndex);
    Q_EMIT groupIndexChanged();
    rebuild();
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
    beginResetModel();
    m_rows.clear();
    if (const QAbstractItemModel *source = sourceModel(); source && m_groupIndex.isValid()) {
        const int count = source->rowCount(m_groupIndex);
        m_rows.reserve(count);
        for (int row = 0; row < count; ++row) {
            if (m_filter.isEmpty()) {
                m_rows.append(row);
                continue;
            }
            const QString title =
                source->index(row, 0, m_groupIndex).data(Qt::DisplayRole).toString();
            if (title.contains(m_filter, Qt::CaseInsensitive)) {
                m_rows.append(row);
            }
        }
    }
    endResetModel();
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
    return QAbstractProxyModel::data(mapToSource(proxyIndex), role);
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

#include "moc_filtermodel.cpp"
