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
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import plasma.applet.com.stack_tech.plasma.taskspot as TaskManagerApplet

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

    // TaskSpot #12: live-filtered view of the hovered group's child
    // windows, fed to the ToolTipDelegate (see filterModel there). The
    // filter tracks the search field; a filter matching nothing falls
    // back to the full child list (fallbackToUnfiltered) so the popup
    // never goes empty — showingUnfiltered lets Enter ignore fallback
    // rows that are not real results. groupRow is a plain int property:
    // Q_INVOKABLE methods on this registered type were observed invisible
    // to the QML engine, while properties kept working.
    TaskManagerApplet.TaskSpotFilterProxyModel {
        id: taskFilterModel

        sourceModel: tasksModel
        filter: searchField.text
        fallbackToUnfiltered: true
        groupRow: searchPopup.task.index
    }

    // TaskSpot #12: Enter activates the first real search result (never
    // fallback rows) and closes the popup, GroupDialog-style.
    function activateFirstResult(): void {
        if (searchField.text === "" || taskFilterModel.showingUnfiltered
            || taskFilterModel.sourceRows.length <= 0) {
            return;
        }
        const childRow = taskFilterModel.sourceRows[0];
        if (childRow < 0) {
            return;
        }
        recordCompletedSearch();
        tasksModel.requestActivate(tasksModel.makeModelIndex(searchPopup.task.index, childRow));
        searchPopup.visible = false;
    }

    // TaskSpot #16: completed-search history, scoped per application. An
    // entry is recorded only when a typed query lands somewhere (card
    // click or Enter); persisted per widget as JSON blobs in the
    // searchHistory config key, each tagged with the hovered group's app
    // identity so a popup shows only the searches completed from that
    // same app's popup. Displayed most-used first so favorites migrate
    // toward the textbox.
    property var searchHistoryEntries: []

    // TaskSpot #16: identity of the app whose history this popup shows:
    // the .desktop id the task manager groups by (the same AppId
    // filtermodel relocates groups by), falling back to AppName for
    // windows that report no launcher. Both may be empty for
    // unidentifiable windows; those share one bucket.
    readonly property string historyAppId: {
        const t = task
        if (!t) {
            return ""
        }
        const id = String(t.model.AppId ?? "")
        return id !== "" ? id : String(t.model.AppName ?? "")
    }

    onHistoryAppIdChanged: refreshHistory()

    // TaskSpot #16: rank key shared by display and persistence — usage
    // count desc, then most recent use.
    function rankNewerFirst(a, b) {
        return (b.n - a.n) || (b.t - a.t)
    }

    // TaskSpot #16: parse the config key into entry objects. Entries
    // without the app tag predate per-app scoping (#14 format) and
    // cannot be attributed to an app; they are ignored and dropped on
    // the next write.
    function readStoredHistory() {
        const raw = Plasmoid.configuration.searchHistory || []
        const entries = []
        for (const s of raw) {
            try {
                const o = JSON.parse(s)
                if (o && o.q && typeof o.a === "string") {
                    entries.push(o)
                }
            } catch (e) {}
        }
        return entries
    }

    // TaskSpot #16: write back while keeping every other app's entries:
    // the caller passes the current app's entries already ranked, so the
    // first 50 per app (this app's best, other apps' stored order) are
    // kept. A global cap bounds the config key across many apps.
    function writeStoredHistory(allEntries) {
        const perAppCount = ({})
        const kept = []
        for (const e of allEntries) {
            perAppCount[e.a] = (perAppCount[e.a] || 0) + 1
            if (perAppCount[e.a] <= 50) {
                kept.push(e)
            }
        }
        if (kept.length > 400) {
            kept.sort(rankNewerFirst)
            kept.length = 400
        }
        Plasmoid.configuration.searchHistory = kept.map(e => JSON.stringify(e))
    }

    // TaskSpot #16: merge the current app's ranked entries back into the
    // stored list without disturbing other apps', then reload the strip.
    function commitAppEntries(appEntries) {
        appEntries.sort(rankNewerFirst)
        const others = readStoredHistory().filter(e => e.a !== historyAppId)
        writeStoredHistory(others.concat(appEntries))
        refreshHistory()
    }

    function refreshHistory(): void {
        // TaskSpot #14: history paused → strip hidden; stored entries are
        // retained so re-enabling restores the labels.
        if (Plasmoid.configuration.taskspotSearchHistoryEnabled === false) {
            searchHistoryEntries = []
            return
        }
        const mine = readStoredHistory().filter(e => e.a === historyAppId)
        mine.sort(rankNewerFirst)
        searchHistoryEntries = mine
    }

    function recordCompletedSearch(): void {
        const q = searchField.text.trim()
        // TaskSpot #14: a fallback search (nothing matched, all cards
        // shown) is not a completed search — only queries that actually
        // matched a card get recorded. Paused history records nothing.
        if (q === "" || taskFilterModel.showingUnfiltered
            || Plasmoid.configuration.taskspotSearchHistoryEnabled === false) {
            return
        }
        // TaskSpot #16: searchHistoryEntries already holds just this
        // app's entries; new ones are tagged with this popup's app.
        const entries = searchHistoryEntries.slice()
        const now = Date.now()
        const existing = entries.find(e => e.q.toLowerCase() === q.toLowerCase())
        if (existing) {
            existing.n = (existing.n || 1) + 1
            existing.t = now
            existing.q = q // latest casing wins
        } else {
            entries.push({ q: q, n: 1, t: now, a: historyAppId })
        }
        commitAppEntries(entries)
    }

    // TaskSpot #14: clicking a history label counts toward that entry's
    // usage, promoting it (count desc, then recency) closer to the box.
    function bumpHistoryEntry(query: string): void {
        const entries = searchHistoryEntries.slice()
        const existing = entries.find(e => e.q.toLowerCase() === query.toLowerCase())
        if (!existing) {
            return
        }
        existing.n = (existing.n || 1) + 1
        existing.t = Date.now()
        commitAppEntries(entries)
    }

    Connections {
        target: Plasmoid.configuration
        function onSearchHistoryChanged() {
            searchPopup.refreshHistory()
        }
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

        // TaskSpot #14: search field at a natural width, with the
        // completed-search history strip filling the rest of the popup
        // width. Labels are buttons (border + hover/press = clickable
        // separate items); clicking one re-runs that search.
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PlasmaExtras.SearchField {
                id: searchField

                Layout.preferredWidth: Kirigami.Units.gridUnit * 16
                Layout.alignment: Qt.AlignVCenter
                placeholderText: i18n("Search windows…")

                Keys.onEscapePressed: searchPopup.visible = false
                Keys.onReturnPressed: searchPopup.activateFirstResult()
                Keys.onEnterPressed: searchPopup.activateFirstResult()
            }

            ListView {
                id: historyStrip

                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                orientation: ListView.Horizontal
                spacing: Kirigami.Units.smallSpacing
                model: searchPopup.searchHistoryEntries

                delegate: PlasmaComponents3.Button {
                    required property var modelData

                    text: modelData.q
                    onClicked: {
                        searchPopup.bumpHistoryEntry(modelData.q)
                        searchField.text = modelData.q
                    }
                }
            }
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

            // TaskSpot #12: route the card list through the live filter.
            filterModel: taskFilterModel

            // TaskSpot #14: a card click completes the typed search.
            onCardActivated: searchPopup.recordCompletedSearch()

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
            // TaskSpot #14: scroll the history strip along with the cards
            // when it overflows too.
            if (historyStrip.contentWidth > historyStrip.width) {
                historyStrip.contentX = Math.max(0,
                    Math.min(historyStrip.contentX - step,
                             historyStrip.contentWidth - historyStrip.width))
            }
            event.accepted = true
        }
    }

    Component.onCompleted: {
        // Size before showing (ToolTipDialog::updateSize() ordering), so
        // the window is positioned against its visualParent with its real
        // size rather than being shown at a transient default and then
        // resized (see GroupDialog.qml for the visible-assignment rule).
        updateSize();
        // TaskSpot #14: load the persisted history — each hover creates a
        // fresh popup instance, and the config-change connection below
        // only fires on writes made during this popup's lifetime.
        refreshHistory();
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
