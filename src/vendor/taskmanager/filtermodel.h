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

class TaskFilterProxyModel : public QAbstractProxyModel
{
    Q_OBJECT
    QML_ELEMENT

    /**
     * Case-insensitive title substring; empty accepts every window.
     */
    Q_PROPERTY(QString filter READ filter WRITE setFilter NOTIFY filterChanged)

    /**
     * Source model index of the group task whose children are exposed.
     * NOT a Q_PROPERTY: qmltyperegistrar drops QModelIndex-typed and
     * QVariant-typed Q_PROPERTYs from the generated .qmltypes, which
     * makes the QML compiler refuse to instantiate the type
     * ("Element is not creatable" at runtime). Set it via the invokable
     * setter instead — see setGroupIndex().
     */
    Q_INVOKABLE void setGroupIndex(const QModelIndex &groupIndex);

public:
    static constexpr int SourceRowRole = Qt::UserRole + 1000;

    explicit TaskFilterProxyModel(QObject *parent = nullptr);
    ~TaskFilterProxyModel() override;

    QString filter() const;
    void setFilter(const QString &filter);

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
    void groupIndexChanged();

private:
    void rebuild();

    QString m_filter;
    QPersistentModelIndex m_groupIndex;
    QList<int> m_rows;
};
