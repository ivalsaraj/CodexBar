# Cursor Usage Range Switch Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a Cursor usage range switch for `30d` vs `Cycle`, defaulting to the billing-cycle view and applying consistently to the menu panel and widget snapshot.

**Architecture:** Preserve Cursor legacy-plan request quota as the cycle-backed primary metric while adding explicit range-scoped Cursor request metrics. Fetch the widest needed Cursor usage-events range once, then derive two local views: billing cycle and rolling 30 days. The menu model and widget snapshot should consume a selected range view, while display rows remain capped and scrollable exactly as they are today.

**Tech Stack:** Swift 6, SwiftPM, Swift Testing, SwiftUI menu views, WidgetKit snapshot model, existing `CursorStatusProbe`, `CursorRecentRequest`, `CursorRequestCostEstimator`, `UsageFormatter`, `UsageStore+WidgetSnapshot`.

---

## Product Contract

- Add a compact range switch on the right side of the `Tokens` heading for Cursor only.
- Switch options:
  - `30d`
  - `Cycle`
- Default selected option: `Cycle`.
- `Cycle` means Cursor's current billing-cycle range. For the current account this should naturally display a `17 -> 17` cycle because Cursor reports reset/start metadata around the 17th.
- `30d` means rolling last 30 days ending at the fetch time.
- The selected range controls:
  - total token line
  - estimated total cost line
  - request detail list
  - visible range label
  - request count shown in the token section
- Cursor legacy request quota remains request-based:
  - `Cycle` shows quota denominator when available, e.g. `Requests: 182 / 500`.
  - `30d` shows range request count without quota denominator, e.g. `Requests: 178`.
- The widget must use the same selected range as the menu.
- Do not add a new external dependency.
- Do not make another network call for every switch toggle. Fetch a wide-enough event set once and filter locally.
- Keep display rows capped at 30 in persisted widget snapshots and menu token section inputs; existing scroll behavior handles overflow presentation.

## Current Context

- `CursorStatusProbe.fetchUsageEvents` currently fetches usage events for the billing cycle start to now, paginated by `totalUsageEventsCount`.
- `CursorStatusProbe.parseUsageSummary` currently derives aggregate cycle tokens and cycle cost from all fetched event requests, while keeping recent display rows capped to 30.
- `UsageSnapshot` currently carries:
  - `cursorRequests`
  - `cursorTokenUsage`
  - `cursorRecentRequests`
  - `cursorRecentRequestRange`
- `MenuCardView.tokenUsageSection(input:)` currently builds one Cursor token section from `cursorTokenUsage` plus `cursorRecentRequests`.
- `UsageStore+WidgetSnapshot.widgetTokenUsageSummary` currently persists one Cursor token summary labeled `Cycle`.
- `WidgetSnapshot` currently carries one `cursorRequestRange` and one `cursorRequestDetails` list.

## Proposed Data Model

Add a small typed range model in `CodexBarCore`, for example:

```swift
public enum CursorUsageRangeKind: String, Codable, Sendable, CaseIterable {
    case last30Days
    case billingCycle
}

public struct CursorRangeUsageSummary: Codable, Sendable {
    public let rangeKind: CursorUsageRangeKind
    public let range: CursorRecentRequestRange
    public let tokens: Int
    public let requests: Int
    public let requestCostSummary: CursorRequestCostSummary?
    public let recentRequests: [CursorRecentRequest]
}
```

Add optional fields to `CursorTokenUsage` or `UsageSnapshot` so both range summaries are available to the menu and widget. Prefer this shape to duplicating loose fields:

```swift
public let cursorRangeSummaries: [CursorRangeUsageSummary]?
```

Do not store the selected range in `UsageSnapshot`. `UsageSnapshot` should carry available usage data only; `SettingsStore.cursorUsageRangeKind` is the canonical source of truth for the selected range.

## Proposed Settings Model

Persist the selected Cursor range in `SettingsStore` using app defaults:

```swift
var cursorUsageRangeKind: CursorUsageRangeKind
```

Default:

```swift
.billingCycle
```

This gives the menu and widget one source of truth. If settings plumbing is too broad, stage it behind the existing `SettingsStore` provider preference pattern rather than introducing a new global singleton. When this setting changes, trigger the existing widget snapshot persistence/reload path so the widget reflects the new range without waiting for the next provider network refresh.

---

## Task 0: Baseline And Scope Check

**Files:**
- Inspect: `Sources/CodexBarCore/Providers/Cursor/CursorStatusProbe.swift`
- Inspect: `Sources/CodexBarCore/Providers/Cursor/CursorTokenUsage.swift`
- Inspect: `Sources/CodexBarCore/UsageFetcher.swift`
- Inspect: `Sources/CodexBar/MenuCardView.swift`
- Inspect: `Sources/CodexBar/UsageStore+WidgetSnapshot.swift`
- Inspect: `Sources/CodexBarCore/WidgetSnapshot.swift`
- Inspect: `Tests/CodexBarTests/MenuCardCursorRequestDetailsTests.swift`
- Inspect: `Tests/CodexBarTests/CursorWidgetSnapshotTests.swift`

**Step 1: Confirm no unrelated files are dirty**

Run:

```bash
git status --short --branch
```

Expected: only known Cursor aggregate-token files and this plan are dirty. If unrelated user changes exist, do not stage or rewrite them.

**Step 2: Run focused baseline**

Run:

```bash
swift test --filter "CursorStatusProbeUsageSummaryTests|CursorWidgetSnapshotTests|MenuCardCursorRequestDetailsTests"
```

Expected: pass before adding range switching.

---

## Task 1: Add Range Summary Model And Filtering Tests

**Files:**
- Modify: `Sources/CodexBarCore/Providers/Cursor/CursorTokenUsage.swift`
- Modify or create: `Sources/CodexBarCore/Providers/Cursor/CursorRangeUsageSummary.swift`
- Modify: `Sources/CodexBarCore/UsageFetcher.swift`
- Modify: `Tests/CodexBarTests/CursorStatusProbeUsageSummaryTests.swift`

**Step 1: Write failing test for two range summaries**

Add a test that constructs usage events covering:

- one event inside both last 30 days and billing cycle
- one event inside billing cycle but outside last 30 days
- one event outside billing cycle but inside last 30 days, if billing-cycle start is later than the 30-day start

Expected assertions:

```swift
#expect(usageSnapshot.cursorRangeSummaries?.first { $0.rangeKind == .billingCycle }?.tokens == expectedCycleTokens)
#expect(usageSnapshot.cursorRangeSummaries?.first { $0.rangeKind == .last30Days }?.tokens == expected30DayTokens)
#expect(cycleSummary.range.start == billingCycleStartDate)
#expect(last30Summary.range.start == now.addingTimeInterval(-30 * 24 * 60 * 60))
```

Use a fixed `now` injection if one already exists. If no injection exists, add the smallest parser-only helper that accepts `now` for deterministic tests.

**Step 2: Run RED test**

Run:

```bash
swift test --filter CursorStatusProbeUsageSummaryTests
```

Expected: fails because `cursorRangeSummaries` and filtering do not exist.

**Step 3: Implement range summary model**

Add:

- `CursorUsageRangeKind`
- `CursorRangeUsageSummary`
- Codable/Sendable conformance
- optional `cursorRangeSummaries` on `UsageSnapshot`

Keep `cursorTokenUsage` and `cursorRecentRequests` for backward compatibility during migration.

**Step 4: Compute both summaries in Cursor parser**

In `CursorStatusProbe.parseUsageSummary`:

- Convert all fetched events to `allEventRequests`.
- Compute billing-cycle range from Cursor billing metadata.
- Compute last-30-days range from `now - 30 days` to `now`.
- Filter `allEventRequests` by timestamp for each range.
- Sum tokens and requests per range.
- Compute `CursorRequestCostEstimator.summarizedEstimate(for:)` per range.
- Store recent requests per range sorted newest-first and capped to 30.

**Step 5: Run GREEN test**

Run:

```bash
swift test --filter CursorStatusProbeUsageSummaryTests
```

Expected: pass.

---

## Task 2: Fetch Wide Enough Cursor Usage Event Range

**Files:**
- Modify: `Sources/CodexBarCore/Providers/Cursor/CursorStatusProbe.swift`
- Modify: `Tests/CodexBarTests/CursorStatusProbeUsageSummaryTests.swift`

**Step 1: Add failing fetch-range helper test**

Add a pure helper test for the requested event-fetch start:

- billing cycle start is 2026-05-17
- now is 2026-06-15
- last 30 days starts 2026-05-16
- expected fetch start is 2026-05-16

Add the opposite case:

- billing cycle start is older than 30 days
- expected fetch start is billing cycle start

Add malformed metadata coverage:

- billing cycle start is malformed or unparsable
- expected fetch start is `now - 30 days`

**Step 2: Run RED test**

Run:

```bash
swift test --filter CursorStatusProbeUsageSummaryTests
```

Expected: fails until a helper exists.

**Step 3: Implement fetch-start helper**

Add a small helper:

```swift
static func cursorUsageEventsStartDate(billingCycleStart: String?, now: Date) -> Date
```

It returns `min(parsedBillingCycleStart, now - 30 days)`, falling back to `now - 30 days` when Cursor omits billing-cycle start or returns an unparsable value.

**Step 4: Use helper in `fetchUsageEvents`**

Replace current billing-cycle-only start with the helper so one paginated fetch covers both views.

**Step 5: Run GREEN test**

Run:

```bash
swift test --filter CursorStatusProbeUsageSummaryTests
```

Expected: pass.

---

## Task 3: Add Persistent Range Selection

**Files:**
- Modify: `Sources/CodexBar/SettingsStore.swift`
- Modify: `Sources/CodexBar/SettingsStoreState.swift`
- Modify likely: `Sources/CodexBar/SettingsStore+Defaults.swift`
- Modify: `Sources/CodexBar/SettingsStore+MenuObservation.swift`
- Modify likely: `Tests/CodexBarTests/SettingsStoreTests.swift`

**Step 1: Find existing settings pattern**

Run:

```bash
rg -n "UserDefault|@ObservationIgnored|Display|Provider|selected" Sources/CodexBar/SettingsStore* Tests/CodexBarTests/SettingsStore*
```

Use the existing defaults pattern.

**Step 2: Add failing persistence test**

Add a test that:

- creates `SettingsStore` with isolated suite
- asserts default `cursorUsageRangeKind == .billingCycle`
- sets `.last30Days`
- creates a new store on same suite
- asserts persisted `.last30Days`
- writes an invalid raw value directly to defaults
- asserts the next store falls back to `.billingCycle`

**Step 3: Run RED test**

Run:

```bash
swift test --filter SettingsStoreTests
```

Expected: fails until setting exists.

**Step 4: Implement setting**

Add `cursorUsageRangeKind` backed by `UserDefaults`, storing raw string values from `CursorUsageRangeKind`.

Invalid stored values must fall back to `.billingCycle`.

Wire this setting through every settings state/observation seam used by the menu and widget:

- add it to `SettingsDefaultsState`
- load/save it in `loadDefaultsState`
- include it in `SettingsStore+MenuObservation` dependencies so menu models invalidate when it changes
- expose a mutation path that can be called by the segmented picker

**Step 5: Run GREEN test**

Run:

```bash
swift test --filter SettingsStoreTests
```

Expected: pass.

---

## Task 4: Add Cursor Menu Range Switch

**Files:**
- Modify: `Sources/CodexBar/MenuCardView.swift`
- Modify: `Sources/CodexBar/MenuCardTokenDetailsView.swift` if the extracted detail view owns the header in some layouts
- Modify: `Sources/CodexBar/StatusItemController+Menu.swift`
- Modify: `Tests/CodexBarTests/MenuCardCursorRequestDetailsTests.swift`
- Modify: `Tests/CodexBarTests/MenuCardModelTests.swift` if model construction changes

**Step 1: Add model tests for selected range**

Add tests that build `UsageSnapshot` with both range summaries and `SettingsStore.cursorUsageRangeKind`:

- selected `.billingCycle` returns:
  - title `Tokens`
  - `Requests: used / limit` when quota exists
  - `Cycle: ... tokens`
  - cycle range
  - cycle rows
- selected `.last30Days` returns:
  - `Requests: N`
  - `30d: ... tokens`
  - 30-day range
  - 30-day rows

**Step 2: Run RED tests**

Run:

```bash
swift test --filter "MenuCardCursorRequestDetailsTests|MenuCardModelTests"
```

Expected: fails until menu model selects range summaries.

**Step 3: Extend `TokenUsageSection`**

Add:

```swift
let selectedCursorRangeKind: CursorUsageRangeKind?
let availableCursorRangeKinds: [CursorUsageRangeKind]
let selectCursorRange: ((CursorUsageRangeKind) -> Void)?
```

or a nested presentation struct if that matches local style better.

Also pass selected range and mutation closure through `UsageMenuCardView.Model.Input` from `StatusItemController+Menu.swift` so the view can update `SettingsStore.cursorUsageRangeKind` without directly owning settings.

**Step 4: Update Cursor token section model**

In `tokenUsageSection(input:)`:

- choose selected summary from `input.snapshot?.cursorRangeSummaries`
- default to `.billingCycle`
- fall back to current legacy fields if summaries are absent
- keep quota denominator only for `.billingCycle`
- format `.last30Days` as `Requests: N` without `/ limit`
- ensure selected range controls both `cursorRequestRange` and `cursorRequestDetails`, not only token totals
- use `UsageFormatter.cursorEstimatedTotalText(summary.requestCostSummary)`
- set `cursorRequestRange` and `cursorRequestDetails` from selected summary

**Step 5: Add segmented switch UI**

In the token section header:

- use a compact segmented `Picker` or equivalent SwiftUI control
- show `30d` and `Cycle`
- align it to the trailing edge of the `Tokens` header row
- update `SettingsStore.cursorUsageRangeKind` on selection
- keep controls small enough for the menu width

Do not add visible help text.

**Step 6: Run GREEN tests**

Run:

```bash
swift test --filter "MenuCardCursorRequestDetailsTests|MenuCardModelTests"
```

Expected: pass.

---

## Task 5: Apply Selected Range To Widget Snapshot

**Files:**
- Modify: `Sources/CodexBar/UsageStore+WidgetSnapshot.swift`
- Modify: `Sources/CodexBar/UsageStore.swift`
- Modify: `Sources/CodexBarCore/WidgetSnapshot.swift` if selected range metadata needs to be persisted
- Modify: `Sources/CodexBarWidget/CodexBarWidgetViews.swift`
- Modify: `Tests/CodexBarTests/CursorWidgetSnapshotTests.swift`

**Step 1: Add failing widget tests**

Add tests for:

- default setting `.billingCycle` persists cycle tokens/cost/range/details
- setting `.last30Days` persists 30-day tokens/cost/range/details
- `TokenUsageSummary.sessionLabel` is `Cycle` for cycle and `30d` for last 30 days
- widget request details remain capped at 30
- old snapshots or `UsageSnapshot` values with no `cursorRangeSummaries` still fall back to current `cursorTokenUsage` and `cursorRecentRequests`

**Step 2: Run RED tests**

Run:

```bash
swift test --filter CursorWidgetSnapshotTests
```

Expected: fails until widget snapshot uses selected range summary.

**Step 3: Update widget snapshot builder**

In `UsageStore+WidgetSnapshot`:

- read selected Cursor range from `SettingsStore`
- pick matching `CursorRangeUsageSummary`
- build `WidgetSnapshot.TokenUsageSummary` from that summary
- build `cursorRequestRange` and `cursorRequestDetails` from the selected summary
- keep backward-compatible fallback to current `cursorTokenUsage` and `cursorRecentRequests`

**Step 4: Trigger widget snapshot refresh on setting change**

When `SettingsStore.cursorUsageRangeKind` changes:

- persist the setting
- persist a new widget snapshot from the latest in-memory provider snapshot
- reload widget timelines through the existing widget reload path if one exists
- add `cursorUsageRangeKind` to `UsageStore.observeSettingsChanges()` or the equivalent stable observation path so setting changes are seen without a provider refresh

Add a test at the closest stable seam proving a setting change causes the next persisted widget snapshot to use the newly selected range without requiring a provider network refresh.

**Step 5: Update widget range display if needed**

The existing `CursorRequestDetailsView` already renders `WidgetFormat.cursorRequestRange(range)`. Keep that, but ensure the range passed is selected-range-specific.

**Step 6: Run GREEN tests**

Run:

```bash
swift test --filter CursorWidgetSnapshotTests
```

Expected: pass.

---

## Task 6: Documentation And Propagation

**Files:**
- Modify: `docs/cursor.md`
- Modify: `docs/widgets.md`
- Modify: `docs/plans/2026-06-15-cursor-usage-range-switch.md` if implementation deviates
- If `docs/knowledge/` exists by implementation time, update active timeline per global protocol.

**Step 1: Search propagation**

Run:

```bash
rg -n "cursorTokenUsage|cursorRecentRequests|cursorRangeSummaries|CursorUsageRangeKind|TokenUsageSummary|cursorRequestRange|cursorRequestDetails" Sources Tests docs
```

Expected: no stale single-range assumptions in changed surfaces.

**Step 2: Update docs**

Update Cursor/widget docs to mention:

- Cursor legacy request plans default to billing-cycle view.
- `30d` view is available as a range switch.
- Cost remains an estimate; legacy billing remains request-based.

**Step 3: Run docs-neutral verification**

Run:

```bash
pnpm check
```

Expected: pass.

---

## Task 7: Full Verification, App Relaunch, And Code Review

**Files:**
- No new source changes unless verification fails.

**Step 1: Run focused tests**

Run:

```bash
swift test --filter "CursorStatusProbeUsageSummaryTests|CursorWidgetSnapshotTests|MenuCardCursorRequestDetailsTests|MenuCardModelTests|SettingsStoreTests"
```

Expected: pass.

**Step 2: Run lint**

Run:

```bash
pnpm check
```

Expected: pass.

**Step 3: Rebuild and relaunch**

Run:

```bash
./Scripts/compile_and_run.sh
```

Expected: app builds, packages, relaunches, and remains running.

**Step 4: Inspect widget snapshot**

Read:

```bash
~/Library/Group Containers/Y5PE65HELJ.com.steipete.codexbar/widget-snapshot.json
```

Expected:

- Cursor token usage label matches selected range.
- Cursor token total is not merely the visible-row sum.
- Cursor request range matches selected range.
- Request rows remain capped.

**Step 5: Get Codex code approval**

Run Codex review in code mode with the final diff and this plan as context.

Expected:

- `VERDICT: APPROVED`

**Step 6: Commit atomically**

Stage only the files touched by this feature, including docs and tests.

Commit message:

```bash
git commit -m "feat(cursor): add usage range switch"
```

Expected: commit succeeds and contains only the Cursor range-switch feature plus required docs/tests.
