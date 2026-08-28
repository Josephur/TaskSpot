# Plugin-ID Migration Design (#18)

- Date: 2026-08-28
- Status: Approved for implementation (ID approved by project owner in chat 2026-08-28; full pipeline directed in kickoff request)
- Related: #18 (this work), #10 (two-compiled-plugins collision finding), #17 (precondition, closed not-a-bug); replaces the delivery shape in `2026-08-22-taskspot-design.md`
- License: GPL-2.0-or-later (unchanged; vendored plasma-desktop code)

## Problem

TaskSpot today installs a rebuilt copy of the **stock plugin ID**
(`org.kde.plasma.taskmanager.so`) user-locally, shadowing the system copy
for every task-manager widget in the shell. This gives a TaskSpot
regression a blast radius over stock widgets (#17), makes #10's
two-compiled-plugins type collision structurally possible again, and can
never be distributed (distro/KDE Store packaging cannot shadow a system
plugin file).

## Decision

Build TaskSpot as its **own compiled applet plugin** with a distinct
identity and retire the shadowing strategy entirely:

- **Plugin / applet ID (public, approved):** `com.stack-tech.plasma.taskspot`
- **QML module URI (internal):** `plasma.applet.com.stack_tech.plasma.taskspot`

The dash vs. underscore split is forced: QML import URIs require each
dot-separated segment to be a valid JS identifier (letters, digits,
underscore — no dash). The public ID keeps the approved dash; only the
QML `import` lines use the underscore form.

After this lands, stock task managers run pristine upstream code and
double as a permanent control group; a TaskSpot regression can no longer
affect them.

## Design

### 1. Type rename (mechanical, its own commit)

Per #10: with both plugins loaded in one plasmashell process, identical
type-name sets cross-wire QML type resolution even under different module
URIs. Since stock `org.kde.plasma.taskmanager.so` (system copy) stays
present, TaskSpot's vendored C++ types must differ in **both** C++
identity and QML-visible name:

- Wrap `Backend`, `TaskFilterProxyModel`, `SmartLauncherBackend`,
  `SmartLauncherItem` in `namespace TaskSpot { ... }` (headers + sources).
- With `QML_ELEMENT` inside the namespace, qmltyperegistrar registers
  them as `TaskSpot.Backend`, `TaskSpot.TaskFilterProxyModel`, etc.
  (default namespace mapping; **no** `QML_NAMED_ELEMENT` overrides —
  keeping the bare QML name `Backend` would recreate exactly the #10
  condition).
- QML references to C++ types gain the namespace segment
  (`TaskManagerApplet.Backend` → `TaskManagerApplet.TaskSpot.Backend`,
  including `required property` annotations and enum reads like
  `TaskManagerApplet.TaskSpot.Backend.Close`) — ~15 sites in 6 files.
- The import alias `TaskManagerApplet` is **kept** so JS-library
  references (`TaskManagerApplet.TaskTools.*`,
  `TaskManagerApplet.LayoutMetrics.*`) and every other qualified
  reference stay untouched; upstream syncs stay a readable patch series.

### 2. Identity swap (second commit)

- **Target:** replicate `plasma_add_applet`'s body in
  `src/vendor/taskmanager/CMakeLists.txt` with one delta — module URI
  `plasma.applet.com.stack_tech.plasma.taskspot` instead of the derived
  `plasma.applet.${id}` — because the macro cannot express a dashed
  target with an underscored URI. The copied block keeps a provenance
  comment pointing at `/usr/lib/cmake/Plasma/PlasmaMacros.cmake`.
  Resulting artifacts: `com.stack-tech.plasma.taskspot.so` in
  `${KDE_INSTALL_PLUGINDIR}/plasma/applets` (same directory the shadowed
  copy used), generated plugin class
  `com_stack_tech_plasma_taskspot_Plugin`.
- **metadata.json:** rewritten as TaskSpot's own (Id
  `com.stack-tech.plasma.taskspot`, Name "TaskSpot", description from the
  retired sibling package, author Josephur, TaskSpot website,
  GPL-2.0-or-later, `X-Plasma-Provides: org.kde.plasma.multitasking`,
  `EnabledByDefault: false`). Upstream's translated author/description
  blocks are dropped — they belong to upstream's metadata.
- **QML imports:** all 8 `import plasma.applet.org.kde.plasma.taskmanager
  as TaskManagerApplet` lines move to the underscored new URI.
- **Applet-ID checks:** `ConfigBehavior.qml` (4 sites) and `main.qml`
  (`isTaskSpot`) switch from `Plasmoid.pluginName === "org.kde.taskspot"`
  to the new ID. The `iconsOnly` icontasks check stays (always false,
  keeps upstream diff minimal).
- **i18n:** `TRANSLATION_DOMAIN` and `Messages.sh` pot name become
  `plasma_applet_com.stack-tech.plasma.taskspot`.
- **Logging:** category `com.stack-tech.plasma.taskspot`, identifier
  renamed `TASKSPOT_DEBUG` (update the few C++ uses).
- **Retire the sibling:** delete `src/packages/` (`org.kde.taskspot`
  metadata-only package and its install rule) and the `add_subdirectory`
  in the root `CMakeLists.txt`. The `X-Plasma-RootPath` trick dies with
  it; there is exactly one TaskSpot artifact.

### 3. What intentionally does not change

- Install location (`~/.local/lib/plugins/plasma/applets/` when prefixed
  with `$HOME/.local`), QML embedded via qrc in the `.so`, config schema
  (`main.xml` including `taskspotSearch*` keys — existing per-widget
  config values carry over when copied), all TaskSpot feature behavior,
  the vendored provenance/patch-series discipline.

## Deployment / user migration

Order matters so the panel transitions cleanly with one shell restart:

1. Build + install the new plugin (`cmake --build && cmake --install`).
2. Remove old artifacts:
   - `~/.local/lib/plugins/plasma/applets/org.kde.plasma.taskmanager.so`
     (restores pristine stock behavior for stock widgets)
   - stale `org.kde.plasma.taskmanager.so.taskspot-disabled`,
     `org.kde.taskspot.so.taskspot-disabled` leftovers
   - `~/.local/share/plasma/plasmoids/org.kde.taskspot/`
3. Back up `~/.config/plasma-org.kde.plasma.desktop-appletsrc`.
4. Restart plasmashell. The old `org.kde.taskspot` widget instance shows
   as an empty placeholder until step 5 completes.
5. Migrate panel widgets via Plasma scripting (evaluateScript): for each
   applet with `plugin: org.kde.taskspot`, create a
   `com.stack-tech.plasma.taskspot` applet at the same position in the
   same container, copy its config groups, then remove the old applet.
   The snippet is recorded on #18 and in `docs/` for reuse.
6. Verify via journalctl + scripting queries.

Stock task managers (if any) need no migration and gain the pristine
system plugin back automatically.

**Manual (user) verification after deploy** — Wayland input can't be
injected, so hover tests stay human: hover grouping popups open the
search popup, live filter narrows cards, Enter activates a result,
settings toggles apply, right-click menu works, drag-reorder with
Sort: Manually, and stock task managers behave normally on the same
panel (A/B control).

## Testing (agent-side, before deploy)

- Clean Release build: qmlcachegen compiles every QML file, so a bad
  import URI, unresolved qualified type name, or registration failure
  fails the build — the main automated gate for the rename.
- Inspect generated `qmldir` / `.qmltypes` for the new module: `TaskSpot.`
  prefixed types present, module URI correct.
- `DESTDIR` staging: install layout exactly one `.so`, no sibling
  package, no stray files.
- `plasmoidviewer -a com.stack-tech.plasma.taskspot` smoke run: loads
  without QML errors (startup tick visible in `journalctl --user`).
- Post-restart plasmashell journal free of plugin/QML errors; migrated
  widget present with config intact (scripting query).

## Risks / fallbacks

- **3-segment qualified type annotations** (`TaskManagerApplet.TaskSpot.Backend`)
  in `required property` lines are valid QML grammar but rarely used;
  if a tool (qmlcachegen/qmllint) rejects them, fallback is distinct
  unqualified names (`QML_NAMED_ELEMENT(TaskSpotBackend)` on a
  `TaskSpot::Backend` class) — still fully name-distinct from stock.
- Widget migration via scripting mutates the live panel; mitigated by a
  fresh appletsrc backup immediately beforehand and by keeping the
  snippet idempotent (skip if no old-ID applets found).
- Any stale `~/.local` artifacts not covered above are swept by listing
  the install tree before/after deploy.

## As-built amendments (implementation, 2026-08-28)

Two spec assumptions failed empirically and were resolved as follows:

1. **Namespace-qualified QML names don't resolve through an import
   alias.** `TaskManagerApplet.TaskSpot.Backend` failed at runtime
   ("TaskSpot is not a type"): the QML engine resolves only
   single-segment type names behind an import alias, and the qmldir
   carries no C++ type entries to help it. The documented fallback was
   applied instead: distinct **unqualified** element names via
   `QML_NAMED_ELEMENT` — `TaskSpotBackend`, `TaskSpotFilterProxyModel`,
   `TaskSpotSmartLauncherItem` (the last because stock registers plain
   `SmartLauncherItem`; equal names would recreate the #10 condition).
   C++ types remain `TaskSpot::{...}`.
2. **The applet needs a real plasmoid package.** The embedded-QML load
   path (`Applet::qrcPath()`, libplasma applet.cpp) derives its qrc root
   from the dashed plugin id — `:/qt/qml/plasma/applet/com/stack-tech/…`
   — which can never reach the underscored module URI
   (`…/com/stack_tech/…`). Without a package, loading failed ("package
   does not exist"). Resolution: TaskSpot ships a normal applet package
   (`src/packages/com.stack-tech.plasma.taskspot/`): package metadata +
   `contents/ui/*.qml` + `contents/config/main.xml`, all installed from
   the single-copy vendored sources (nothing duplicated in git). The
   compiled module keeps only the C++ types and the TaskTools/
   LayoutMetrics JS libraries (accessed through the import alias). The
   `X-Plasma-RootPath` trick remains retired — this is the ordinary,
   distributable KPackage + C++ applet shape.
   - Consequence: QML files that relied on the qrc directory's implicit
     qmldir import needed an explicit module import (ToolTipDelegate.qml).

