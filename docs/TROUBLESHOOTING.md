# TaskSpot debugging notes

Lessons from the #11/#12 sessions. Read this before changing
`SearchPopup.qml`, `ToolTipDelegate.qml`, or `filtermodel.{h,cpp}`.

## The one rule

**Any QML error inside a lazily-created component is fatal for the whole
component.** `createObject()` returns null and the only trace is one line
in the journal. The popup "not appearing at all" has always been a single
bad property or a throw in `Component.onCompleted`.

### Verification protocol (mandatory after every QML/model change)

1. `cmake --build build 2>&1 | tail -3` — confirm `[100%] Built target`,
   never pipe the build through a filter that hides failures, and never
   let `install`/`restart` run after a failed build (use `&&`).
2. `cmake --install build && systemctl --user restart
   plasma-plasmashell.service`
3. Hover a grouped task, then immediately:
   `journalctl --user -u plasma-plasmashell.service --since "-1 min" |
   grep -aE "TaskSpot|ReferenceError|TypeError|is not a function"`
4. Only report success to the human after step 3 is clean.

## Failure taxonomy (all observed)

| Symptom | Root cause | Fix |
|---------|-----------|-----|
| Popup never appears; journal: `Cannot assign to non-existent property "X"` | One bad property aborts component instantiation | Check the property exists in *this* Qt/Plasma version. `hoverEnabled` is not on Items or window-level handlers; `takesFocus` not on PopupPlasmaWindow in 6.7.4 |
| Popup never appears; journal: `TypeError ... of undefined` in `Component.onCompleted` | A throw aborts completion before `visible = true` | Null-guard everything read from attached/context objects (`Plasmoid.screenGeometry` does not exist in 6.7.4) |
| Popup renders but zero cards | The filter proxy resolved no rows | `groupRow`/`sourceModel` binding order, or the group re-location failed — see filtermodel.cpp rebuild() |
| Card titles render `undefined` | `model.display` undefined at render time while the filter's direct source read worked — the proxy's group index was invalidated by model churn between filter and render | Group is located by **AppId** (stable identity), never by re-reading the stale int row |
| Generic app icons instead of live thumbnails | `pipeWireLoader.active` false, or KWin/PipeWire stream pipeline broken | Check `journalctl --user -b | grep "can't create node"` — PipeWire fd exhaustion (soft limit 1024) kills thumbnails *system-wide* until pipewire restart + KWin reconnect (relogin) |
| Binding loop on window `width` | Deriving window size from content that depends on the window size | Window sizing is imperative (`updateSize()`), one-way from implicit sizes, mirroring `ToolTipDialog::updateSize()` |
| Clicking a grouped task does nothing | A throw in `updateMainItemBindings()` aborts `activateTask()`'s previews branch | `Geometry` role can be undefined — always `?.`-guard it |

## Environment gotchas

- `PlasmoidItem.screenGeometry` does not exist in Plasma 6.7.4 (added in
  6.7.5). The panel's monitor is passed from `Task.qml`'s scope, where the
  `Screen` attached property resolves to the panel's real output.
- The `Screen` attached property inside the popup resolves against the
  whole virtual desktop (6435px here) before first show — never use it
  for clamping.
- `Q_INVOKABLE` methods on `TaskFilterProxyModel` were observed invisible
  to the QML engine while properties kept working — expose functionality
  as properties (`groupRow`, `sourceRows`).
- `QAbstractProxyModel::data()` must not be relied on for forwarding;
  forward explicitly via `mapToSource`.
- The tasks model re-sorts rows on activation changes: an int row captured
  at popup creation is stale within seconds. `QPersistentModelIndex`
  tracks until invalidated; the AppId re-location in `rebuild()` is the
  durable answer.
- `plasmoidviewer` QML output goes to `journalctl --user`, not stderr.
- `pkill -f plasmoidviewer` matches your own shell's command line.
