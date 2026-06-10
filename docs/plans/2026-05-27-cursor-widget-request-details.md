# Cursor Widget Request Details Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Show Cursor legacy-plan widget details with cycle tokens plus recent request rows containing model, time, token spend, and numeric request count.

**Architecture:** Add a Cursor-only recent request model to the core usage snapshot, populate it from Cursor's authenticated dashboard usage data, persist it into the shared widget snapshot, and render a bounded fixed-height row list in WidgetKit behind Cursor-only UI branches. Existing Cursor quota count and cycle-token summaries stay intact; widgets show the most recent rows plus a `+N more` affordance instead of trying to scroll inside WidgetKit.

**Tech Stack:** Swift 6.2, Swift Testing, SwiftUI, WidgetKit, existing Cursor cookie/API fetcher, SwiftPM.

---

## Current State

- Cursor summary fetching lives in `Sources/CodexBarCore/Providers/Cursor/CursorStatusProbe.swift`.
- Current Cursor legacy quota data comes from `/api/usage?user=<id>` and is modeled by `CursorUsageResponse` and `CursorModelUsage`.
- Cycle tokens already flow through:
  - `CursorStatusSnapshot.billingCycleTokensUsed`
  - `UsageSnapshot.cursorTokenUsage`
  - `WidgetSnapshot.TokenUsageSummary` with label `Cycle`
- The widget snapshot has no per-request row model today.
- The widget UI renders token totals through `Sources/CodexBarWidget/CodexBarWidgetViews.swift`.
- WidgetKit widgets should not rely on vertical scrolling for usage rows. Keep the widget fixed-height by showing a bounded subset of recent Cursor requests and a `+N more` summary when the snapshot contains additional rows.
- There is one unplanned dirty test diff in `Tests/CodexBarTests/CursorStatusProbeUsageSummaryTests.swift` from an interrupted attempt. Before execution, inspect it and either keep it as Task 1's RED test or revert and recreate it under this plan.

---

### Task 1: Inspect And Normalize Existing Dirty Test Diff

**Files:**
- Inspect: `Tests/CodexBarTests/CursorStatusProbeUsageSummaryTests.swift`

**Step 1: Inspect the current diff**

Run:

```bash
git diff -- Tests/CodexBarTests/CursorStatusProbeUsageSummaryTests.swift
```

Expected: the only diff is a test named like `parse usage summary carries recent cursor request events`.

**Step 2: Decide how to proceed**

- If the diff matches Task 2's desired RED test, keep it.
- If it is incomplete or mismatched, revert only that file and recreate the RED test in Task 2.
- If the diff contains unrelated assertions or behavior outside Cursor recent request parsing, split those changes out: keep only the RED test needed for Task 2 and revert the rest of that file.

Do not touch production code in this task.

---

### Task 2: Write RED Tests For Cursor Recent Request Data

**Files:**
- Modify: `Tests/CodexBarTests/CursorStatusProbeUsageSummaryTests.swift`
- Modify: `Tests/CodexBarTests/WidgetSnapshotTests.swift`
- Modify: `Tests/CodexBarTests/CursorWidgetSnapshotTests.swift`

**Step 1: Add Cursor parser/model test**

Add a test that constructs a Cursor usage event row with:

- timestamp
- model, for example `claude-opus-4-7-thinking-xhigh`
- token fields that sum to a known total
- numeric request count `1`

Expected assertions:

- `UsageSnapshot.cursorRecentRequests?.count == 1`
- first row preserves model
- first row preserves timestamp as a `Date`
- first row stores summed token spend
- first row stores numeric request count

**Step 2: Add widget snapshot round-trip test**

Add a `WidgetSnapshotTests` case that encodes and decodes a Cursor `ProviderEntry` with recent request details.

Expected assertions:

- decoded entry has one request detail row
- model, tokens, requests, and timestamp survive JSON round trip
- decoding legacy widget JSON without the new field still succeeds

**Step 3: Add UsageStore widget snapshot test**

Extend `CursorWidgetSnapshotTests` or add a focused test that seeds a Cursor `UsageSnapshot` containing more than 30 request rows.

Expected assertions:

- saved widget entry includes request details
- request details are capped at 30
- newest rows are first
- malformed rows are filtered before capping, then the remaining rows are sorted newest-first and capped at 30

**Step 4: Verify RED**

Run:

```bash
swift test --filter CursorStatusProbeUsageSummaryTests
swift test --filter WidgetSnapshotTests
swift test --filter CursorWidgetSnapshotTests
```

Expected: tests fail because `CursorUsageEvent`, `cursorRecentRequests`, or widget request detail fields do not exist yet.

---

### Task 3: Add Core Recent Request Models

**Files:**
- Create: `Sources/CodexBarCore/Providers/Cursor/CursorRecentRequest.swift`
- Modify: `Sources/CodexBarCore/UsageFetcher.swift`

**Step 1: Add `CursorRecentRequest`**

Create:

```swift
import Foundation

public struct CursorRecentRequest: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let model: String
    public let tokens: Int
    public let requests: Int

    public init(timestamp: Date, model: String, tokens: Int, requests: Int) {
        self.timestamp = timestamp
        self.model = model
        self.tokens = tokens
        self.requests = requests
    }
}
```

**Step 2: Extend `UsageSnapshot`**

Add:

```swift
public let cursorRecentRequests: [CursorRecentRequest]?
```

Thread it through:

- initializer
- `withIdentity(_:)`
- any copy/scoping paths that must preserve all snapshot fields

Keep `UsageSnapshot` decode behavior consistent with current Cursor request/token fields. These are fresh runtime fields today, so do not accidentally persist stale Cursor request details through cached `UsageSnapshot` JSON unless the app already has a reason to do so.

**Step 3: Verify model compile progress**

Run:

```bash
swift test --filter CursorStatusProbeUsageSummaryTests
```

Expected: errors move from missing `UsageSnapshot` field to missing Cursor event decoding/plumbing.

---

### Task 4: Decode Cursor Usage Event Rows

**Files:**
- Modify: `Sources/CodexBarCore/Providers/Cursor/CursorStatusProbe.swift`

**Step 1: Add API decode structs**

Add Cursor event decode structs near the existing Cursor usage API models. Keep them narrow and tolerant:

- `CursorUsageEvent`
- `CursorUsageEventTokenUsage`

The tests should drive the exact public initializer surface needed.

**Step 2: Normalize timestamps**

Support:

- ISO 8601 strings
- millisecond epoch strings
- second or millisecond numeric epochs

**Step 3: Normalize token spend**

Token total order:

1. explicit total token field if present
2. sum known token fields
3. omit row if no token information exists

Known fields should include input, output, cache read, and cache write variants if Cursor returns them.

**Step 4: Normalize request count**

Use numeric request/count fields. Default to `1` only when the row clearly represents a single request event. Do not include dashboard `Type`.

**Step 5: Thread through snapshots**

Add recent requests to:

- `CursorStatusSnapshot`
- `CursorStatusSnapshot.init`
- `CursorStatusSnapshot.toUsageSnapshot()`
- `CursorStatusProbe.parseUsageSummary(...)`

Sort newest first and cap to 30 before creating the final snapshot.

**Step 6: Verify GREEN for parser/model**

Run:

```bash
swift test --filter CursorStatusProbeUsageSummaryTests
```

Expected: parser/model tests pass.

---

### Task 5: Fetch Cursor Dashboard Usage Detail Rows

**Files:**
- Modify: `Sources/CodexBarCore/Providers/Cursor/CursorStatusProbe.swift`
- Create: `Tests/CodexBarTests/Fixtures/cursor-usage-events.json`
- Modify: `Tests/CodexBarTests/CursorStatusProbeUsageSummaryTests.swift`

**Step 1: Inspect live Cursor request shape before implementation**

Use browser devtools or existing debug raw JSON to identify the endpoint/parameters backing `cursor.com/dashboard/usage?from=...&to=...`.

Required data:

- endpoint URL
- query parameters for `from` and `to`
- response shape for rows
- timestamp field name and units
- model field name
- token field names
- numeric requests field name

Save a sanitized fixture before writing the network fetcher. The fixture must preserve the real response shape while removing account identifiers and any credential-like values. Record these contract facts in the test name or setup comments:

- whether rows are event rows or aggregates
- timestamp field name and units
- model field name
- token field names and whether an explicit total exists
- numeric requests field name

**Step 2: Add fixture-backed decode test**

Add a test that decodes `Tests/CodexBarTests/Fixtures/cursor-usage-events.json` through the same decoder the runtime fetcher will use.

Expected assertions:

- parsed row count matches the fixture
- model, timestamp, token total, and numeric request count match known fixture values
- no dashboard `Type` value is surfaced into `CursorRecentRequest`

Run:

```bash
swift test --filter CursorStatusProbeUsageSummaryTests
```

Expected: the fixture decode test fails until the event decoder is wired to the real response shape.

**Step 3: Add fetch helper**

Add a helper similar to `fetchRequestUsage(...)` that:

- uses the same cookie header
- uses the same timeout
- requests current billing cycle start through today
- decodes rows to `[CursorUsageEvent]`
- returns raw JSON for debug concatenation if useful

The fetch helper must call the fixture-tested decoder instead of using a separate ad hoc parse path.

**Step 4: Make fetch failure non-fatal**

If detail fetch fails:

- keep Cursor refresh successful
- keep current request quota and cycle tokens
- log/debug only through existing patterns if available

**Step 5: Verify Cursor tests**

Run:

```bash
swift test --filter CursorStatusProbeTests
swift test --filter CursorStatusProbeUsageSummaryTests
```

Expected: all Cursor status tests pass.

---

### Task 6: Persist Cursor Request Details Into Widget Snapshot

**Files:**
- Modify: `Sources/CodexBarCore/WidgetSnapshot.swift`
- Modify: `Sources/CodexBar/UsageStore+WidgetSnapshot.swift`

**Step 1: Add widget request detail model**

Inside `WidgetSnapshot`, add:

```swift
public struct CursorRequestDetail: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let model: String
    public let tokens: Int
    public let requests: Int
}
```

**Step 2: Extend `ProviderEntry`**

Add:

```swift
public let cursorRequestDetails: [CursorRequestDetail]?
```

Update initializer with a default of `nil` to minimize call-site churn.

**Step 3: Populate Cursor-only rows**

In `UsageStore+WidgetSnapshot.swift`, map `UsageSnapshot.cursorRecentRequests` to widget request details only for `.cursor`.

Cap at 30 here as a final safety check.

**Step 4: Verify widget snapshot tests**

Run:

```bash
swift test --filter WidgetSnapshotTests
swift test --filter CursorWidgetSnapshotTests
```

Expected: widget snapshot tests pass.

---

### Task 7: Render Fixed-Height Cursor Request List

**Files:**
- Modify: `Sources/CodexBarWidget/CodexBarWidgetViews.swift`
- Modify: `Tests/CodexBarTests/CodexBarWidgetProviderTests.swift`

**Step 1: Add formatting helpers**

Add `WidgetFormat` helpers if needed:

- compact local time for request timestamp
- compact request label: `Req 1` or `Req N`
- token count can reuse `WidgetFormat.tokenCount`

**Step 2: Add `CursorRequestDetailsView`**

Render rows with:

- model, single line, truncating middle or tail
- time
- token spend
- numeric request count

Do not use `ScrollView` for the WidgetKit UI. WidgetKit widgets need a bounded static layout.

Use fixed bounded row counts:

- medium widget: show 2 or 3 recent rows, whichever fits cleanly with the cycle token summary
- large widget: show 4 to 6 recent rows, whichever fits cleanly with the cycle token summary
- if more rows exist in `cursorRequestDetails`, show a final `+N more` line

The full snapshot can still store up to 30 rows; the widget renders only the bounded subset.

**Step 3: Integrate into widget layouts**

Show the view only when:

- provider is `.cursor`
- `cursorRequestDetails` is non-empty

Integrate in:

- `MediumUsageView`
- `LargeUsageView`
- `SwitcherMediumUsageView`
- `SwitcherLargeUsageView`

Cursor-specific layout contract:

- The cycle token summary stays visible above recent request rows in medium and large widgets.
- When Cursor request details exist, suppress `UsageHistoryChart` in Cursor large widgets so request details have stable space.
- When Cursor request details exist, suppress optional provider-cost rendering in Cursor medium, large, and switcher layouts unless there is enough room after the cycle token summary and bounded request rows.
- Do not change non-Cursor provider layouts.
- Small widgets remain unchanged except existing cycle token summary behavior.

**Step 4: Add focused widget test**

In `CodexBarWidgetProviderTests`, add non-visual tests for the Cursor row presentation helper:

- medium selection returns the expected visible rows and `+N more`
- large selection returns the expected visible rows and `+N more`
- non-Cursor entries return no Cursor request rows

Avoid brittle SwiftUI rendering tests.

**Step 5: Verify**

Run:

```bash
swift test --filter CodexBarWidgetProviderTests
swift build
```

Expected: tests and build pass.

---

### Task 8: Documentation And Propagation

**Files:**
- Modify: `docs/widgets.md`
- Modify or create relevant timeline note under `docs/knowledge/timeline/` if that directory exists in this checkout.

**Step 1: Search references**

Run:

```bash
rg -n "cursorRecentRequests|CursorRecentRequest|CursorRequestDetail|TokenUsageSummary|ProviderEntry|cursorRequestDetails" Sources Tests docs -S
```

Expected: all references are intentional and no call site has stale initializer errors.

**Step 2: Update docs**

Update `docs/widgets.md` to mention Cursor widgets can show cycle token usage plus recent request details for legacy request-plan accounts.

If `docs/knowledge/timeline/` exists, add a dated note summarizing:

- Cursor widget request details
- cap of 30 rows
- numeric request count instead of dashboard Type

**Step 3: Run formatting and lint**

Run:

```bash
swiftformat Sources Tests
swiftlint --strict
```

Expected: no remaining formatting/lint issues.

---

### Task 9: Full Verification And App Relaunch

**Files:**
- No planned edits.

**Step 1: Run test suite**

Run:

```bash
swift test
```

Expected: all tests pass, or document unrelated pre-existing failures with exact failing tests.

**Step 2: Run package check**

Run:

```bash
pnpm check
```

Expected: pass. If the repo has no `pnpm` setup, record the exact command output.

**Step 3: Rebuild and restart app**

Run:

```bash
./Scripts/compile_and_run.sh
```

Expected: builds, tests, packages, launches `CodexBar.app`, and confirms the app stays running.

---

### Task 10: Commit

**Files:**
- Stage only files changed by the implementation.

**Step 1: Final diff review**

Run:

```bash
git status --short
git diff --stat
git diff -- Sources Tests docs
```

Expected: only planned Cursor widget request detail changes are present, plus the plan file if it is part of the same commit.

**Step 2: Stage specific files**

Run `git add` with explicit file paths only.

**Step 3: Commit**

Run:

```bash
git commit -m "Improve Cursor widget request details"
```

Expected: one scoped commit.
