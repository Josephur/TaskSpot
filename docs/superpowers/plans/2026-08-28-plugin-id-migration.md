# Plugin-ID Migration Implementation Plan (#18)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild TaskSpot as its own compiled applet (`com.stack-tech.plasma.taskspot`) instead of shadowing `org.kde.plasma.taskmanager.so`, retire the `org.kde.taskspot` package sibling, and migrate the user's panel.

**Architecture:** Three commits in order: (1) wrap all vendored C++ QML types in `namespace TaskSpot` so no type name collides with the stock plugin (#10), (2) swap target/URI/metadata to the new ID and delete the sibling package, (3) document migration. Then deploy: install new plugin, remove old artifacts, rewrite the panel widget's plugin line in the appletsrc with the shell stopped, restart, verify.

**Tech Stack:** CMake + ECM (`ecm_add_qml_module`), Qt6/QML, KPlugin metadata JSON, systemd user unit (`plasma-plasmashell.service`), Plasma scripting console for verification.

**Spec:** `docs/superpowers/specs/2026-08-28-plugin-id-migration-design.md` — the plan argues from the spec; executors read both.

## Global Constraints

- Approved public ID, verbatim: `com.stack-tech.plasma.taskspot` (dash). Used for: CMake target, `.so` filename, `Id` in metadata.json, `TRANSLATION_DOMAIN`/pot name, logging category, `Plasmoid.pluginName` checks.
- QML module URI, verbatim: `plasma.applet.com.stack_tech.plasma.taskspot` (underscore — dashes are illegal in QML import URIs). Used only in `import` statements and the `ecm_add_qml_module` call.
- Generated plugin class name: `com_stack_tech_plasma_taskspot_Plugin`.
- QML-visible C++ type names after Task 1: `TaskSpot.Backend`, `TaskSpot.TaskFilterProxyModel`, `TaskSpot.SmartLauncher.*` (via `TaskManagerApplet.TaskSpot.…` after import aliasing).
- Import alias stays `TaskManagerApplet` in all 8 QML files (minimizes upstream-sync diff).
- `/home/josephur/dev/kde-reference/` is read-only — never touched.
- QML console output goes to `journalctl --user`, not stderr.
- Never leave the session unusable; back up `plasma-org.kde.plasma.desktop-appletsrc` before any mutation.

**Test strategy note:** this repo has no unit-test framework. For a rename/migration the equivalent gates are: (a) a clean Release build — `qmlcachegen` compiles every QML source, so a bad import URI, unresolvable qualified type name, or type-registration failure fails the build; (b) inspection of generated `qmldir`/`.qmltypes`; (c) a `plasmoidviewer` smoke run with journal assertions; (d) post-restart journal + scripting verification. Hover/drag behaviors are manual-only on Wayland (user tests at the end).

---

### Task 1: Mechanical type rename — `namespace TaskSpot`

**Files:**
- Modify: `src/vendor/taskmanager/backend.h`, `backend.cpp`, `filtermodel.h`, `filtermodel.cpp`, `smartlauncherbackend.h`, `smartlauncherbackend.cpp`, `smartlauncheritem.h`, `smartlauncheritem.cpp`
- Modify (QML type references): `src/vendor/taskmanager/qml/ContextMenu.qml`, `GroupDialog.qml`, `SearchPopup.qml`, `main.qml` (only lines referencing `TaskManagerApplet.Backend` / `TaskManagerApplet.TaskFilterProxyModel`)

**Interfaces:**
- Produces: QML types `TaskManagerApplet.TaskSpot.Backend`, `TaskManagerApplet.TaskSpot.TaskFilterProxyModel` (used by Task 2's QML); C++ classes `TaskSpot::Backend`, `TaskSpot::TaskFilterProxyModel`, `TaskSpot::SmartLauncher::Backend`, `TaskSpot::SmartLauncher::Item` (no C++ consumers outside this directory).

- [ ] **Step 1: Wrap `Backend` in `namespace TaskSpot` (header + source)**

In `backend.h`, replace:

```cpp
class Backend : public QObject
{
```

with:

```cpp
namespace TaskSpot
{
class Backend : public QObject
{
```

and after the class's closing `};` (before `Q_DECLARE`-style trailing code if any, else at the point immediately following the class body) add:

```cpp
} // namespace TaskSpot
```

In `backend.cpp`, immediately before the first definition (`Backend::Backend(QObject *parent)`) insert:

```cpp
namespace TaskSpot
{
```

and at end of file append:

```cpp
} // namespace TaskSpot
```

(Verified: no `.moc"` includes in any `src/vendor/taskmanager/*.cpp`, so wrapping the whole definition area is safe. Nested `namespace NotificationManager { }` blocks inside `backend.cpp`, if any, may stay inside the wrap — harmless.)

- [ ] **Step 2: Wrap `TaskFilterProxyModel` the same way**

`filtermodel.h`: open `namespace TaskSpot {` around `class TaskFilterProxyModel : public QAbstractProxyModel` (closing `} // namespace TaskSpot` after the class). `filtermodel.cpp`: wrap all definitions from `TaskFilterProxyModel::TaskFilterProxyModel(...)` to end of file the same way as Step 1.

- [ ] **Step 3: Rename the SmartLauncher namespace**

In `smartlauncherbackend.h` and `smartlauncheritem.h`, change both the opening and closing lines:

```cpp
namespace SmartLauncher
```
→
```cpp
namespace TaskSpot::SmartLauncher
```
and
```cpp
} // namespace SmartLauncher
```
→
```cpp
} // namespace TaskSpot::SmartLauncher
```

In `smartlauncherbackend.cpp` and `smartlauncheritem.cpp`, change:

```cpp
using namespace SmartLauncher;
```
→
```cpp
using namespace TaskSpot::SmartLauncher;
```

Do **not** touch `QML_NAMED_ELEMENT(SmartLauncherItem)` — it stays; qmltyperegistrar nests it under the enclosing namespaces automatically.

- [ ] **Step 4: Update the ~10 QML type references**

```bash
cd /home/josephur/dev/TaskSpot/src/vendor/taskmanager/qml
sed -i 's/TaskManagerApplet\.Backend/TaskManagerApplet.TaskSpot.Backend/g; s/TaskManagerApplet\.TaskFilterProxyModel/TaskManagerApplet.TaskSpot.TaskFilterProxyModel/g' ContextMenu.qml GroupDialog.qml SearchPopup.qml main.qml Task.qml TaskList.qml MouseHandler.qml TaskProgressOverlay.qml
```

Verification before running: `grep -rn "TaskManagerApplet\.\(Backend\|TaskFilterProxyModel\)" .` lists the expected sites (`ContextMenu.qml` 4, `GroupDialog.qml` 2, `SearchPopup.qml` 1, plus `required property` annotations wherever they appear — all `TaskManagerApplet.LayoutMetrics.*` and `TaskManagerApplet.TaskTools.*` references must remain untouched). After: the same grep returns nothing.

- [ ] **Step 5: Build and verify type registration**

```bash
cmake --build /home/josephur/dev/TaskSpot/build 2>&1 | tail -5
grep -o "TaskSpot\.[A-Za-z.]*" build/src/vendor/taskmanager/org.kde.plasma.taskmanager.qmltypes | sort -u
```

Expected: build succeeds; qmltypes contains `TaskSpot.Backend` and `TaskSpot.TaskFilterProxyModel` (module is still the old URI/id at this point — that's intentional; the ID swap is Task 2).

- [ ] **Step 6: Smoke-run in plasmoidviewer**

```bash
plasmoidviewer -a org.kde.plasma.icontasks >/dev/null 2>&1 &
sleep 8; journalctl --user --since "-2 min" | grep -iE "taskmanager|TaskSpot|error" | tail -20; kill %1
```

Expected: no `Could not set initial property backend`, no TypeError about `backend`. (Startup noise about unrelated applets is fine.)

- [ ] **Step 7: Commit**

```bash
git add -A src/vendor/taskmanager
git commit -m "Rename vendored C++ QML types into TaskSpot namespace (#18)

Mechanical rename required by #10's finding: with stock
org.kde.plasma.taskmanager.so loaded in the same plasmashell process,
identical type-name sets cross-wire QML type resolution even under
different module URIs. Backend and TaskFilterProxyModel become
TaskSpot::{...}; SmartLauncher:: becomes TaskSpot::SmartLauncher::.
QML-visible names gain the TaskSpot. namespace segment; the
TaskManagerApplet import alias is kept so upstream syncs stay a
readable patch series."
```

---

### Task 2: Identity swap — target, URI, metadata, retire sibling

**Files:**
- Modify: `src/vendor/taskmanager/CMakeLists.txt` (full rewrite below), `src/vendor/taskmanager/metadata.json` (full rewrite below), `src/vendor/taskmanager/Messages.sh`, root `CMakeLists.txt`
- Modify (import lines + ID checks): the 8 QML files, `qml/ConfigBehavior.qml`, `qml/main.qml`
- Delete: `src/packages/` (whole directory)

**Interfaces:**
- Consumes: Task 1's `TaskSpot.`-prefixed QML type names.
- Produces: installed `com.stack-tech.plasma.taskspot.so` (consumed by Task 4); applet ID `com.stack-tech.plasma.taskspot` (consumed by Task 4's appletsrc rewrite).

- [ ] **Step 1: Rewrite `src/vendor/taskmanager/CMakeLists.txt` with this exact content:**

```cmake
# SPDX-License-Identifier: GPL-2.0-or-later
# Vendored from plasma-desktop applets/taskmanager (KDE), Plasma 6.7.5
# Modified by TaskSpot - see repository history for the patch series.
#
# The target below replicates plasma_add_applet()
# (/usr/lib/cmake/Plasma/PlasmaMacros.cmake, GENERATE_APPLET_CLASS branch)
# with one delta: the macro derives the QML module URI from the target id
# (plasma.applet.${id}), and the approved applet id contains a dash, which
# a QML module URI cannot express (every dot-separated URI segment must be
# a valid JS identifier). The URI therefore uses an underscore spelling
# while the target, .so name and metadata keep the approved id verbatim.
# See #18 and docs/superpowers/specs/2026-08-28-plugin-id-migration-design.md.

add_definitions(-DTRANSLATION_DOMAIN=\"plasma_applet_com.stack-tech.plasma.taskspot\")

set(TASKSPOT_ID com.stack-tech.plasma.taskspot)
set(TASKSPOT_URI plasma.applet.com.stack_tech.plasma.taskspot)

add_library(${TASKSPOT_ID} SHARED)

set_target_properties(${TASKSPOT_ID} PROPERTIES PREFIX "")

include(ECMQmlModule)
ecm_add_qml_module(${TASKSPOT_ID} URI ${TASKSPOT_URI} QT_NO_PLUGIN)

ecm_target_qml_sources(${TASKSPOT_ID}
    SOURCES
        qml/AudioStream.qml
        qml/ConfigAppearance.qml
        qml/ConfigBehavior.qml
        qml/config.qml
        qml/ContextMenu.qml
        qml/GroupDialog.qml
        qml/GroupExpanderOverlay.qml
        qml/main.qml
        qml/MouseHandler.qml
        qml/PipeWireThumbnail.qml
        qml/PlayerController.qml
        qml/PulseAudio.qml
        qml/ScrollableTextWrapper.qml
        qml/SearchPopup.qml
        qml/TaskBadgeOverlay.qml
        qml/TaskList.qml
        qml/TaskProgressOverlay.qml
        qml/Task.qml
        qml/ToolTipDelegate.qml
        qml/ToolTipInstance.qml
        qml/ToolTipWindowMouseArea.qml
        qml/code/LayoutMetrics.js
        qml/code/TaskTools.js
    RESOURCES
        main.xml
)

set_target_properties(${TASKSPOT_ID} PROPERTIES LIBRARY_OUTPUT_DIRECTORY "${CMAKE_LIBRARY_OUTPUT_DIRECTORY}/plasma/applets")

# Generated applet class, exactly as plasma_add_applet(GENERATE_APPLET_CLASS)
# would emit for this id.
file(GENERATE OUTPUT ${TASKSPOT_ID}.cpp CONTENT "\
#include <KPluginFactory>
#include <Plasma/Applet>

class com_stack_tech_plasma_taskspot_Plugin : public Plasma::Applet {
   Q_OBJECT
public:
   com_stack_tech_plasma_taskspot_Plugin(QObject *parent, const KPluginMetaData &data, const QVariantList &args)
      : Plasma::Applet(parent, data, args) {}
};

K_PLUGIN_CLASS_WITH_JSON(com_stack_tech_plasma_taskspot_Plugin, \"metadata.json\")

#include \"com.stack-tech.plasma.taskspot.moc\"
")

target_sources(${TASKSPOT_ID} PRIVATE ${TASKSPOT_ID}.cpp)

kconfig_add_kcfg_files(${TASKSPOT_ID} ${CMAKE_CURRENT_SOURCE_DIR}/kactivitymanagerd_plugins_settings.kcfgc)

ecm_qt_declare_logging_category(${TASKSPOT_ID}
    HEADER log_settings.h
    IDENTIFIER TASKSPOT_DEBUG
    CATEGORY_NAME com.stack-tech.plasma.taskspot)

# FIXME Cleanup no longer used libs.
target_link_libraries(${TASKSPOT_ID} PRIVATE
                      Qt::Core
                      Qt::Qml
                      Qt::Quick
                      Plasma::Activities
                      Plasma::ActivitiesStats
                      KF6::ConfigGui
                      KF6::CoreAddons # generated applet class (KPluginFactory)
                      KF6::I18n
                      KF6::KIOCore
                      KF6::KIOGui
                      KF6::KIOFileWidgets # KFilePlacesModel
                      KF6::Notifications # KNotificationJobUiDelegate
                      Plasma::Plasma # generated applet class
                      KSysGuard::ProcessCore
                      KF6::Service
                      KF6::WindowSystem
                      PW::LibNotificationManager)

install(TARGETS ${TASKSPOT_ID} DESTINATION ${KDE_INSTALL_PLUGINDIR}/plasma/applets)
```

- [ ] **Step 2: Rewrite `src/vendor/taskmanager/metadata.json` with this exact content:**

```json
{
    "KPlugin": {
        "Authors": [
            {
                "Name": "Josephur"
            }
        ],
        "BugReportUrl": "https://github.com/Josephur/TaskSpot/issues",
        "Category": "Windows and Tasks",
        "Description": "Task manager with live search over window titles and browser tabs",
        "EnabledByDefault": false,
        "Icon": "preferences-system-windows",
        "Id": "com.stack-tech.plasma.taskspot",
        "License": "GPL-2.0-or-later",
        "Name": "TaskSpot",
        "Website": "https://github.com/Josephur/TaskSpot"
    },
    "X-Plasma-API-Minimum-Version": "6.0",
    "X-Plasma-Provides": [
        "org.kde.plasma.multitasking"
    ]
}
```

(Upstream's translated author/description blocks are dropped deliberately: they describe upstream, not TaskSpot.)

- [ ] **Step 3: QML import lines and ID checks**

```bash
cd /home/josephur/dev/TaskSpot/src/vendor/taskmanager/qml
sed -i 's|import plasma.applet.org.kde.plasma.taskmanager as TaskManagerApplet|import plasma.applet.com.stack_tech.plasma.taskspot as TaskManagerApplet|' AudioStream.qml ConfigAppearance.qml ConfigBehavior.qml config.qml ContextMenu.qml GroupDialog.qml GroupExpanderOverlay.qml main.qml MouseHandler.qml PipeWireThumbnail.qml PlayerController.qml PulseAudio.qml ScrollableTextWrapper.qml SearchPopup.qml TaskBadgeOverlay.qml TaskList.qml TaskProgressOverlay.qml Task.qml ToolTipDelegate.qml ToolTipInstance.qml ToolTipWindowMouseArea.qml
sed -i 's|Plasmoid.pluginName === "org.kde.taskspot"|Plasmoid.pluginName === "com.stack-tech.plasma.taskspot"|g' ConfigBehavior.qml main.qml
grep -rn "org.kde.plasma.taskmanager\|org\.kde\.taskspot" .
```

The final grep must return only the `iconsOnly` icontasks line in `main.qml` (`Plasmoid.pluginName === "org.kde.plasma.icontasks"` — stays by design; it is always false for TaskSpot and keeps the upstream diff minimal). If any other line matches, fix it before continuing.

- [ ] **Step 4: Messages.sh + retire the sibling package**

`src/vendor/taskmanager/Messages.sh` becomes:

```bash
#! /usr/bin/env bash
$XGETTEXT `find . -name \*.js -o -name \*.qml -o -name \*.cpp` -o $podir/plasma_applet_com.stack-tech.plasma.taskspot.pot
```

Root `CMakeLists.txt`: delete the line `add_subdirectory(src/packages)`. Then `git rm -r src/packages` (removes the `org.kde.taskspot` metadata-only package and its install rule — the `X-Plasma-RootPath` trick is retired; see `src/packages/CMakeLists.txt` history for the #10 context it carried).

- [ ] **Step 5: Clean rebuild + registration check**

```bash
cd /home/josephur/dev/TaskSpot
rm -rf build && cmake -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$HOME/.local && cmake --build build 2>&1 | tail -5
ls build/bin/plasma/applets/  # expect: com.stack-tech.plasma.taskspot.so (only)
grep -E "module|TaskSpot\." build/bin/plasma/applet/com/stack_tech/plasma/taskspot/qmldir | head
```

Expected: clean build (qmlcachegen validates every import URI and qualified type annotation); `.so` named with dashes; `qmldir` shows `module plasma.applet.com.stack_tech.plasma.taskspot` and the `.qmltypes` lists `TaskSpot.Backend` / `TaskSpot.TaskFilterProxyModel`.

- [ ] **Step 6: Staged-install layout check**

```bash
rm -rf /tmp/ts-stage && DESTDIR=/tmp/ts-stage cmake --install build
find /tmp/ts-stage -type f | sort
```

Expected: exactly one file — `tmp/ts-stage/lib64/plugins/plasma/applets/com.stack-tech.plasma.taskspot.so` (lib64 vs lib per distro). No plasmoids dir, no stray files.

- [ ] **Step 7: Smoke-run the new applet**

```bash
plasmoidviewer -a com.stack-tech.plasma.taskspot >/dev/null 2>&1 &
sleep 10; journalctl --user --since "-2 min" | grep -iE "stack_tech|stack-tech|taskspot|error" | tail -20; kill %1
```

Expected: the viewer loads the applet from the user-local install (run `cmake --install build` first if the applet is not found), no QML errors / TypeErrors in the journal.

- [ ] **Step 8: Commit + push**

```bash
git add -A
git commit -m "Build TaskSpot under its own plugin ID com.stack-tech.plasma.taskspot (#18)

TaskSpot stops shadowing org.kde.plasma.taskmanager.so: stock task
managers run pristine upstream code again and serve as a permanent
A/B control group, the #10 two-compiled-plugins collision becomes
structurally impossible, and the widget becomes distributable.

The CMake target replicates plasma_add_applet() with one delta: the
QML module URI is plasma.applet.com.stack_tech.plasma.taskspot
(underscore) because QML import URIs cannot contain the dash that the
approved public ID uses. The org.kde.taskspot package-only sibling and
its X-Plasma-RootPath trick are retired. Closes #18 (deploy +
manual verification to follow)."
git push
```

---

### Task 3: Migration documentation

**Files:**
- Create: `docs/widget-migration.md`
- Modify: `README.md` (the "No system file modification" bullet, ~line 15)

**Interfaces:**
- Produces: the user-facing migration guide referenced from the #18 closing comment.

- [ ] **Step 1: Write `docs/widget-migration.md`:**

Explain: panels that used the old `org.kde.taskspot` sibling (or anyone moving from the shadowed build) switch to the new `com.stack-tech.plasma.taskspot` widget. Include (a) the one-restart route used by this repo's own deploy — stop plasmashell, rewrite `plugin=org.kde.taskspot` → `plugin=com.stack-tech.plasma.taskspot` in `~/.config/plasma-org.kde.plasma.desktop-appletsrc` after backing it up, remove the old artifacts, start plasmashell — and (b) the manual route: back up the appletsrc, remove the old widget, add "TaskSpot" from the widget explorer, re-apply per-widget settings (launchers, grouping, sort), noting the applet UUID changes so config does not carry over automatically. Also list the artifacts to delete when upgrading from the shadowed build:
`~/.local/lib/plugins/plasma/applets/org.kde.plasma.taskmanager.so`, any `*.taskspot-disabled` files in the same directory, and `~/.local/share/plasma/plasmoids/org.kde.taskspot/`.

- [ ] **Step 2: Update the README bullet to:**

```markdown
- No system file modification: TaskSpot installs its own widget plugin
  (`com.stack-tech.plasma.taskspot`) user-locally; deleting it (and
  removing the widgets) restores a stock system.
```

- [ ] **Step 3: Commit + push**

```bash
git add docs/widget-migration.md README.md
git commit -m "Document widget migration and new uninstall story (#18)"
git push
```

---

### Task 4: Deploy (build is already installed from Task 2)

No commit. This task mutates the live session — every step has a check before the next.

- [ ] **Step 1: Pre-flight**

```bash
ls -la ~/.local/lib/plugins/plasma/applets/
cp ~/.config/plasma-org.kde.plasma.desktop-appletsrc ~/.config/plasma-org.kde.plasma.desktop-appletsrc.pre-taskspot18
grep -c "^plugin=org.kde.taskspot" ~/.config/plasma-org.kde.plasma.desktop-appletsrc
```

Expected: new `.so` present alongside the old shadowed one; backup created; old-ID widget count ≥ 1 recorded.

- [ ] **Step 2: Remove old artifacts with the shell stopped, migrate, restart**

```bash
systemctl --user stop plasma-plasmashell.service
rm ~/.local/lib/plugins/plasma/applets/org.kde.plasma.taskmanager.so
rm -f ~/.local/lib/plugins/plasma/applets/*.taskspot-disabled
rm -rf ~/.local/share/plasma/plasmoids/org.kde.taskspot
sed -i 's/^plugin=org\.kde\.taskspot$/plugin=com.stack-tech.plasma.taskspot/' ~/.config/plasma-org.kde.plasma.desktop-appletsrc
grep -c "^plugin=com.stack-tech.plasma.taskspot" ~/.config/plasma-org.kde.plasma.desktop-appletsrc
systemctl --user start plasma-plasmashell.service
```

Expected: sed replaced exactly the lines counted in Step 1 (verify count matches; if it does not match, restore the backup and stop — investigate before touching anything else). Old-ID count is now 0:

```bash
grep -c "^plugin=org.kde.taskspot" ~/.config/plasma-org.kde.plasma.desktop-appletsrc || echo 0
```

- [ ] **Step 3: Verify the live shell**

```bash
sleep 15
journalctl --user -u plasma-plasmashell.service --since "-2 min" | grep -iE "taskspot|taskmanager|error|cannot|unable" | head -30
qdbus org.kde.plasmashell /PlasmaShell evaluateScript 'for (const c of panels()) { for (const id of c.widgetIds) { const w = c.widgetById(id); if (w && String(w.type).indexOf("taskspot") !== -1) print("panel applet:", id, w.type); } }'
```

Expected: journal shows no TaskSpot/taskmanager errors; the scripting query prints the migrated applet with type `com.stack-tech.plasma.taskspot`.

- [ ] **Step 4: Report to the user for manual verification**

Hand over the manual checklist (Wayland hover input cannot be injected): hover a grouped task → search popup opens and takes typing; live filter narrows cards; Enter activates the first real result; per-widget settings (search toggles, launchers, grouping, sort) still applied; right-click context menu works; drag-reorder with Sort: Manually; a stock task-manager widget (if added) behaves normally alongside — the A/B control. On confirmation, close #18 with a summary comment; on failure, `superpowers:systematic-debugging` before any fix, restoring the appletsrc backup if the panel is broken.

---

## Self-Review

- **Spec coverage:** type rename (Task 1), identity swap + sibling retirement (Task 2), migration docs + README (Task 3), deploy/migration sequence + verification + manual handoff (Task 4). All spec sections map to tasks.
- **Placeholder scan:** no TBDs; every code step carries exact content or exact commands.
- **Type consistency:** `com.stack-tech.plasma.taskspot` (dashes) for target/.so/metadata/domain/logging/pluginName checks; `plasma.applet.com.stack_tech.plasma.taskspot` (underscores) only for imports/`ecm_add_qml_module`; `TaskManagerApplet.TaskSpot.Backend` / `TaskManagerApplet.TaskSpot.TaskFilterProxyModel` in QML — consistent with Task 1's sed outputs.
