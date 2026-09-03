# Popup as Default Hover UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the TaskSpot popup the hover UI for every eligible grouped task, so `taskspotSearchEnabled` controls only whether the search bar appears inside it, and add keyboard card navigation for the search-off case.

**Architecture:** One boolean term leaves `taskspotSearchEligible` in `Task.qml`, so the popup replaces the stock tooltip for grouped tasks unconditionally. `SearchPopup.qml` gains a `searchVisible` flag that hides the search bar and history strip, a `selectedIndex` browse-mode selection rendered as an overlay, and key handling lifted off `searchField` onto the popup content root. The popup's window model is unchanged — still an always-focusable `PopupPlasmaWindow` — so all existing dismissal logic keeps working.

**Tech Stack:** QML (Qt 6 / Qt Quick Layouts), Plasma 6 (`PlasmaCore.PopupPlasmaWindow`, `PlasmaExtras.SearchField`), Kirigami, CMake + qmlcachegen.

**Spec:** `docs/superpowers/specs/2026-09-03-popup-as-default-hover-ui-design.md`

## Global Constraints

- **No automated test framework exists.** This is a Plasma applet; Wayland input cannot be injected. The per-task gate is: `cmake --build build` succeeds (qmlcachegen compiles all QML, so syntax and property-resolution errors fail the build), plus the `plasmoidviewer` smoke run in Task 6. Real behavioral verification is the manual checklist in Task 6, run by the project owner. Do not invent a test harness for this plan.
- **Never edit `ToolTipDelegate.qml` or `ToolTipInstance.qml` ungated.** These are shared with stock task-manager widgets. #18 established a permanent stock A/B control on the same panel; an ungated change breaks it. The design's chosen approach avoids touching them at all.
- **Do not assign `takesFocus`** on `PopupPlasmaWindow` — it does not exist in Plasma 6.7.4, and assigning a non-existent property makes the component fail to compile so `createObject()` returns `null` (see the NOTE at `SearchPopup.qml:45-48`).
- **`searchField` stays instantiated when hidden**, never removed or conditionally created. `closeGraceTimer` (`SearchPopup.qml:304`), `activateFirstResult()` (`:88`) and `readonly property alias searchField` (`:43`) all reference it.
- **Scope:** grouped tasks only (`IsGroupParent && ChildCount >= 2`). Do not extend the popup to single-window tasks or launchers.
- **Out of scope:** `wheelEnabled` / "Scrolling Behaviour" reconciliation belongs to #15. Do not touch `MouseHandler.qml`.
- Vendored code is GPL-2.0-or-later from plasma-desktop; keep provenance headers intact and keep TaskSpot changes readable as a patch series.
- Reference issue **#25** in every commit.

---

### Task 1: Popup becomes the hover UI; search chrome hides

This task alone resolves the reported defect (wheel over cards does nothing with search off), because the popup's existing wheel overlay is now always present.

**Files:**
- Modify: `src/vendor/taskmanager/qml/Task.qml:97-99`
- Modify: `src/vendor/taskmanager/qml/SearchPopup.qml` (add property near `:43`; add `visible` on the `RowLayout` at `:345`)

**Interfaces:**
- Consumes: nothing.
- Produces: `searchPopup.searchVisible` — `bool`, true when the search bar is shown. Tasks 2, 4 and 5 read it.

- [ ] **Step 1: Drop the search-enabled term from eligibility**

In `Task.qml`, replace the `taskspotSearchEligible` binding (currently lines 97-99) with:

```qml
    readonly property bool taskspotSearchEligible: tasksRoot.isTaskSpot
        && model.IsGroupParent && model.ChildCount >= 2
```

Leave the comment block above it in place, and append to it:

```qml
    // TaskSpot (#25): eligibility no longer consults
    // taskspotSearchEnabled — the popup is the hover UI for every
    // eligible group, and that setting only controls whether the search
    // bar appears inside it (see SearchPopup.searchVisible).
```

- [ ] **Step 2: Add `searchVisible` to the popup**

In `SearchPopup.qml`, immediately after `readonly property alias searchField: searchField` (line 43), add:

```qml
    // TaskSpot #25: taskspotSearchEnabled controls only whether the
    // search bar is part of the popup. searchField stays instantiated
    // while hidden — closeGraceTimer and activateFirstResult() both
    // reference its text.
    readonly property bool searchVisible:
        Plasmoid.configuration.taskspotSearchEnabled !== false
```

- [ ] **Step 3: Hide the search bar and history strip together**

In `SearchPopup.qml`, on the `RowLayout` that holds `searchField` and `historyStrip` (opens at line 345), add as its first property:

```qml
            visible: searchPopup.searchVisible
```

A `visible: false` child is excluded from `ColumnLayout` sizing, so the popup shrinks to the cards on its own; no explicit height handling is needed.

- [ ] **Step 4: Build**

Run: `cmake --build build`
Expected: `[100%] Built target com.stack-tech.plasma.taskspot`, no QML compile errors.

- [ ] **Step 5: Commit**

```bash
git add src/vendor/taskmanager/qml/Task.qml src/vendor/taskmanager/qml/SearchPopup.qml
git commit -m "Use the TaskSpot popup for every eligible group (#25)"
```

---

### Task 2: Lift key handling onto the popup content root

With the bar hidden there is no `searchField` to hold focus, so Escape and Enter stop working. This moves the policy into functions on the popup and gives the content root its own handlers, while `searchField` keeps handlers that delegate to the same functions.

**Files:**
- Modify: `src/vendor/taskmanager/qml/SearchPopup.qml` (add functions near `:87`; `mainItem: ColumnLayout` at `:313`; `searchField` handlers at `:352-354`)

**Interfaces:**
- Consumes: `searchPopup.searchVisible` (Task 1), `activateFirstResult()` (existing, `:87`).
- Produces:
  - `searchPopup.searchMode` — `bool`, true when the bar is visible and its text is non-empty.
  - `searchPopup.handleEscape(event)` — clears the query if in search mode, else closes the popup.
  - `searchPopup.handleActivate(event)` — Enter policy; Task 4 extends it to activate the selected card.

- [ ] **Step 1: Add the mode property and key-policy functions**

In `SearchPopup.qml`, directly above `function activateFirstResult()` (line 87), add:

```qml
    // TaskSpot #25: the popup has two keyboard modes, switched by query
    // content rather than by a setting, so the mode is always visible on
    // screen. Browse mode (bar hidden, or bar visible with an empty
    // query) navigates cards; search mode filters and activates the
    // first result.
    readonly property bool searchMode: searchVisible && searchField.text !== ""

    function handleEscape(event): void {
        if (searchMode) {
            searchField.text = "";
            event.accepted = true;
            return;
        }
        searchPopup.visible = false;
        event.accepted = true;
    }

    function handleActivate(event): void {
        if (searchMode) {
            activateFirstResult();
        }
        event.accepted = true;
    }
```

- [ ] **Step 2: Give the content root focus and handlers**

In `SearchPopup.qml`, in `mainItem: ColumnLayout { id: contentColumn` (line 313), add after `clip: true`:

```qml
        focus: true

        // TaskSpot #25: key policy lives here, not on searchField, so it
        // still works when the search bar is hidden. searchField keeps
        // its own handlers because a focused TextField consumes these
        // keys before they reach an ancestor.
        Keys.onEscapePressed: event => searchPopup.handleEscape(event)
        Keys.onReturnPressed: event => searchPopup.handleActivate(event)
        Keys.onEnterPressed: event => searchPopup.handleActivate(event)
```

- [ ] **Step 3: Delegate the field's handlers to the same functions**

In `SearchPopup.qml`, replace the three `searchField` handlers (lines 352-354) with:

```qml
                Keys.onEscapePressed: event => searchPopup.handleEscape(event)
                Keys.onReturnPressed: event => searchPopup.handleActivate(event)
                Keys.onEnterPressed: event => searchPopup.handleActivate(event)
```

- [ ] **Step 4: Build**

Run: `cmake --build build`
Expected: builds clean. A typo in an arrow-function handler surfaces here as a qmlcachegen error.

- [ ] **Step 5: Commit**

```bash
git add src/vendor/taskmanager/qml/SearchPopup.qml
git commit -m "Move popup key policy off the search field (#25)"
```

---

### Task 3: Browse-mode selection state and highlight overlay

**Files:**
- Modify: `src/vendor/taskmanager/qml/SearchPopup.qml` (add state near `:87`; add overlay near the existing wheel overlay at `:448`)

**Interfaces:**
- Consumes: `searchPopup.searchMode` (Task 2).
- Produces:
  - `searchPopup.selectedIndex` — `int`, index into the card ListView; `-1` means no selection.
  - `searchPopup.cardList` — the card `ListView`, or `null` before content loads.
  - `searchPopup.moveSelection(delta)` — clamps, scrolls the card into view.

- [ ] **Step 1: Add selection state**

In `SearchPopup.qml`, after the `searchMode` property added in Task 2, add:

```qml
    // TaskSpot #25: browse-mode card selection. -1 means nothing is
    // selected, which is the state a freshly opened popup starts in, so
    // Enter cannot raise a window the user never pointed at.
    property int selectedIndex: -1

    readonly property var cardList: toolTipContent.item
        ? toolTipContent.item.contentItem : null

    function moveSelection(delta: int): void {
        const list = cardList;
        if (!list || list.count <= 0) {
            return;
        }
        let next = selectedIndex < 0
            ? (delta > 0 ? 0 : list.count - 1)
            : selectedIndex + delta;
        next = Math.max(0, Math.min(next, list.count - 1));
        selectedIndex = next;
        list.positionViewAtIndex(next, ListView.Contain);
    }

    function activateSelectedCard(): void {
        const list = cardList;
        if (!list || selectedIndex < 0 || selectedIndex >= list.count) {
            return;
        }
        tasksModel.requestActivate(
            tasksModel.makeModelIndex(searchPopup.task.index, selectedIndex));
        searchPopup.visible = false;
    }
```

Note `activateSelectedCard()` uses the same `makeModelIndex(task.index, childRow)` form as `activateFirstResult()` at line 97; in browse mode the query is empty, so card position and child row coincide.

- [ ] **Step 2: Reset the selection whenever the card set changes**

In `SearchPopup.qml`, immediately after the block added in Step 1, add:

```qml
    onSearchModeChanged: selectedIndex = -1
    onVisibleChanged: if (!visible) { selectedIndex = -1; }
```

- [ ] **Step 3: Add the highlight overlay**

In `SearchPopup.qml`, directly above the existing wheel-overlay `MouseArea` (line 448), add:

```qml
    // TaskSpot #25: browse-mode selection is drawn here rather than as a
    // ListView highlight, because the card list lives in shared
    // ToolTipDelegate.qml which stock widgets also use (#18's A/B
    // control). Same instinct as the wheel overlay below.
    Rectangle {
        id: selectionHighlight

        readonly property Item card: searchPopup.selectedIndex >= 0
            && searchPopup.cardList
            ? searchPopup.cardList.itemAtIndex(searchPopup.selectedIndex)
            : null

        z: 99
        visible: card !== null
        color: "transparent"
        radius: Kirigami.Units.cornerRadius
        border.width: 2
        border.color: Kirigami.Theme.highlightColor

        x: card ? card.mapToItem(parent, 0, 0).x : 0
        y: card ? card.mapToItem(parent, 0, 0).y : 0
        width: card ? card.width : 0
        height: card ? card.height : 0
    }
```

- [ ] **Step 4: Keep the highlight glued to the card while the row scrolls**

`mapToItem` is not reactive to scrolling, so add inside the `Rectangle` from Step 3:

```qml
        Connections {
            target: searchPopup.cardList
            enabled: selectionHighlight.card !== null

            function onContentXChanged() {
                selectionHighlight.x =
                    selectionHighlight.card.mapToItem(selectionHighlight.parent, 0, 0).x;
            }
        }
```

- [ ] **Step 5: Build**

Run: `cmake --build build`
Expected: builds clean.

- [ ] **Step 6: Commit**

```bash
git add src/vendor/taskmanager/qml/SearchPopup.qml
git commit -m "Add browse-mode card selection and highlight overlay (#25)"
```

---

### Task 4: Browse-mode arrow keys and Enter

**Files:**
- Modify: `src/vendor/taskmanager/qml/SearchPopup.qml` (`handleActivate` from Task 2; `contentColumn` handlers from Task 2)

**Interfaces:**
- Consumes: `moveSelection(delta)`, `activateSelectedCard()`, `selectedIndex` (Task 3); `searchMode`, `handleActivate` (Task 2).
- Produces: `searchPopup.handleArrow(event, delta)` — Task 5 reuses it from the search field.

- [ ] **Step 1: Teach Enter about the selection**

In `SearchPopup.qml`, replace the `handleActivate` function body from Task 2 with:

```qml
    function handleActivate(event): void {
        if (searchMode) {
            activateFirstResult();
        } else {
            activateSelectedCard();
        }
        event.accepted = true;
    }
```

- [ ] **Step 2: Add the arrow-key policy function**

In `SearchPopup.qml`, directly below `handleActivate`, add:

```qml
    // TaskSpot #25: Left/Right drive the cards until the user starts
    // typing; from then on they belong to the text cursor.
    function handleArrow(event, delta: int): void {
        if (searchMode) {
            return; // not accepted — falls through to the text cursor
        }
        moveSelection(delta);
        event.accepted = true;
    }
```

- [ ] **Step 3: Bind the arrows on the content root**

In `SearchPopup.qml`, in `contentColumn`, add below the `Keys.onEnterPressed` line from Task 2:

```qml
        Keys.onLeftPressed: event => searchPopup.handleArrow(event, -1)
        Keys.onRightPressed: event => searchPopup.handleArrow(event, 1)
```

- [ ] **Step 4: Build**

Run: `cmake --build build`
Expected: builds clean.

- [ ] **Step 5: Commit**

```bash
git add src/vendor/taskmanager/qml/SearchPopup.qml
git commit -m "Navigate cards with Left/Right in browse mode (#25)"
```

---

### Task 5: Arrow keys with the search bar visible

With the bar visible and empty, `searchField` holds focus and a `TextField` consumes Left/Right before they reach `contentColumn`. The field needs its own arrow handlers delegating to the same policy, so the keys drive cards until typing starts.

**Files:**
- Modify: `src/vendor/taskmanager/qml/SearchPopup.qml` (`searchField`, near the handlers from Task 2)

**Interfaces:**
- Consumes: `handleArrow(event, delta)` (Task 4).
- Produces: nothing.

- [ ] **Step 1: Add arrow handlers to the search field**

In `SearchPopup.qml`, in the `PlasmaExtras.SearchField` block, add below its `Keys.onEnterPressed` line:

```qml
                Keys.onLeftPressed: event => searchPopup.handleArrow(event, -1)
                Keys.onRightPressed: event => searchPopup.handleArrow(event, 1)
```

Because `handleArrow` leaves the event unaccepted in search mode, a non-empty query lets the `TextField` handle the key normally and the cursor moves.

- [ ] **Step 2: Build**

Run: `cmake --build build`
Expected: builds clean.

- [ ] **Step 3: Commit**

```bash
git add src/vendor/taskmanager/qml/SearchPopup.qml
git commit -m "Give Left/Right to the text cursor once typing starts (#25)"
```

---

### Task 6: Install, smoke test, and hand off for manual verification

**Files:**
- No source changes. Deploys the built plugin over the running installation.

**Interfaces:**
- Consumes: everything above.
- Produces: a deployed build and the manual checklist result.

- [ ] **Step 1: Full clean build**

Run:

```bash
cmake -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$HOME/.local && cmake --build build
```

Expected: `[100%] Built target com.stack-tech.plasma.taskspot`.

- [ ] **Step 2: Isolated smoke run before touching the live shell**

Run: `plasmoidviewer -a com.stack-tech.plasma.taskspot`

Expected: the widget loads. QML output goes to `journalctl --user`, not stderr — check it with `journalctl --user -n 80 --no-pager | grep -iE "taskspot|qml"`. Expected: no QML errors. Close the viewer before continuing.

- [ ] **Step 3: Install**

Run: `cmake --install build`
Expected: the plugin and both plasmoid packages install under `$HOME/.local`.

- [ ] **Step 4: Restart the shell**

Run: `systemctl --user restart plasma-plasmashell.service`

Then confirm it came back clean:

```bash
journalctl --user -u plasma-plasmashell -b --since "1 minute ago" --no-pager | grep -iE "taskspot|error" | head -20
```

Expected: no TaskSpot errors.

- [ ] **Step 5: Hand the manual checklist to the project owner**

Wayland input cannot be injected, so these are the owner's to run. With `taskspotSearchEnabled=false`:

1. Hovering a grouped task (2+ windows) shows the popup with cards and **no** search bar.
2. Wheel over the cards scrolls them — **the originally reported defect**.
3. Left/Right move the selection highlight; Enter raises the selected window; Escape closes.

Then re-enable the search bar in the widget's settings and confirm:

4. Empty query: Left/Right still move the card selection.
5. Typing filters the cards; Left/Right now move the text cursor; Enter raises the first result.
6. Escape with a query clears it and returns to browse mode; Escape again closes.
7. Right-click a card: the context menu stays open (#19 unbroken).
8. The stock task-manager widget on the same panel still shows its normal tooltip (#18 A/B control unbroken).

- [ ] **Step 6: Record the result on the issue**

Post the checklist outcome to #25. Close it only once the owner confirms items 1-8, per AGENTS.md.

---

## Self-Review

**Spec coverage:** §1 eligibility → Task 1 Step 1. §2 search chrome → Task 1 Steps 2-3. §3 keyboard modes table → Tasks 2 (Escape/Enter), 4 (browse arrows, Enter-on-selection), 5 (search-mode cursor). §4 key ownership → Task 2. §5 selection rendering via overlay → Task 3, with the shared-delegate fallback recorded in the spec and deliberately not planned (take it only if Task 3's overlay proves unreliable during Task 6's manual check). §6 wheel defect → resolved by Task 1, verified at Task 6 Step 5 item 2. Spec testing list → Task 6 Step 5.

**Placeholder scan:** No TBDs; every code step carries the literal QML to insert.

**Type consistency:** `searchVisible` (Task 1) is read in Tasks 2, 4, 5. `searchMode`, `handleEscape`, `handleActivate` (Task 2) are extended in Task 4 and reused in Task 5. `selectedIndex`, `cardList`, `moveSelection`, `activateSelectedCard` (Task 3) are consumed in Task 4. `handleArrow` (Task 4) is reused in Task 5. Names match across tasks.
