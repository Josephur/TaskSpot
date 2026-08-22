# TaskSpot

Live search for KDE Plasma 6's default taskbar grouped-windows popup.

Hover an app icon in the taskbar and the group dialog lists that app's
windows. With TaskSpot, just start typing: the list filters by window
title instantly, and for browsers it also searches **open tab titles**
(Chrome/Chromium/Firefox, via the existing Plasma Browser Integration).
Click a result to focus the window — or to jump straight to that tab in
the right browser window.

- No new browser extension: TaskSpot consumes the DBus API that Plasma
  Browser Integration already ships (`org.kde.plasma.browser_integration`,
  `/TabsRunner`).
- No system file modification: TaskSpot installs a user-local build of the
  task manager plugin (same plugin ID) that shadows the system one;
  deleting it restores stock behavior.

Status: work in progress — see the issue tracker for the running
development history and `docs/superpowers/specs/` for design documents.

## Requirements

- Plasma 6 (developed against 6.7.x) on Wayland
- plasma-workspace (provides the task manager plugin being shadowed)
- For browser-tab search: `plasma-browser-integration` package plus the
  "Plasma Integration" browser extension (Firefox: AMO; Chrome-family:
  Web Store)

## Build

```sh
cmake -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$HOME/.local
cmake --build build
cmake --install build
```

## License

GPL-2.0-or-later. Contains code vendored from plasma-desktop
(`src/vendor/taskmanager`), copyright KDE contributors.
