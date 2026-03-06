# Codex + Claude Utilization History Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a shared utilization history line chart for Codex and Claude, stack it above the existing 30-day cost history chart, and keep the lower cost chart unchanged.

**Architecture:** Capture utilization points from successful `UsageStore` refreshes for `codex` and `claude`, persist them in a small provider-scoped history store, and render them through a new hosted SwiftUI chart view that composes above the existing `CostHistoryChartMenuView`. The upper chart owns its own segmented range control; the lower chart remains fixed to 30-day daily cost bars.

**Tech Stack:** Swift 6, SwiftUI, Swift Charts, Observation-friendly store patterns, XCTest, existing `NSMenu` hosting helpers.

---

## Shared Data Rules

- `ProviderUtilizationHistoryPoint`
  - `timestamp: Date`
  - `primaryUsedPercent: Double`
  - `secondaryUsedPercent: Double?`
- Supported providers: `codex`, `claude`
- Persistence path: `~/Library/Caches/CodexBar/utilization-history/<provider>.json`
- Dedup rule: skip append when the newest stored point for the same provider is less than 60 seconds old and both primary/secondary values are unchanged within a tiny epsilon
- Dedup epsilon: `0.001`
- Empty-state behavior: show the `Usage history (30 days)` submenu for Codex/Claude only when cost history exists as it does today; within the composite view, the upper chart may show an empty-state message until enough utilization history has been recorded
- Composite hosted-menu identifier: `providerUtilizationCompositeChart`
- Provider behavior:
  - `codex` and `claude`: replace the current cost-only submenu content with the composite stacked view
  - `vertexai`: keep the existing cost-only submenu behavior
  - all other providers: no change

### Task 1: Add failing tests for provider utilization history storage

**Files:**
- Create: `Tests/CodexBarTests/ProviderUtilizationHistoryStoreTests.swift`
- Create: `Sources/CodexBar/ProviderUtilizationHistoryStore.swift`
- Create: `Sources/CodexBar/ProviderUtilizationHistoryModels.swift`
- Modify: `Sources/CodexBar/UsageStore.swift`
- Modify: `Sources/CodexBar/UsageStore+Refresh.swift`

**Step 1: Write the failing tests**

Cover:
- appending a Codex or Claude point with primary and optional secondary data
- ignoring unsupported providers
- pruning entries older than 30 days
- preserving `nil` secondary values
- skipping obvious duplicate points when recorded too frequently

**Step 2: Run test to verify it fails**

Run: `swift test --filter ProviderUtilizationHistoryStoreTests`

Expected: missing store/types/functions

**Step 3: Write minimal implementation**

Add the provider-scoped utilization history model/store under `Sources/CodexBar` with in-memory append, pruning, provider filtering, and explicit secondary-value preservation.

**Step 4: Run test to verify it passes**

Run: `swift test --filter ProviderUtilizationHistoryStoreTests`

Expected: PASS

### Task 2: Add persistence and lifecycle coverage for history storage

**Files:**
- Modify: `Tests/CodexBarTests/ProviderUtilizationHistoryStoreTests.swift`
- Modify: `Sources/CodexBar/ProviderUtilizationHistoryStore.swift`

**Step 1: Write the failing tests**

Cover:
- loading saved history from disk
- recovering from corrupt history files safely
- periodic/termination flush behavior through explicit flush calls

**Step 2: Run test to verify it fails**

Run: `swift test --filter ProviderUtilizationHistoryStoreTests`

Expected: persistence assertions fail

**Step 3: Write minimal implementation**

Implement local JSON persistence with 30-day retention and provider partitioning.

**Step 4: Run test to verify it passes**

Run: `swift test --filter ProviderUtilizationHistoryStoreTests`

Expected: PASS

### Task 3: Add failing tests for chart-range downsampling

**Files:**
- Modify: `Tests/CodexBarTests/ProviderUtilizationHistoryStoreTests.swift`
- Modify: `Sources/CodexBar/ProviderUtilizationHistoryModels.swift`

**Step 1: Write the failing tests**

Cover:
- `1h`, `6h`, `1d`, `7d`, `30d` range definitions
- downsampling returns bounded point counts
- old points outside the selected range are excluded from the rendered dataset

**Step 2: Run test to verify it fails**

Run: `swift test --filter ProviderUtilizationHistoryStoreTests`

Expected: missing range model/downsampling behavior

**Step 3: Write minimal implementation**

Add range enum + downsampling helpers shared by the chart/store.

**Step 4: Run test to verify it passes**

Run: `swift test --filter ProviderUtilizationHistoryStoreTests`

Expected: PASS

### Task 4: Add failing tests for `UsageStore` recording hooks

**Files:**
- Create: `Tests/CodexBarTests/UsageStoreHistoryRecordingTests.swift`
- Modify: `Sources/CodexBar/UsageStore.swift`
- Modify: `Sources/CodexBar/UsageStore+Refresh.swift`

**Step 1: Write the failing tests**

Cover:
- successful Claude refresh records history
- successful Codex refresh records history
- failed refresh does not record history
- unsupported providers do not record history

**Step 2: Run test to verify it fails**

Run: `swift test --filter UsageStoreHistoryRecordingTests`

Expected: store has no recording integration yet

**Step 3: Write minimal implementation**

Inject/own the history store in `UsageStore` and record after successful refreshes.

**Step 4: Run test to verify it passes**

Run: `swift test --filter UsageStoreHistoryRecordingTests`

Expected: PASS

### Task 5: Add failing tests for composite Codex/Claude history menu behavior

**Files:**
- Modify: `Tests/CodexBarTests/StatusMenuTests.swift`
- Modify: `Sources/CodexBar/StatusItemController+Menu.swift`

**Step 1: Write the failing tests**

Cover:
- Claude usage history submenu contains a hosted composite history view
- Codex usage history submenu contains a hosted composite history view
- non-Codex/Claude providers keep existing behavior
- submenu only appears when the required history data exists

**Step 2: Run test to verify it fails**

Run: `swift test --filter StatusMenuTests`

Expected: missing composite submenu identifiers/behavior

**Step 3: Write minimal implementation**

Add provider-aware submenu composition and stable represented-object identifiers for the new hosted view.

**Step 4: Run test to verify it passes**

Run: `swift test --filter StatusMenuTests`

Expected: PASS

### Task 6: Implement the new utilization line chart view

**Files:**
- Create: `Sources/CodexBar/ProviderUtilizationChartMenuView.swift`

**Step 1: Port the upstream chart behavior carefully**

Reuse the useful parts:
- segmented range picker
- line/path chart presentation
- hover rule/point inspection
- tooltip formatting

Do not port:
- `ObservableObject` ownership model
- separate polling service
- standalone app assumptions

**Step 2: Adapt the chart to local architecture**

Use provider-scoped history inputs and the existing menu-safe hover handling from `MouseLocationReader` without modifying that helper unless an actual gap appears during implementation.

**Step 3: Verify the chart builds**

Run: `swift build`

Expected: success

### Task 7: Compose the stacked history view above the existing cost chart

**Files:**
- Create: `Sources/CodexBar/ProviderUsageHistoryCompositeMenuView.swift`
- Modify: `Sources/CodexBar/StatusItemController+Menu.swift`

**Step 1: Build the composite view**

Stack:
- utilization chart
- divider
- existing cost history chart

Mirror the existing chart submenu pattern with a `!menuCardRenderingEnabled` fallback path for the new composite submenu builder.

**Step 2: Keep the lower chart behavior unchanged**

The segmented control must update only the upper chart.

**Step 3: Update hosted-menu identifiers and routing**

Add the new represented-object identifier to the hosted-submenu detection logic so sizing/hover behavior still works.

**Step 4: Verify submenu sizing**

Run: `swift build`

Expected: success

### Task 8: Wire Codex and Claude to the composite submenu only

**Files:**
- Modify: `Sources/CodexBar/StatusItemController+Menu.swift`

**Step 1: Restrict new behavior to supported providers**

Codex and Claude:
- add a `makeCompositeHistorySubmenu` path at the call site and use it for Codex/Claude

Vertex AI:
- keep the current cost-only submenu

Other providers:
- existing behavior only

**Step 2: Verify no regressions in provider gating**

Run: `swift test --filter StatusMenuTests`

Expected: PASS

### Task 9: Update docs for the new menu history behavior

**Files:**
- Modify: `README.md`
- Modify: `docs/claude.md`
- Modify: `docs/codex.md`

**Step 1: Document the new chart**

Describe:
- utilization chart ranges
- supported providers
- relationship to the existing 30-day cost chart

**Step 2: Verify docs build/format expectations**

Run: `pnpm check`

Expected: PASS

### Task 10: Run focused verification, then full verification

**Files:**
- Modify: any files above as needed

**Step 1: Run focused tests**

Run:
- `swift test --filter ProviderUtilizationHistoryStoreTests`
- `swift test --filter UsageStoreHistoryRecordingTests`
- `swift test --filter StatusMenuTests`

**Step 2: Run full project verification**

Run:
- `swiftformat Sources Tests`
- `swiftlint --strict`
- `pnpm check`
- `./Scripts/compile_and_run.sh`

**Step 3: Review diff and prepare for Claude code review**

Capture exact behavior changes and test evidence before the code review loop.
