# Codex Cost History Missing Days Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Keep token-bearing Codex usage days visible and selectable when local dollar pricing is unavailable.

**Architecture:** Extract the chart's input normalization into an internal Foundation-only model. Preserve optional
cost through normalization, plot unknown cost at the zero baseline, and format it as unavailable in details rather
than inventing a dollar value.

**Tech Stack:** Swift 6, SwiftUI Charts, Swift Testing, SwiftPM

---

### Task 1: Reproduce missing unknown-cost days

**Files:**
- Create: `Tests/CodexBarTests/CostHistoryChartDataTests.swift`
- Modify: `Sources/CodexBar/CostHistoryChartMenuView.swift`

1. Add tests with consecutive known-cost, unknown-cost/token-bearing, component-token-only, negative, and empty entries.
2. Assert that positive token dates are retained, invalid dates are excluded, and only known positive cost is the peak.
3. Run the focused test and confirm it fails before production behavior changes.

### Task 2: Preserve token-bearing days

**Files:**
- Modify: `Sources/CodexBar/CostHistoryChartMenuView.swift`
- Test: `Tests/CodexBarTests/CostHistoryChartDataTests.swift`

1. Add the minimal internal chart-data normalization model.
2. Make the view render bars using `costUSD ?? 0` while retaining optional cost for details.
3. Format unknown cost as an em dash and restrict peak selection to known positive costs.
4. Run the focused tests until green.

### Task 3: Verify and deliver

**Files:**
- Modify only files required by Tasks 1 and 2.

1. Run `swiftformat Sources Tests` and `swiftlint --strict`.
2. Run `pnpm check`.
3. Run `./Scripts/compile_and_run.sh --test` to build, test, package, relaunch, and verify the app.
4. Confirm the running executable belongs to this workspace and inspect the refreshed Codex cost cache dates.
5. Review propagation references and documentation, stage only these files, and create one atomic commit.
