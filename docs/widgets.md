---
summary: "WidgetKit snapshot pipeline + visibility troubleshooting for CodexBar widgets."
read_when:
  - Modifying WidgetKit extension behavior or snapshot format
  - Debugging widget update timing
  - Widget gallery shows no CodexBar widgets
---

# Widgets

## Snapshot pipeline
- `WidgetSnapshotStore` writes compact JSON snapshots to the app-group container.
- Widgets read the snapshot and render usage/credits/history states.
- Codex dashboard snapshots carry the OpenAI subscription renewal timestamp when the page exposes it; the menu renders
  that date below Codex token-cost lines.
- Provider extra-usage snapshots include their renewal metadata so medium, large, switcher, and history widgets can show
  a muted line such as `Monthly · renews in 6 days` under the related cost value when a renewal date is known.
- OpenCode snapshots can now contain multiple saved workspace entries for the same provider.
- Cursor legacy-plan snapshots can include recent request details with the usage range, model, time, tokens, raw
  request count, and optional dashboard-weighted request cost. WidgetKit renders a bounded subset with `+N more`
  instead of a scrollable table.
- `WidgetSnapshot.CursorRequestDetail` also carries optional `compactModel` (e.g. `Opus 4.8 · xhigh` or
  `GPT-5.5 · extra-high`) and `estimateText` (e.g. `Est. $12.34` or `Approx. $5.00+`). Both are optional, so
  older snapshot JSON without them still decodes; non-Cursor providers never gain these fields.
- Cursor request rows survive into the snapshot when they have at least one request, even with zero tokens; rows with no
  model or with neither tokens nor requests are dropped.
- Cursor medium/large widgets can show billing-cycle token totals (`Cycle`) plus a bounded list of recent request rows
  for legacy request-plan accounts. The widget mirrors the Cursor token range selected in the menu (`Cycle` by default,
  or `30d` for the rolling 30-day view), including the token total, date range, total estimate, and stored request rows.
  The cycle/30-day row includes a summed local request estimate when priced breakdowns are
  available (`Est. $X` via `sessionCostUSD`) or an approximate range (`Approx. $low-$high` via `sessionCostText`) when
  any stored row is total-only for Composer or Anthropic, or a one-sided lower bound (`Approx. $low+`) when Cursor only
  exposes a total or incomplete GPT split. WidgetKit never shows approximate ranges as exact numeric costs. Each
  request row renders the compact model label, local time, dashboard-weighted `Req N` when Cursor provides
  `requestsCosts` (otherwise the raw event count), token spend, and the optional estimate (`Est.` or `Approx.` - only
  when available; unknown models never show a fabricated dollar value).
  WidgetKit has no hover or row expansion; expanded per-request detail is available in the macOS menu only. Up to 30 rows
  are stored in the snapshot; the widget renders the newest subset with a `+N more` line when additional rows exist.
- `WidgetSnapshot.TokenUsageSummary.sessionCostText` is an optional display override for approximate cycle totals,
  including one-sided lower bounds for incomplete GPT totals. Older snapshots without the field still decode and render
  from `sessionCostUSD` alone.

## Extension
- `Sources/CodexBarWidget` contains timeline + views.
- Keep data shape in sync with `WidgetSnapshot` in the main app.
- When the selected provider is OpenCode and multiple saved workspaces exist, the switcher widget exposes a workspace
  chip row so you can flip between workspace balances without reopening the app.

## Visibility troubleshooting (macOS 14+)
When widgets do not appear in the gallery at all, the issue is almost always
registration, signing, or daemon caching (not SwiftUI code).

### 1) Verify the extension bundle exists where macOS expects it
```
APP="/Applications/CodexBar.app"
WAPPEX="$APP/Contents/PlugIns/CodexBarWidget.appex"

ls -la "$WAPPEX" "$WAPPEX/Contents" "$WAPPEX/Contents/MacOS"
```

### 2) PlugInKit registration (pkd)
```
pluginkit -m -p com.apple.widgetkit-extension -v | grep -i codexbar || true
pluginkit -m -p com.apple.widgetkit-extension -i com.steipete.codexbar.widget -vv
```
Notes:
- `+` = elected to use, `-` = ignored (PlugInKit elections).
- If missing or ignored, force-add and re-elect:
```
pluginkit -a "$WAPPEX"
pluginkit -e use -p com.apple.widgetkit-extension -i com.steipete.codexbar.widget
```
- Check for duplicates (old installs or version precedence):
```
pluginkit -m -D -p com.apple.widgetkit-extension -i com.steipete.codexbar.widget -vv
```
If multiple paths appear, delete older installs and bump `CFBundleVersion`.

### 3) Code signing + Gatekeeper assessment
Widgets are loaded by system daemons. Any signing failure can hide the widget.
```
codesign --verify --deep --strict --verbose=4 /Applications/CodexBar.app
codesign --verify --strict --verbose=4 "$WAPPEX"
codesign --verify --strict --verbose=4 "$WAPPEX/Contents/MacOS/CodexBarWidget"
spctl --assess --type execute --verbose=4 /Applications/CodexBar.app
```

### 4) Restart the right daemons (NotificationCenter alone is not enough)
```
killall -9 pkd || true
sudo killall -9 chronod || true
killall Dock NotificationCenter || true
```

### 5) Watch logs while opening the widget gallery
```
log stream --style compact --predicate '(process == "pkd" OR process == "chronod" OR subsystem CONTAINS "PlugInKit" OR subsystem CONTAINS "WidgetKit")'
```

### 6) Packaging sanity checks
- Widget bundle id should be `com.steipete.codexbar.widget`.
- `NSExtensionPointIdentifier` must be `com.apple.widgetkit-extension`.
- Bundle folder name should match: `CodexBarWidget.appex`.

Optional: re-seed LaunchServices (rarely helps, but low risk):
```
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -seed
```

## Common post-visibility issue: stale data
If the widget appears but always shows preview data:
- App writes snapshot to fallback path while widget reads app-group container.
- Validate that both app and widget resolve the same app-group container.

See also: `docs/ui.md`, `docs/packaging.md`.
