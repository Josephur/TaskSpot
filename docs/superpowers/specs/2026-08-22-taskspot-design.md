# TaskSpot Design

- Date: 2026-08-22
- Status: Approved (design reviewed with project owner before implementation)
- License: GPL-2.0-or-later (forced: TaskSpot derives from plasma-desktop taskmanager code)

## Problem

On KDE Plasma 6 / Wayland, hovering an app icon in the default taskbar
opens the grouped-window popup ("group dialog") listing that app's open
windows as cards. There is no way to search this list. With many windows
or browser tabs it becomes unusable. TaskSpot adds live search to this
default popup:

1. Typing while the popup is open immediately filters window cards by title.
2. For browsers (Chrome/Chromium/Firefox), matching open tab titles also
   appear as individual results; clicking one activates the correct browser
   window and switches directly to that tab.
3. Clicking any result activates/focuses that window.

## Delivery shape (decision)

Two artifacts from one source tree:

- **Artifact A — default-behavior override.** A rebuild of the stock task
  manager plugin under its real ID (`org.kde.plasma.taskmanager`) with
  TaskSpot's search enhancements, installed user-locally. Because
  plasmashell resolves plugins through `QT_PLUGIN_PATH` with user-local
  directories first (`~/.local/lib/plugins`), our copy shadows the system
  one for every taskbar widget using it — both Icons-Only Task Manager and
  the text Task Manager (they share `X-Plasma-RootPath`). Uninstalling the
  file restores stock behavior.
- **Artifact B — standalone widget** under a distinct ID for users who do
  not want to shadow system components.

## Verified architecture facts (research log)

### Plugin resolution / override feasibility

- Modern Plasma ships the Icons-Only Task Manager as a metadata-only
  package (`X-Plasma-RootPath: org.kde.plasma.taskmanager`); all QML,
  including `GroupDialog.qml`, is compiled into
  `/usr/lib/qt6/plugins/plasma/applets/org.kde.plasma.taskmanager.so`.
  Nothing patchable on disk.
- `PluginLoader::loadApplet` (libplasma/src/plasma/pluginloader.cpp) looks
  up both the package metadata and the RootPath plugin by ID via Qt's
  standard plugin search order.
- The running plasmashell carries
  `QT_PLUGIN_PATH=$HOME/.local/lib/plugins:$HOME/.local/lib/qt6/plugins`,
  which precedes system paths. **M0 spike confirmed empirically**: a
  user-locally installed same-ID `.so` is loaded instead of the system one.

### Browser tabs — reuse Plasma Browser Integration (no new extension)

KDE's existing Plasma Browser Integration (PBI) already provides everything:

- Its WebExtension collects tabs (`chrome.tabs.query({windowType:"normal"})`)
  and forwards them over native messaging to the per-browser host process
  (`plasma-browser-integration-host`).
- The host exports DBus object `/TabsRunner`, interface `org.kde.krunner1`
  on session bus names matching `org.kde.plasma.browser_integration*`
  (one bus name per running browser instance):
  - `Match(query) -> a(sssida{sv})` — scored matches; match `id` is the
    decimal tab id, `text` the tab title, `properties.subtext` the URL.
    Empty queries are rejected by design; results come from a cache filled
    on first query per session.
  - `Run(matchId, actionId)` — with empty action id, activates the tab:
    extension does `chrome.tabs.update(tabId,{active:true})` then focuses
    the owning window. Wayland-safe (browser performs internal activation).
  - `Teardown()` — drops the host-side cache; call when our popup closes.
- Any third-party session-bus client may call this interface; no auth.
- Firefox needs the "Plasma Integration" add-on installed manually (AMO);
  Chrome-family installs from the Web Store. If absent → no tab results,
  window-title filtering still works (graceful degradation requirement).
- Gotchas handled: merge across all matching bus names; long timeout on
  first query (delayed reply while browser collects tabs); incognito
  filtered upstream; PBI's shipped introspection XML has a stale signature
  — use krunner's authoritative `a(sssida{sv})`.

### Type-to-filter UX — Klipper idiom

- Group dialogs are focus-taking windows even on Wayland
  (`setTakesFocus(true)` for PopupPlasmaWindow/AppletPopup role; tooltips
  deliberately refuse keyboard — we use the former).
- Proven pattern (plasma-workspace klipper ClipboardMenu.qml): root-level
  `Keys.onPressed` redirects printable characters and Backspace into a
  `PlasmaExtras.SearchField` and gives it active focus on first keystroke;
  arrow-key navigation keeps working on the list; Escape clears the filter
  first, second Escape closes.
- GroupDialog already calls `requestActivate()` + `forceActiveFocus()` on
  show, so typed input lands in the popup window.

## Component design

```
src/vendor/taskmanager/            vendored plasma-desktop applet (GPL-2.0-or-later)
  qml/GroupDialog.qml              MODIFIED: live search
  qml/main.qml                     near-stock
  <c++> BrowserTabs backend        NEW: DBus client exposed to QML
docs/                              design history
```

### Result provider seam

GroupDialog merges rows from independent providers sharing one contract:

```
provider = {
    available: bool,
    query(text),                 // async; results arrive via signal/property
    activate(resultId),
    results: [{ id, title, subtext, iconSource, kind }]
}
```

v1 providers:

- **WindowsProvider** (always present): filters the group's child windows
  (TasksModel children at `rootIndex`) case-insensitively by title.
  Activation via the stock task activation path.
- **BrowserTabsProvider** (present when PBI hosts detected): fans the
  query out to all `org.kde.plasma.browser_integration*` hosts (debounced
  ~150 ms), merges scored matches, activates via `Run(tabId, "")`.

Future providers plug into the same contract without touching GroupDialog.

### Interaction flow

1. Hover task → stock popup opens (unchanged).
2. First printable keypress reveals SearchField, captures input, list
   filters live.
3. Same text fans out to PBI hosts; tab matches append below window cards,
   visually distinct (favicon + URL subtext).
4. Enter/click → activate row (window or tab). Escape clears filter first;
   second Escape closes popup. Closing triggers `Teardown()` on all hosts.
5. No PBI / no matches → tabs silently absent.

## Testing strategy

- Build must stay warning-clean-ish; `plasmoidviewer -a
  org.kde.plasma.icontasks` runs the shadowed plugin without touching the
  running shell. QML console output goes to `journalctl --user`.
- Manual checklists per milestone committed to the repo
  (`docs/testing/checklist.md`): kitty multi-window filtering, Chrome +
  Firefox tab match→activate, multi-instance merge, no-PBI fallback,
  Wayland focus-loss behavior.
- Screenshots captured during verification where visual proof matters.

## Risks & fallbacks

| Risk | Mitigation |
| --- | --- |
| User-local `.so` shadow precedence breaks in future Plasma | M0 spike verified current behavior; fallback documented: extend `QT_PLUGIN_PATH` via `environment.d`, or distro-overlay install replacing the system `.so`. |
| Upstream drift between Plasma releases | Vendored source + documented re-sync procedure (own commit/issue per sync). Pin supported Plasma version(s) in README. |
| PBI absent/disabled | Tabs section hidden; window filtering unaffected (explicit graceful-degradation requirement). |
| Multiple browser instances | Query all `org.kde.plasma.browser_integration*` names, merge results. |

## Milestones

- **M0** Feasibility spike: build vendored plugin unmodified; prove same-ID
  user-local shadowing. ✅ completed 2026-08-22 (see issue #1)
- **M1** Repository scaffolding: AGENTS.md governance, README, LICENSES,
  GitHub repository, milestone issues.
- **M2** Baseline: vendored build reproduces stock behavior end-to-end.
- **M3** Live window-title filtering in GroupDialog (the minimal prototype:
  type-to-filter, Enter/click activation, kitty case covered).
- **M4** Browser-tab provider via PBI DBus (Chrome/Firefox live).
- **M5** Polish, docs, CI workflow, tag 0.1.0.
