# AGENTS.md — TaskSpot

Rules in this file are standing project rules. They apply to every agent
(human or AI) and every future development session on this repository.

## Project identity

TaskSpot enhances KDE Plasma 6 / Wayland's default taskbar grouped-window
hover popup ("group dialog") with live search: typing while the popup is
open filters window cards by title, and matching browser tabs (via Plasma
Browser Integration) appear as individual results that activate the right
browser window and switch directly to that tab.

Key architecture facts (verified — see `docs/` for the design history):

- The stock task manager's QML, including `GroupDialog.qml`, is compiled
  into `org.kde.plasma.taskmanager.so`. TaskSpot builds a patched copy of
  that same plugin ID and installs it user-locally
  (`~/.local/lib/plugins/plasma/applets/`), which shadows the system
  plugin because plasmashell's `QT_PLUGIN_PATH` lists user-local plugin
  directories first. Uninstalling TaskSpot's file restores stock behavior.
- Browser tab data comes from the existing Plasma Browser Integration
  DBus API (`org.kde.plasma.browser_integration*` bus names,
  `/TabsRunner`, interface `org.kde.plasma.krunner1`: `Match(query)`,
  `Run(tabId, "")`, `Teardown()`). TaskSpot does not ship its own browser
  extension or native messaging host.
- Vendored code under `src/vendor/` derives from plasma-desktop
  (GPL-2.0-or-later). Keep provenance headers intact and keep TaskSpot
  modifications reviewable as a readable patch series against upstream.

## Issue-driven development history (standing rule)

Use GitHub Issues as the running development history for this project,
including work performed locally.

- Before beginning a meaningful feature, bug fix, investigation,
  refactor, or other significant task, create an issue describing the
  work and expected outcome.
- Keep issues updated with useful discoveries, implementation decisions,
  blockers, test results, and changes in direction when appropriate.
- Reference the relevant issue in commits and pull requests.
- Close issues when the associated work is completed and verified,
  preferably using GitHub's automatic closing syntax where appropriate.
- If new work is discovered while implementing something, create a
  separate issue rather than allowing unrelated work to disappear into
  commits or conversation history.
- Do not create issues for trivial mechanical actions that would only
  add noise.
- Use descriptive commits and preserve a clean, useful Git history.
- Push work to the public repository regularly so GitHub remains an
  accurate historical record of the project, not merely a release
  destination.
- Record important architectural or project-wide decisions in the
  repository when they would otherwise exist only in agent conversations.

## Development workflow

- **Before changing any QML under `src/vendor/taskmanager/qml/`, read
  `docs/TROUBLESHOOTING.md`** and follow its mandatory verification
  protocol. A build that succeeds proves nothing about a lazily-created
  component: `SearchPopup.qml` is only instantiated on hover, so a fatal
  error in it is invisible to `cmake --build`, to `qmllint`, and to a
  `plasmoidviewer` smoke run. Hovering a grouped task and reading the
  journal is the only gate that sees it.

- Build: `cmake -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$HOME/.local`
  then `cmake --build build && cmake --install build`.
- Test without touching the running shell:
  `plasmoidviewer -a org.kde.plasma.icontasks` (loads the shadowed plugin;
  QML console output goes to `journalctl --user`, not stderr).
- Reload plasmashell only when necessary and carefully
  (`systemctl --user restart plasma-plasmashell.service`); never leave the
  session unusable.
- Do not modify anything under `/home/josephur/dev/kde-reference/` — it is
  a read-only reference checkout of upstream KDE repositories.
- When syncing vendored code from a newer plasma-desktop release, do it as
  its own documented commit/issue so upstream changes stay distinguishable
  from TaskSpot changes.
