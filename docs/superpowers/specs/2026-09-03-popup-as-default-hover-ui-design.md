# Popup as Default Hover UI Design (#25)

- Date: 2026-09-03
- Status: Approved for implementation (design approved by project owner in chat 2026-09-03; full pipeline directed in the same request)
- Related: #25 (this work), #7 (hover search popup), #11/#14/#19 (popup dismissal paths this design must preserve), #15 (wheel/"Scrolling Behaviour" reconciliation — explicitly out of scope), #18 (plugin-ID migration, whose stock A/B control this design must not break)
- License: GPL-2.0-or-later (unchanged; vendored plasma-desktop code)

## Problem

`taskspotSearchEnabled=false` was reported as breaking wheel-scrolling of
the hover cards. Investigation showed this is not a regression: card
scrolling has never worked outside the search popup.

`PlasmaComponents3.ScrollView` installs a Kirigami `WheelHandler` that
consumes vertical wheel events without scrolling a horizontal-only
`ListView`. #7 worked around this with a `z: 100`, button-less,
hover-less overlay `MouseArea` that sees the wheel first
(`SearchPopup.qml:442-472`). The stock tooltip has the identical shape —
`PlasmaComponents3.ScrollView` wrapping the horizontal
`groupToolTipListView` (`ToolTipDelegate.qml:108-143`) — **minus that
overlay**. Vertical wheel over stock cards is therefore swallowed.

Turning the search bar off swaps TaskSpot's popup for the stock tooltip,
and the overlay goes with it. The symptom is a side effect of a deeper
structural fact: `taskspotSearchEnabled` currently gates *which hover UI
appears*, not *what that UI contains*.

## Decision

Porting the wheel overlay into the stock tooltip was considered and
rejected. Instead, the popup becomes TaskSpot's hover UI for grouped
tasks, and `taskspotSearchEnabled` controls only whether the search bar
is present inside it. Future TaskSpot features gain a surface to appear
in rather than each needing its own tooltip patch.

This is a product-boundary change, not only a bug fix: on a TaskSpot
widget, a grouped task's hover popup is always TaskSpot's.

## Architecture

### 1. Eligibility

`Task.qml:97` drops the `taskspotSearchEnabled !== false` term:

```qml
readonly property bool taskspotSearchEligible: tasksRoot.isTaskSpot
    && model.IsGroupParent && model.ChildCount >= 2
```

`ToolTipArea.active` (`Task.qml:101`) already derives from
`taskspotSearchEligible`, so the stock tooltip stays correctly suppressed
for eligible groups with no further change.

**Scope boundary:** single-window tasks, pinned launchers, and every
stock task-manager widget are untouched. `ToolTipDelegate.qml` is shared
with stock widgets, so #18's permanent A/B control on the same panel
survives intact. Any change to that shared file must be gated on
`isTaskSpot`.

### 2. Search chrome visibility

A `readonly property bool searchVisible` on the popup mirrors
`Plasmoid.configuration.taskspotSearchEnabled !== false`, driving
`visible` on the `RowLayout` that holds `searchField` and `historyStrip`
(`SearchPopup.qml:345`).

Both hide together. Search history without a search bar is meaningless,
and `taskspotSearchHistoryEnabled` is already gated behind the search
checkbox in `ConfigBehavior.qml:128`.

### 3. Two keyboard modes

Mode is determined by query content, which is visible on screen rather
than hidden in a setting. With the bar hidden, browse mode is the only
reachable mode.

| Key | Browse mode (query empty or bar hidden) | Search mode (query non-empty) |
|---|---|---|
| Left / Right | move card selection | move the text cursor |
| Enter | activate the selected card | `activateFirstResult()` (unchanged) |
| Escape | close the popup | clear the query, returning to browse mode |
| Wheel | scroll cards (unchanged) | scroll cards (unchanged) |

Typing any printable character enters search mode; clearing the field
returns to browse mode. Search mode deliberately has **no** card
selection — filtering plus Enter is that mode's purpose, and a second
selection concept would compete with it.

### 4. Key ownership

All key handling currently lives on `searchField`
(`SearchPopup.qml:352-354`) — even Escape works only because that field
holds focus. With the bar hidden there is no such field, so handlers move
to the popup's content root, which owns Escape, Enter, and the arrow
keys. `searchField` keeps text input when visible; printable keys
arriving at the root are forwarded into the field, which is what enters
search mode.

The popup's window model is unchanged: it remains an always-focusable
`PlasmaCore.PopupPlasmaWindow` whose C++ constructor opts into focus. One
window model in every mode means the dismissal logic from #11, #14 and
#19 — `onActiveChanged`, `closeGraceTimer`, the `menuOpen` gate — keeps
working untouched. The accepted cost is that hovering a grouped task
takes activation even when the bar is hidden.

### 5. Card selection rendering

Cards are stock `ToolTipInstance` delegates inside `groupToolTipListView`
in shared `ToolTipDelegate.qml`. The popup drives `currentIndex` on that
list and renders the selection highlight as an **overlay inside
`SearchPopup.qml`**, following the same instinct as the existing wheel
overlay and leaving the shared file untouched.

Fallback if positioning an overlay over list items proves unreliable: add
a `highlight` component in `ToolTipDelegate.qml` gated on `isTaskSpot`.
The fallback is second choice precisely because it edits shared code.

### 6. Resolution of the original defect

No dedicated fix is required. With the popup always used for grouped
tasks, its wheel overlay is always present, so wheel-over-cards works
with the search bar off.

## Out of scope

- Reconciling the popup's wheel handling with the `wheelEnabled`
  "Scrolling Behaviour" setting — stays in #15.
- Popups for single-window tasks and pinned launchers.
- Renaming the `taskspotSearchEnabled` config key; its meaning ("the
  search bar is shown") remains accurate, and keeping it avoids a config
  migration.

## Testing

Wayland input cannot be injected, so verification is manual by the
project owner. Build and deploy per AGENTS.md, restart plasmashell, then:

1. Search off: hovering a grouped task shows a popup with cards and no
   search bar.
2. Search off: wheel over the cards scrolls them (the original defect).
3. Browse mode: Left/Right move the selection; Enter raises the selected
   window; Escape closes.
4. Typing a character reveals search mode: cards filter, Left/Right now
   move the text cursor, Enter raises the first result.
5. Escape with a query clears it and returns to browse mode; Escape again
   closes.
6. Search on with an empty query behaves as browse mode.
7. Right-click a card: the context menu stays open (#19 unbroken).
8. A stock task-manager widget on the same panel still shows its normal
   tooltip (#18 A/B control unbroken).
