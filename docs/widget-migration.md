# Migrating to the standalone TaskSpot widget (#18)

As of #18, TaskSpot is its own applet: **`com.stack-tech.plasma.taskspot`**.
It no longer shadows the system task-manager plugin, and the old
`org.kde.taskspot` package (which borrowed the compiled plugin via
`X-Plasma-RootPath`) is retired.

## Upgrading from the shadowed build

Remove the old artifacts (with plasmashell stopped, e.g.
`systemctl --user stop plasma-plasmashell.service`):

```bash
rm ~/.local/lib/plugins/plasma/applets/org.kde.plasma.taskmanager.so
rm -f ~/.local/lib/plugins/plasma/applets/*.taskspot-disabled
rm -rf ~/.local/share/plasma/plasmoids/org.kde.taskspot
```

Removing the shadowed `org.kde.plasma.taskmanager.so` instantly restores
pristine upstream behavior for all stock task-manager widgets.

## Moving your panel widgets

Old `org.kde.taskspot` widgets keep their configuration only if the
applet keeps its UUID in Plasma's config. Two routes:

### Route A — keep config (one restart, used by this repo's deploy)

1. Back up the config:
   `cp ~/.config/plasma-org.kde.plasma.desktop-appletsrc{,.bak}`
2. Stop plasmashell.
3. Rewrite the plugin line — the applet UUID and all of its config groups
   are preserved, only the plugin id changes:
   `sed -i 's/^plugin=org\.kde\.taskspot$/plugin=com.stack-tech.plasma.taskspot/' ~/.config/plasma-org.kde.plasma.desktop-appletsrc`
4. Start plasmashell. The widget reappears with launchers, grouping,
   sorting and TaskSpot search settings intact.

### Route B — manual re-add

Back up the config, remove the old widget from the panel, add the widget
named **TaskSpot** from the widget explorer, and re-apply per-widget
settings (Behavior page: launchers, grouping, sorting, search toggles).
The new applet gets a new UUID, so config does not carry over
automatically.

## Uninstalling TaskSpot entirely

Remove the widgets from your panel, then:

```bash
rm ~/.local/lib/plugins/plasma/applets/com.stack-tech.plasma.taskspot.so
rm -rf ~/.local/share/plasma/plasmoids/com.stack-tech.plasma.taskspot
```
