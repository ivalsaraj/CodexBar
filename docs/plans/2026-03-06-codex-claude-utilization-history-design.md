# Codex + Claude Utilization History Design

## Goal

Add a new utilization history line chart for `codex` and `claude`, sourced from successful provider snapshots, and show it above the existing 30-day cost history bar chart inside the current `Usage history (30 days)` menu experience.

## Approved Scope

- Support `codex` and `claude` only.
- Record utilization history from any successful, reliable provider refresh that yields real `UsageSnapshot` window percentages.
- Keep the existing lower cost chart unchanged.
- Add a new upper path/line chart with its own segmented range control: `1h`, `6h`, `1d`, `7d`, `30d`.
- Keep the range control scoped to the new utilization chart only.
- Stack the new chart above the existing cost chart with a divider between them.

## Why This Fits The Existing Architecture

`UsageStore` already owns normalized provider snapshots and drives menu refreshes. That makes it the right place to capture utilization history after successful refreshes, instead of introducing a second polling or auth pipeline.

The existing menu system already supports hosted SwiftUI chart views inside `NSMenu` submenus. The new work should reuse that hosting pattern and `MouseLocationReader` hover interaction instead of adding a new menu surface or standalone window.

## Data Model

Add a small shared history model for provider utilization points:

- `provider`
- `timestamp`
- `primaryUsedPercent`
- `secondaryUsedPercent`

This is intentionally separate from token cost history:

- utilization history is sampled snapshot data over variable time ranges
- cost history is existing daily aggregate data over a fixed 30-day range

The store should:

- persist per-provider history locally
- prune data older than 30 days
- support downsampling by requested display range
- tolerate missing secondary data without inventing zeros

## Recording Rules

Record a point only when:

- the provider is `codex` or `claude`
- a refresh succeeds
- the snapshot contains a valid primary usage window

Secondary usage should be recorded when present. If it is missing, preserve that as missing data rather than converting to `0`.

To avoid pointless churn, the recorder may skip appending a point when the latest stored point is effectively identical and very recent.

## UI Design

Inside the existing `Usage history (30 days)` submenu for `codex` and `claude`:

1. show the new utilization line chart first
2. show a divider
3. show the existing cost history bar chart unchanged

The new chart should:

- use a segmented control for `1h`, `6h`, `1d`, `7d`, `30d`
- render two lines when both windows are available
- render a single line when only the primary window is available
- support hover inspection using the menu-safe mouse tracking pattern already used elsewhere

The lower cost chart should remain 30-day-only and should not react to the new segmented control.

## Provider Behavior

`claude`
- use the existing primary/secondary usage windows from `UsageSnapshot`
- works regardless of whether data came from OAuth, CLI, or web, as long as the snapshot was successful

`codex`
- use the same normalized snapshot windows already shown in the menu bar/menu card
- share the same history and chart infrastructure as Claude

Other providers
- no behavior change
- keep their current cost-history-only behavior, if any

## Testing Strategy

Add focused tests for:

- history recording and pruning
- downsampling across each supported range
- preserving missing secondary values
- provider filtering so only `codex` and `claude` record/display utilization history
- menu composition so `codex` and `claude` get the stacked chart view while other providers keep current behavior

## Risks To Manage

- accidental coupling between the new utilization range picker and the existing cost chart
- writing `0` for missing weekly data and creating misleading lines
- showing the new chart for providers without persisted utilization history
- introducing UI regressions in hosted submenu sizing or hover handling

## Decision Summary

Build a shared `codex`/`claude` utilization history pipeline in `UsageStore`, render it as a new chart type above the existing cost chart, and keep the existing cost chart logic and timeframe unchanged.
