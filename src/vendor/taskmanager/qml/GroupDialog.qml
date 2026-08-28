/*
    SPDX-FileCopyrightText: 2012-2013 Eike Hein <hein@kde.org>
    SPDX-FileCopyrightText: 2021 Fushan Wen <qydwhotmail@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/
pragma ComponentBehavior: Bound

import QtQuick
import QtQml.Models
import QtQuick.Layouts

import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasmoid
import plasma.applet.org.kde.plasma.taskmanager as TaskManagerApplet

PlasmaCore.PopupPlasmaWindow {
    id: groupDialog

    width: mouseHandler.implicitWidth + leftPadding + rightPadding
    height: mouseHandler.implicitHeight + topPadding + bottomPadding

    animated: true
    removeBorderStrategy: Plasmoid.location === PlasmaCore.Types.Floating
            ? PlasmaCore.AppletPopup.AtScreenEdges
            : PlasmaCore.AppletPopup.AtScreenEdges | PlasmaCore.AppletPopup.AtPanelEdges

    margin: (Plasmoid.containmentDisplayHints & PlasmaCore.Types.ContainmentPrefersFloatingApplets) ? Kirigami.Units.largeSpacing : 0

    // TaskSpot: do NOT assign takesFocus here. PopupPlasmaWindow has no
    // such property in Plasma 6.7.4 (see
    // /usr/include/PlasmaQuick/plasmaquick/popupplasmawindow.h), so
    // assigning it makes the whole component fail to compile and
    // createObject() returns null — the popup never appears at all.
    // PopupPlasmaWindow's C++ constructor already calls
    // setTakesFocus(true) on Wayland, so focus is opted into for us.

    Timer {
        id: closeOnTimer
        interval: 100
        onTriggered: {
            if (!active && !mouseHandler.containsDrag) {
                // TaskSpot: if we're still trying to acquire focus via the
                // activation retry, don't close yet — KWin's
                // focus-stealing prevention can take a few seconds to
                // grant focus to a transient popup. Yield and let the
                // retry continue.
                if (activationRetryTimer.running) {
                    closeOnTimer.restart();
                    return;
                }
                visible = false;
            }
        }
    }

    // TaskSpot: on Wayland, requestActivate() from a popup doesn't always
    // succeed quickly — KWin's focus-stealing prevention can take 1–3 s to
    // grant focus to a transient popup that has to displace another app
    // (Kate). Retry aggressively while the dialog is shown but not yet
    // the active window. Caps at ~5 s so a permanently-blocked
    // activation doesn't keep the timer running forever.
    Timer {
        id: activationRetryTimer
        interval: 50
        repeat: true
        running: false
        property int attempts: 0
        onTriggered: {
            attempts += 1
            if (active) {
                running = false
                return
            }
            requestActivate()
            if (attempts >= 100) { // ~5s @ 50ms
                running = false
            }
        }
    }

    onActiveChanged: {
        if (active) {
            // TaskSpot: focus acquired, stop retrying requestActivate().
            activationRetryTimer.running = false
        } else {
            closeOnTimer.restart();
        }
    }

    popupDirection: switch (Plasmoid.location) {
        case PlasmaCore.Types.TopEdge:
            return Qt.BottomEdge
        case PlasmaCore.Types.LeftEdge:
            return Qt.RightEdge
        case PlasmaCore.Types.RightEdge:
            return Qt.LeftEdge
        default:
            return Qt.TopEdge
    }

    readonly property real preferredWidth: Screen.width / 3
    readonly property real preferredHeight: Screen.height / 2
    readonly property real contentWidth: mainItem.width // No padding here to avoid text elide.

    // TaskSpot: exposed for future TaskSpot features that need to drive
    // the live filter programmatically.
    readonly property alias searchField: searchField
    readonly property int listCount: groupListView.count

    property /*PlasmaCore.ItemStatus*/int _oldAppletStatus: PlasmaCore.Types.UnknownStatus

    function findActiveTaskIndex(): void {
        // TaskSpot: only meaningful with the live filter inactive (rows are
        // then identity-mapped to source child rows).
        if (!tasksModel.activeTask || searchField.text !== "") {
            return;
        }
        for (let i = 0; i < groupListView.count; i++) {
            if (tasksModel.makeModelIndex((visualParent as Task).index, i) === tasksModel.activeTask) {
                groupListView.positionViewAtIndex(i, ListView.Contain); // Prevent visual glitches
                groupListView.currentIndex = i;
                return;
            }
        }
    }

    Component.onCompleted: {
        // Don't bind visible at creation, otherwise it
        // will be made visible before assigning the visual partent
        // making the window flickering in the center of the screen before being moved
        // in the correct position
        visible = true
    }

    mainItem: MouseHandler {
        id: mouseHandler
        implicitWidth: Math.min(groupDialog.preferredWidth, Math.max(groupListView.maxWidth, groupDialog.visualParent.width))
        implicitHeight: Math.min(groupDialog.preferredHeight,
                                 groupListView.maxHeight
                                 + (searchField.visible ? searchField.implicitHeight + mainColumn.spacing : 0))

        target: groupListView
        handleWheelEvents: !scrollView.overflowing
        isGroupDialog: true

        // TaskSpot: capture printable keys and Backspace anywhere in the
        // dialog (Klipper-style) and route them into the live filter field.
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                if (searchField.text !== "") {
                    searchField.text = "";
                    groupListView.forceActiveFocus();
                    event.accepted = true;
                    return;
                }
                groupDialog.visible = false;
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Backspace || event.text.length > 0) {
                searchField.forceActiveFocus();
                if (event.text.length > 0) {
                    searchField.text += event.text;
                } else if (searchField.text.length > 0) {
                    searchField.text = searchField.text.slice(0, -1);
                }
                event.accepted = true;
            }
        }

        onContainsDragChanged: {
            if (!active && !containsDrag) {
                groupDialog.visible = false;
            }
        }

        function moveRow(event: KeyEvent, insertAt: int): void {
            // TaskSpot: rows are proxy positions while filtering; reordering
            // by proxy row would target the wrong window.
            if (searchField.text !== "") {
                event.accepted = false;
                return;
            }
            if (!(event.modifiers & Qt.ControlModifier) || !(event.modifiers & Qt.ShiftModifier)) {
                event.accepted = false;
                return;
            } else if (insertAt < 0 || insertAt >= groupListView.count) {
                return;
            }

            const parentModelIndex = tasksModel.makeModelIndex((groupDialog.visualParent as Task).index);
            const status = tasksModel.move(groupListView.currentIndex, insertAt, parentModelIndex);
            if (!status) {
                return;
            }

            groupListView.currentIndex = insertAt;
        }

        ColumnLayout {
            id: mainColumn

            spacing: Kirigami.Units.smallSpacing

            width: parent.width
            height: parent.height

            // TaskSpot: hidden until typing starts; filters the window cards.
            PlasmaExtras.SearchField {
                id: searchField

                Layout.fillWidth: true
                // Collapse to zero height when hidden so the dialog's first
                // paint doesn't leave a gap where the field would be — the
                // parent's implicitHeight already accounts for visibility.
                Layout.preferredHeight: visible ? implicitHeight : 0
                visible: text.length > 0 || activeFocus
                placeholderText: i18n("Search windows…")

                // TaskSpot: while the search field holds focus, Up/Down must
                // still navigate the (filtered) list. Reordering keys
                // (Ctrl+Shift+Up/Down) remain disabled because proxy rows
                // would target the wrong source window — see moveRow().
                Keys.onUpPressed: {
                    if (groupListView.count > 0) {
                        groupListView.currentIndex = Math.max(0, groupListView.currentIndex - 1);
                        groupListView.positionViewAtIndex(groupListView.currentIndex, ListView.Contain);
                    }
                }
                Keys.onDownPressed: {
                    if (groupListView.count > 0) {
                        groupListView.currentIndex = Math.min(groupListView.count - 1, groupListView.currentIndex + 1);
                        groupListView.positionViewAtIndex(groupListView.currentIndex, ListView.Contain);
                    }
                }
                Keys.onReturnPressed: {
                    // Mirror Task.qml's Keys.onReturnPressed so a typed query
                    // can still be activated without leaving the search field.
                    // effectWatcher is main.qml-scoped, so pass false; the
                    // non-group-parent branch in activateTask never reads it.
                    const item = groupListView.currentItem;
                    if (item && item.model && !item.model.IsGroupParent) {
                        TaskManagerApplet.TaskTools.activateTask(item.modelIndex(), item.model, 0, item, Plasmoid, item.tasksRoot, false);
                        event.accepted = true;
                    }
                }
            }

            PlasmaComponents3.ScrollView {
                id: scrollView

                // To achieve a bottom-to-top layout on vertical panels, the task manager
                // is rotated by 180 degrees(see main.qml). This makes the group dialog's
                // items rotated, so un-rotate them here to fix that.
                rotation: Plasmoid.configuration.reverseMode && Plasmoid.formFactor === PlasmaCore.Types.Vertical ? 180 : 0

                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(groupDialog.preferredHeight, groupListView.maxHeight)
                readonly property bool overflowing: leftPadding > 0 || rightPadding > 0 // Scrollbar is visible

                ListView {
                    id: groupListView

                    readonly property real maxWidth: groupFilter.maxTextWidth
                                                    + TaskManagerApplet.LayoutMetrics.horizontalMargins()
                                                    + Kirigami.Units.iconSizes.medium
                                                    + 2 * (TaskManagerApplet.LayoutMetrics.labelMargin + TaskManagerApplet.LayoutMetrics.iconMargin)
                                                    + scrollView.leftPadding + scrollView.rightPadding
                    // Use groupFilter.count because sometimes count is not updated in time (BUG 446105)
                    readonly property real maxHeight: (searchField.text === "" ? groupFilter.count : taskFilterModel.rowCount())
                                                      * (TaskManagerApplet.LayoutMetrics.verticalMargins() + Math.max(Kirigami.Units.iconSizes.sizeForLabels, Kirigami.Units.iconSizes.medium))

                    // TaskSpot: live-filtered view of this group's windows.
                    // groupRow is a plain int property — Q_INVOKABLE methods
                    // on this registered type were observed invisible to the
                    // QML engine (#12), while properties kept working.
                    model: TaskManagerApplet.TaskFilterProxyModel {
                        id: taskFilterModel

                        sourceModel: tasksModel
                        groupRow: (groupDialog.visualParent as Task).index
                    }

                    DelegateModel {
                        id: groupFilter

                        readonly property TextMetrics textMetrics: TextMetrics {}
                        property real maxTextWidth: 0

                        model: tasksModel
                        rootIndex: tasksModel.makeModelIndex((groupDialog.visualParent as Task).index)
                        delegate: Item {}

                        function updateMaxTextWidth(): void {
                            let tempMaxTextWidth = 0;
                            // 20 is based on performance considerations.
                            for (let i = 0; i < Math.min(count, 20); i++) {
                                textMetrics.text = items.get(i).model.display;
                                if (textMetrics.boundingRect.width > tempMaxTextWidth) {
                                    tempMaxTextWidth = textMetrics.boundingRect.width;
                                }
                            }
                            maxTextWidth = tempMaxTextWidth;
                        }
                    }

                    delegate: Task {
                        id: delegate

                        width: groupListView.width
                        visible: true
                        inPopup: true
                        tasksRoot: tasks

                        ListView.onRemove: Qt.callLater(groupFilter.updateMaxTextWidth)
                        Connections {
                            enabled: delegate.index < 20 // 20 is based on performance considerations.

                            function onLabelTextChanged(): void { // ListView.onAdd included
                                if (groupFilter.maxTextWidth === 0) {
                                    // Update immediately to avoid shrinking
                                    groupFilter.updateMaxTextWidth();
                                } else {
                                    Qt.callLater(groupFilter.updateMaxTextWidth);
                                }
                            }
                        }
                    }

                    reuseItems: false

                    Keys.onUpPressed: event => mouseHandler.moveRow(event, groupListView.currentIndex - 1)
                    Keys.onDownPressed: event => mouseHandler.moveRow(event, groupListView.currentIndex + 1)

                    onCountChanged: {
                        if (count > 0) {
                            tasks.cancelHighlightWindows()
                        } else if (searchField.text === "") {
                            // Only auto-close when no live filter is active,
                            // otherwise typing a query with no matches yet
                            // would dismiss the dialog.
                            groupDialog.visible = false;
                        }
                    }
                }
            }
        }
    }

    onVisibleChanged: {
        if (visible) {
            _oldAppletStatus = Plasmoid.status;
            Plasmoid.status = PlasmaCore.Types.RequiresAttentionStatus;

            groupDialog.requestActivate();
            groupListView.forceActiveFocus(); // Active focus on ListView so keyboard navigation can work.
            // TaskSpot: kick off the activation retry so Wayland's
            // focus-stealing prevention eventually yields keyboard focus
            // to the popup even if the initial requestActivate() loses.
            activationRetryTimer.attempts = 0
            activationRetryTimer.running = true
            Qt.callLater(findActiveTaskIndex);
        } else {
            activationRetryTimer.running = false
            Plasmoid.status = _oldAppletStatus;
            tasks.groupDialog = null;
            destroy();
        }
    }
}
