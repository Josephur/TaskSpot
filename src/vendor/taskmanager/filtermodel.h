/*
    SPDX-FileCopyrightText: 2026 Josephur <Josephur@users.noreply.github.com>

    SPDX-License-Identifier: GPL-2.0-or-later

    TaskSpot: flat proxy model exposing one group task's child windows,
    optionally filtered by case-insensitive title substring.
*/

#pragma once

#include <QAbstractProxyModel>
#include <QPersistentModelIndex>
#include <QString>
#include <qqmlintegration.h>

namespace TaskSpot
{

class TaskFilterProxyModel : public QAbstractProxyModel
{
    Q_OBJECT
    QML_ELEMENT
    // See Backend: distinct unqualified QML name (#10, #18).
    QML_NAMED_ELEMENT(TaskSpotFilterProxyModel)

    /**
     * Case-insensitive title substring; empty accepts every window.
     */
    Q_PROPERTY(QString filter READ filter WRITE setFilter NOTIFY filterChanged)

    /**
     * When true, a filter that matches no child window falls back to
     * exposing every child (an empty result set never reaches the view).
     */
    Q_PROPERTY(bool fallbackToUnfiltered READ fallbackToUnfiltered
               WRITE setFallbackToUnfiltered NOTIFY fallbackToUnfilteredChanged)

    /**
     * True when the current rows are the fallback set (filter set, nothing
     * matched, fallbackToUnfiltered enabled). Callers must not treat these
     * rows as search results — e.g. for Enter-to-activate.
     */
    Q_PROPERTY(bool showingUnfiltered READ showingUnfiltered NOTIFY showingUnfilteredChanged)

    /**
     * Row of the group task in the source model whose children are
     * exposed. A plain int property on purpose: Q_INVOKABLE methods on
     * this registered type were observed invisible to the QML engine
     * (properties kept working), and a QModelIndex-typed Q_PROPERTY is
     * dropped by qmltyperegistrar (#8) — so the row is set as a number
     * and the QModelIndex is derived internally.
     */
    Q_PROPERTY(int groupRow READ groupRow WRITE setGroupRow NOTIFY groupRowChanged)

    /**
     * Current child rows in source-model coordinates, mirroring the
     * model's row order. Read for Enter-to-activate style mappings.
     */
    Q_PROPERTY(QVariantList sourceRows READ sourceRows NOTIFY sourceRowsChanged)

public:
    static constexpr int SourceRowRole = Qt::UserRole + 1000;

    explicit TaskFilterProxyModel(QObject *parent = nullptr);
    ~TaskFilterProxyModel() override;

    QString filter() const;
    void setFilter(const QString &filter);

    bool fallbackToUnfiltered() const;
    void setFallbackToUnfiltered(bool fallback);

    bool showingUnfiltered() const;

    int groupRow() const;
    void setGroupRow(int row);

    QVariantList sourceRows() const;

    QModelIndex groupIndex() const;

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    // Pure virtual in QAbstractItemModel; without this override the whole
    // class stays abstract, and qmlRegisterTypesAndRevisions then refuses
    // to register it as creatable ("neither a default constructible
    // QObject..." at every shell/viewer startup — #8).
    int columnCount(const QModelIndex &parent = QModelIndex()) const override;
    QModelIndex index(int row, int column, const QModelIndex &parent = QModelIndex()) const override;
    QModelIndex parent(const QModelIndex &child) const override;
    QVariant data(const QModelIndex &proxyIndex, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    QModelIndex mapToSource(const QModelIndex &proxyIndex) const override;
    QModelIndex mapFromSource(const QModelIndex &sourceIndex) const override;

protected:
    void setSourceModel(QAbstractItemModel *sourceModel) override;

Q_SIGNALS:
    void filterChanged();
    void fallbackToUnfilteredChanged();
    void showingUnfilteredChanged();
    void groupRowChanged();
    void sourceRowsChanged();

private:
    void rebuild();

    QString m_filter;
    bool m_fallbackToUnfiltered = false;
    bool m_showingUnfiltered = false;
    int m_groupRow = -1;
    QString m_groupAppId;
    QPersistentModelIndex m_groupIndex;
    QList<int> m_rows;
};

} // namespace TaskSpot
