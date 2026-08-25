/*
    SPDX-FileCopyrightText: 2026 Josephur <Josephur@users.noreply.github.com>

    SPDX-License-Identifier: GPL-2.0-or-later

    TaskSpot: a focusable popup that hosts the stock tooltip content plus a
    live search field.

    Why this exists instead of putting a text field in the tooltip: the
    tooltip is rendered in libplasma's shared ToolTipDialog, which is
    created with Qt::WindowDoesNotAcceptFocus and the Wayland role
    "tooltip". KWin's XdgToplevelWindow::acceptsFocus() returns false for
    that role unconditionally, so a text field there can hold QML item
    focus but will never receive a keystroke — they go to whichever window
    was active before. ToolTipDialog also calls dismiss() on QEvent::Leave
    unconditionally, so layering a focusable window over it does not work
    either.

    ToolTipDelegate itself is not tooltip-bound: ToolTipArea merely
    reparents it into that window. Hosting it here gives identical content
    in a window that can accept focus.
*/
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

PlasmaCore.PopupPlasmaWindow {
    id: searchPopup

    // visualParent is inherited from PopupPlasmaWindow and set by
    // TaskTools.createSearchPopup() at createObject() time.
    readonly property Task task: visualParent as Task

    readonly property alias searchField: searchField

    // NOTE: do not assign takesFocus here — PopupPlasmaWindow has no such
    // property in Plasma 6.7.4, and assigning a non-existent property
    // makes the component fail to compile so createObject() returns null.
    // The C++ constructor already opts into focus on Wayland.

    animated: true
    removeBorderStrategy: Plasmoid.location === PlasmaCore.Types.Floating
            ? PlasmaCore.AppletPopup.AtScreenEdges
            : PlasmaCore.AppletPopup.AtScreenEdges | PlasmaCore.AppletPopup.AtPanelEdges

    margin: (Plasmoid.containmentDisplayHints & PlasmaCore.Types.ContainmentPrefersFloatingApplets) ? Kirigami.Units.largeSpacing : 0

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

    // TaskSpot #11: the monitor this popup must stay on, passed in from
    // Task.qml by createSearchPopup() (initial properties). The Screen
    // attached property of THIS window is not reliably set before it is
    // first shown, and PlasmoidItem.screenGeometry does not exist in
    // Plasma 6.7.4 — reading it threw and silently killed the show.
    property real panelScreenWidth: 0
    property real panelScreenHeight: 0

    // TaskSpot #11: sizing translated from ToolTipDialog::updateSize()
    // (libplasma tooltipdialog.cpp), which sizes the stock tooltip window:
    // the window takes the mainItem's *implicit* size one-way (never the
    // reverse, so no binding loops), and is clamped to the monitor the
    // panel lives on. Like the stock dialog, this is re-run whenever the
    // mainItem's implicit size changes, which is how the asynchronous
    // ToolTipDelegate loader settles the final size after the popup is
    // already visible; PopupPlasmaWindow repositions on every resize.
    function updateSize() {
        const maxWidth = panelScreenWidth > 0 ? panelScreenWidth : Screen.width
        // Keep the half-monitor height cap TaskSpot chose in #11; content
        // taller than that scrolls inside the delegate.
        const maxHeight = panelScreenHeight > 0 ? panelScreenHeight / 2 : Screen.height / 2
        const w = Math.min(contentColumn.implicitWidth + leftPadding + rightPadding, maxWidth)
        const h = Math.min(contentColumn.implicitHeight + topPadding + bottomPadding, maxHeight)
        if (w > 0 && h > 0) {
            width = w
            height = h
        }
    }

    Connections {
        target: contentColumn

        function onImplicitWidthChanged() {
            searchPopup.updateSize()
        }

        function onImplicitHeightChanged() {
            searchPopup.updateSize()
        }
    }

    // TaskSpot #11: stock tooltips dismiss as soon as the pointer leaves
    // the tooltip (ToolTipDialog starts a 200ms hide timer on QEvent::Leave)
    // and stay alive while the pointer is back on the task button. The
    // search popup replicates that with a short grace timer, with one
    // extra exception: an in-progress search (non-empty field) is never
    // dismissed by the mouse, only by Escape, activation loss, or the
    // task button being clicked again. The HoverHandler lives inside the
    // mainItem: a window-level one would need hoverEnabled, which is an
    // Item property, not a handler property here.
    Timer {
        id: closeGraceTimer

        interval: 300
        onTriggered: {
            if (searchField.text === ""
                && !(searchPopup.task && searchPopup.task.containsMouse)) {
                searchPopup.visible = false
            }
        }
    }

    mainItem: ColumnLayout {
        id: contentColumn

        clip: true

        // TaskSpot #11: passive hover tracker for the dismissal grace
        // timer below. A HoverHandler enables hover events on its parent
        // item by itself; it does not steal hover or clicks from the
        // window cards.
        HoverHandler {
            id: popupHover

            onHoveredChanged: {
                if (hovered) {
                    closeGraceTimer.stop()
                } else {
                    closeGraceTimer.restart()
                }
            }
        }

        spacing: Kirigami.Units.smallSpacing

        PlasmaExtras.SearchField {
            id: searchField

            Layout.fillWidth: true
            placeholderText: i18n("Search windows…")

            Keys.onEscapePressed: searchPopup.visible = false
        }

        // The same component the stock tooltip renders, with the same
        // property wiring Task.qml's updateMainItemBindings() applies.
        // fillWidth + minimumWidth 0 let the ColumnLayout shrink it to the
        // window width when the card row is wider than the monitor; its
        // internal ScrollView then engages its horizontal scrollbar
        // (size < 1). Without this the delegate overflows at its implicit
        // width and gets clipped with no scrollbar — the stock tooltip
        // never hits this because its ScrollView is the window's mainItem
        // and is resized directly.
        //
        // The preferredHeight binding compensates for the scrollbar the
        // same squeezing produces: upstream implicitHeight only reserves
        // scrollbar space when contentWidth exceeds the *window's*
        // Screen.desktopAvailableWidth, which inside this popup resolves
        // to the whole virtual desktop (larger than any card row), so the
        // reservation never fires and the visible scrollbar would eat
        // exactly its own height out of the card viewport.
        ToolTipDelegate {
            id: toolTipContent

            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: implicitWidth

            Layout.fillHeight: true
            Layout.minimumHeight: 0
            Layout.preferredHeight: {
                const sv = toolTipContent.item
                const squeezed = searchPopup.width
                    - searchPopup.leftPadding - searchPopup.rightPadding < implicitWidth
                const scrollbarHeight = sv ? sv.ScrollBar.horizontal.height : 0
                return implicitHeight + (squeezed ? scrollbarHeight : 0)
            }

            parentTask: searchPopup.task
            rootIndex: tasksModel.makeModelIndex(searchPopup.task.index, -1)

            appName: searchPopup.task.model.AppName
            pidParent: searchPopup.task.model.AppPid
            windows: searchPopup.task.model.WinIdList
            isGroup: searchPopup.task.model.IsGroupParent
            icon: searchPopup.task.model.decoration
            launcherUrl: searchPopup.task.model.LauncherUrlWithoutIcon
            isLauncher: searchPopup.task.model.IsLauncher
            isMinimized: searchPopup.task.model.IsMinimized
            display: searchPopup.task.model.display
            genericName: searchPopup.task.model.GenericName
            virtualDesktops: searchPopup.task.model.VirtualDesktops
            isOnAllVirtualDesktops: searchPopup.task.model.IsOnAllVirtualDesktops
            activities: searchPopup.task.model.Activities
            isReadyForPainting: (searchPopup.task.model.Geometry?.width ?? 0) > 0
                                && (searchPopup.task.model.Geometry?.height ?? 0) > 0
        }
    }

    // TaskSpot #11: wheel-scroll the card row from anywhere over the
    // popup, including over the cards themselves and over the scrollbar.
    // The delegate's ScrollView installs a Kirigami WheelHandler that
    // consumes vertical wheel events without scrolling a horizontal-only
    // list, starving ancestor handlers over the cards; this overlay sits
    // on top of everything and sees the wheel first. It is button-less
    // and hover-less, so clicks and hover pass straight through to the
    // cards underneath (wheel up / left notch scrolls left).
    MouseArea {
        anchors.fill: parent
        z: 100
        acceptedButtons: Qt.NoButton
        hoverEnabled: false

        onWheel: event => {
            const list = toolTipContent.item
                ? toolTipContent.item.contentItem : null
            if (!list || list.contentWidth <= list.width) {
                event.accepted = false
                return
            }
            const notch = (event.angleDelta.y !== 0
                ? event.angleDelta.y : event.angleDelta.x) / 120
            const step = notch * Kirigami.Units.gridUnit * 4
            list.contentX = Math.max(0, Math.min(list.contentX - step,
                                                 list.contentWidth - list.width))
            event.accepted = true
        }
    }

    Component.onCompleted: {
        // Size before showing (ToolTipDialog::updateSize() ordering), so
        // the window is positioned against its visualParent with its real
        // size rather than being shown at a transient default and then
        // resized (see GroupDialog.qml for the visible-assignment rule).
        updateSize();
        visible = true;
    }

    onVisibleChanged: {
        if (visible) {
            requestActivate();
            searchField.forceActiveFocus();
        } else {
            tasks.searchPopup = null;
            destroy();
        }
    }

    onActiveChanged: {
        if (!active) {
            visible = false;
        }
    }
}
