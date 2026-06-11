# Fable 5 Cursor Estimate Repair Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Claude Fable 5 pricing and show approximate estimates for total-only priced Anthropic Cursor rows such as Opus 4.8 `max` with 252K tokens.

**Architecture:** The primary Cursor request-cost branch has now been merged into `main`, restoring the request model contracts, Opus 4.7/4.8 pricing aliases, and Claude pricing capability helper. First lock that restored baseline with focused tests. Then extend the shared Claude pricing catalog with Fable 5 and reuse the pricing-rate capabilities so the Cursor estimator can produce honest exact estimates when breakdowns exist and approximate ranges when only total tokens exist. The Cursor legacy plan remains request-based; cost labels stay diagnostic and exact-vs-approximate text must remain explicit.

**Tech Stack:** Swift 6, SwiftPM, Swift Testing, existing `CostUsagePricing`, `CursorModelNormalizer`, `CursorRequestCostEstimator`, `UsageFormatter`, widget snapshot plumbing, official Anthropic pricing docs.

---

## Findings From Pre-Plan Investigation

- Official source checked 2026-06-11: Anthropic pricing docs list Claude Fable 5 at:
  - base input: `$10 / MTok`
  - 5-minute cache write: `$12.50 / MTok`
  - 1-hour cache write: `$20 / MTok`
  - cache hits/refreshes: `$1 / MTok`
  - output: `$50 / MTok`
- Official source also says Opus 4.8 is `$5 / MTok` input, `$6.25 / MTok` 5-minute cache write, `$10 / MTok` 1-hour cache write, `$0.50 / MTok` cache hit, `$25 / MTok` output.
- Anthropic docs say Fable 5 and Opus 4.8 include the full 1M context window at standard pricing, so a 252K total-only row should not be rejected because it is over 200K.
- Before merging the primary Cursor branch, `main` failed to compile because `CursorRecentRequest`, `CursorRecentRequestRange`, and `CursorRecentRequestTokenBreakdown` were missing.
- After merging `codex/opencode-multi-workspace-ux` into `main` as `a7dc2646`, the focused baseline passed:
  - command: `swift test --filter CursorModelNormalizerTests --filter CursorRequestCostEstimatorTests --filter CostUsagePricingTests --filter CursorStatusProbeUsageSummaryTests --filter CursorWidgetSnapshotTests`
  - result: 54 tests passed
- Branch/worktree check:
  - active workspace: `/Users/valsaraj/Documents/projects/CodexBar` on `main` at `a7dc2646`
  - extra worktree: `/Users/valsaraj/.codex/worktrees/e4c7/CodexBar`, detached at `9f191992` (`codex/better-graphs`), older and unrelated to Cursor request-cost work
  - local branch `codex/opencode-multi-workspace-ux` at `d24e559f` has been merged and remains a reference for the restored Cursor request-cost work
- Likely reason for the 12:43 PM Opus 4.8 `max` 252K row showing no estimate:
  - `CursorModelNormalizer` maps `claude-opus-4-8-thinking-max` to pricing key `claude-opus-4-8`
  - `CursorRequestCostEstimator` currently returns `.totalOnlyUnavailable` for Anthropic total-only rows
  - Therefore total-only Opus rows show no estimate even when pricing exists

## Product Contract

- Cursor legacy plan quota remains request-based. Keep `Requests: used / limit` primary.
- Exact cost labels use `Est. $X` only when input/output/cache breakdown is available and priced.
- Total-only priced model rows use `Approx. $low-$high`; never present a midpoint as exact.
- For total-only Anthropic rows, the range must be conservative across known priced token categories because Cursor does not expose whether total tokens were input, output, cache read, or cache write.
- Unknown models remain cost-unavailable; do not fabricate rates.
- Fable 5 should normalize from likely Cursor strings such as `claude-fable-5`, `claude-fable-5-thinking`, and `claude-fable-5-thinking-max`.
- Thinking effort (`max`, `xhigh`, etc.) must not change the pricing key.
- Cache-write tier remains the existing 5-minute default for exact Anthropic breakdowns unless Cursor exposes a tier.
- Opus 4.8 total-only rows with 252K tokens should show an approximate range from all-tokens-cache-read to all-tokens-output, with the explanation naming the unknown input/output/cache split:
  - standard Opus 4.8 range: about `$0.13-$6.30`
  - if the raw model later encodes Anthropic Fast Mode, a separate plan must add fast-mode detection before using fast-mode rates

---

## Task 0: Confirm Restored Cursor Request-Cost Baseline

**Files:**
- Inspect/verify: `Sources/CodexBarCore/Providers/Cursor/CursorRecentRequest.swift`
- Inspect/verify: `Sources/CodexBarCore/Vendored/CostUsage/CostUsagePricing.swift`
- Inspect/verify: `Tests/CodexBarTests/CostUsagePricingTests.swift`

**Step 1: Confirm Cursor request model contracts exist**

Confirm `Sources/CodexBarCore/Providers/Cursor/CursorRecentRequest.swift` exists and contains:

- `CursorRecentRequestTokenBreakdown`
- `CursorRecentRequest`
- `CursorRecentRequestRange`

**Step 2: Confirm pricing helper contracts and Opus aliases exist**

Confirm `Sources/CodexBarCore/Vendored/CostUsage/CostUsagePricing.swift` contains:

- `claude-opus-4-7`
- `claude-opus-4-8`
- `supportedCodexPricingKey(_:)`
- `supportedClaudePricingKey(_:)`
- `ClaudePricingCapabilities`
- `claudePricingCapabilities(model:)`

**Step 3: Confirm focused pricing tests exist**

Confirm `Tests/CodexBarTests/CostUsagePricingTests.swift` covers:

- `claude opus 4-8 normalizes and prices flat`
- `claude opus 4-7 normalizes and prices flat`
- `claude pricing capabilities exposes rates`

**Step 4: Verify restored baseline remains green**

Run:

```bash
swift test --filter CursorModelNormalizerTests --filter CursorRequestCostEstimatorTests --filter CostUsagePricingTests --filter CursorStatusProbeUsageSummaryTests --filter CursorWidgetSnapshotTests
```

Expected:

- no missing type errors for `CursorRecentRequest*`
- no missing helper errors for `supportedClaudePricingKey` / `supportedCodexPricingKey`
- existing Cursor/pricing/widget tests pass before adding Fable 5 or Anthropic total-only estimate behavior

---

## Task 1: Add Claude Fable 5 To Shared Pricing Catalog

**Files:**
- Modify: `Sources/CodexBarCore/Vendored/CostUsage/CostUsagePricing.swift`
- Modify: `Tests/CodexBarTests/CostUsagePricingTests.swift`
- Modify: `docs/cursor.md`

**Step 1: Add failing pricing tests**

Add tests:

```swift
@Test
func `claude fable 5 normalizes and prices official rates`() {
    #expect(CostUsagePricing.normalizeClaudeModel("claude-fable-5") == "claude-fable-5")
    let cost = CostUsagePricing.claudeCostUSD(
        model: "claude-fable-5",
        inputTokens: 1_000_000,
        cacheReadInputTokens: 1_000_000,
        cacheCreationInputTokens: 1_000_000,
        outputTokens: 1_000_000)
    let expected = 10 + 1 + 12.5 + 50
    #expect(abs((cost ?? 0) - expected) < 1e-9)
}
```

Add a dated/variant normalization test only if Cursor or Anthropic exposes a dated Fable ID in local fixtures. Otherwise keep this limited to `claude-fable-5`.

**Step 2: Run RED test**

Run:

```bash
swift test --filter CostUsagePricingTests
```

Expected: Fable 5 test fails because pricing is not in the catalog.

**Step 3: Add Fable pricing**

In `CostUsagePricing.claude`, add:

```swift
"claude-fable-5": ClaudePricing(
    inputCostPerToken: 1.0e-5,
    outputCostPerToken: 5.0e-5,
    cacheCreationInputCostPerToken: 1.25e-5,
    cacheReadInputCostPerToken: 1.0e-6,
    thresholdTokens: nil,
    inputCostPerTokenAboveThreshold: nil,
    outputCostPerTokenAboveThreshold: nil,
    cacheCreationInputCostPerTokenAboveThreshold: nil,
    cacheReadInputCostPerTokenAboveThreshold: nil),
```

Add a nearby source comment:

```swift
// Source: Anthropic pricing docs, checked 2026-06-11.
// Fable 5: $10 input, $12.50 5m cache write, $20 1h cache write, $1 cache hit, $50 output per MTok.
// This catalog stores the 5-minute cache-write rate used by CodexBar's default cache-write assumption.
```

**Step 4: Run GREEN test**

Run:

```bash
swift test --filter CostUsagePricingTests
```

Expected: pass.

---

## Task 2: Normalize Cursor Fable Model Names

**Files:**
- Modify: `Sources/CodexBarCore/Providers/Cursor/CursorModelNormalizer.swift`
- Modify: `Tests/CodexBarTests/CursorModelNormalizerTests.swift`

**Step 1: Add failing normalizer tests**

Add:

```swift
@Test
func `normalizes claude fable 5 with pricing key`() {
    let model = CursorModelNormalizer.normalize("claude-fable-5-thinking-max")
    #expect(model.rawName == "claude-fable-5-thinking-max")
    #expect(model.displayName == "Fable 5")
    #expect(model.provider == .anthropic)
    #expect(model.family == "fable")
    #expect(model.version == "5")
    #expect(model.mode == "thinking")
    #expect(model.effort == "max")
    #expect(model.pricingKey == "claude-fable-5")
}
```

Also add:

```swift
@Test
func `fable effort never changes pricing key`() {
    #expect(CursorModelNormalizer.normalize("claude-fable-5").pricingKey == "claude-fable-5")
    #expect(CursorModelNormalizer.normalize("claude-fable-5-thinking").pricingKey == "claude-fable-5")
    #expect(CursorModelNormalizer.normalize("claude-fable-5-thinking-xhigh").pricingKey == "claude-fable-5")
}
```

**Step 2: Run RED test**

Run:

```bash
swift test --filter CursorModelNormalizerTests
```

Expected: fails until Task 1 pricing key is present, or passes if Task 1 already added the key. The test still guards future regressions.

**Step 3: Implement minimal normalizer changes if needed**

The existing Anthropic parser should handle `claude-fable-5-thinking-max` once `CostUsagePricing.supportedClaudePricingKey("claude-fable-5")` returns a key. If the tests fail because version parsing assumes two numeric tokens, update the parser to allow single numeric versions.

**Step 4: Run GREEN test**

Run:

```bash
swift test --filter CursorModelNormalizerTests
```

Expected: pass.

---

## Task 3: Add Approximate Total-Only Estimates For Priced Anthropic Rows

**Files:**
- Modify: `Sources/CodexBarCore/Vendored/CostUsage/CostUsagePricing.swift`
- Modify: `Sources/CodexBarCore/Providers/Cursor/CursorRequestCostEstimator.swift`
- Modify: `Sources/CodexBarCore/UsageFormatter.swift` only if labels need adjustment
- Modify: `Tests/CodexBarTests/CostUsagePricingTests.swift`
- Modify: `Tests/CodexBarTests/CursorRequestCostEstimatorTests.swift`

**Step 1: Expand and reuse pricing-rate capabilities safely**

Expand the existing internal capability helper in `CostUsagePricing`. Today it only exposes `distinguishesCacheWriteTiers`; preserve that flag and add the pricing rates/thresholds needed by `CursorRequestCostEstimator`, or add a shared tiered-rate calculator that keeps the raw pricing dictionary private.

```swift
struct ClaudePricingCapabilities: Equatable, Sendable {
    let distinguishesCacheWriteTiers: Bool
    let inputCostPerToken: Double
    let outputCostPerToken: Double
    let cacheCreationInputCostPerToken: Double
    let cacheReadInputCostPerToken: Double
    let thresholdTokens: Int?
    let inputCostPerTokenAboveThreshold: Double?
    let outputCostPerTokenAboveThreshold: Double?
    let cacheCreationInputCostPerTokenAboveThreshold: Double?
    let cacheReadInputCostPerTokenAboveThreshold: Double?
}

static func claudePricingCapabilities(model: String) -> ClaudePricingCapabilities?
```

If the helper shape changes during implementation, keep the contract internal and avoid exposing the raw pricing dictionary.

**Step 2: Add failing capability tests**

In `CostUsagePricingTests`, assert:

```swift
let fable = try #require(CostUsagePricing.claudePricingCapabilities(model: "claude-fable-5"))
#expect(fable.inputCostPerToken == 1.0e-5)
#expect(fable.outputCostPerToken == 5.0e-5)

let opus = try #require(CostUsagePricing.claudePricingCapabilities(model: "claude-opus-4-8"))
#expect(opus.inputCostPerToken == 5.0e-6)
#expect(opus.outputCostPerToken == 2.5e-5)
```

**Step 3: Add failing estimator tests for Opus 4.8 total-only**

Replace or update the current `total only breakdown returns no estimate` test. Add:

```swift
@Test
func `anthropic total only estimate returns approximate range`() {
    let bd = self.breakdown(
        (input: nil, output: nil, cacheRead: nil, cacheWrite: nil),
        total: 252_000,
        confidence: .totalOnly)
    let estimate = CursorRequestCostEstimator.estimate(model: "claude-opus-4-8-thinking-max", breakdown: bd)
    #expect(estimate.confidence == .approximateTotalOnly)
    #expect(estimate.pricingKey == "claude-opus-4-8")
    #expect(estimate.lowerBoundUSD == self.usd(0.126))
    #expect(estimate.upperBoundUSD == self.usd(6.30))
    #expect(estimate.explanation.lowercased().contains("total tokens only"))
    #expect(estimate.explanation.lowercased().contains("unknown input/output/cache split"))
    #expect(estimate.explanation.contains("request-based"))
}
```

**Step 4: Add failing estimator tests for Fable 5**

Add:

```swift
@Test
func `fable exact estimate prices official rates`() {
    let bd = self.breakdown(
        (input: 1_000_000, output: 1_000_000, cacheRead: 1_000_000, cacheWrite: 1_000_000),
        total: 4_000_000,
        confidence: .exactBreakdown)
    let estimate = CursorRequestCostEstimator.estimate(model: "claude-fable-5-thinking-max", breakdown: bd)
    #expect(estimate.confidence == .exactBreakdown)
    #expect(estimate.pricingKey == "claude-fable-5")
    #expect(estimate.usd == self.usd(73.5))
    #expect(estimate.explanation.lowercased().contains("5-minute"))
}

@Test
func `fable total only estimate returns approximate range`() {
    let bd = self.breakdown(
        (input: nil, output: nil, cacheRead: nil, cacheWrite: nil),
        total: 252_000,
        confidence: .totalOnly)
    let estimate = CursorRequestCostEstimator.estimate(model: "claude-fable-5-thinking-max", breakdown: bd)
    #expect(estimate.confidence == .approximateTotalOnly)
    #expect(estimate.lowerBoundUSD == self.usd(0.252))
    #expect(estimate.upperBoundUSD == self.usd(12.60))
    #expect(estimate.explanation.lowercased().contains("unknown input/output/cache split"))
}
```

**Step 5: Add failing estimator test for tiered Claude total-only pricing**

Add a threshold regression using an existing Claude model with `thresholdTokens`:

```swift
@Test
func `anthropic total only estimate applies tiered pricing above threshold`() {
    let bd = self.breakdown(
        (input: nil, output: nil, cacheRead: nil, cacheWrite: nil),
        total: 250_000,
        confidence: .totalOnly)
    let estimate = CursorRequestCostEstimator.estimate(model: "claude-sonnet-4-6-thinking-max", breakdown: bd)
    #expect(estimate.confidence == .approximateTotalOnly)
    #expect(estimate.pricingKey == "claude-sonnet-4-6")
    #expect(estimate.lowerBoundUSD == self.usd(0.09))
    #expect(estimate.upperBoundUSD == self.usd(4.125))
}
```

**Step 6: Run RED tests**

Run:

```bash
swift test --filter CostUsagePricingTests
swift test --filter CursorRequestCostEstimatorTests
```

Expected: total-only Anthropic tests fail until implementation is added.

**Step 7: Implement Anthropic total-only approximate range**

In `CursorRequestCostEstimator.estimate(...)`, change `.totalOnly` handling:

- if provider is `.cursor` and cursor pricing exists, keep existing Composer range path
- if provider is `.anthropic` and `CostUsagePricing.claudePricingCapabilities(model:)` exists:
  - calculate category scenarios for all total tokens as input, output, cache read, and default 5-minute cache write
  - lower bound = cheapest priced category scenario
  - upper bound = most expensive priced category scenario
  - if the model has threshold pricing, use the existing tier logic or a shared helper so every scenario reflects the correct tier
  - return `.approximateTotalOnly`
- leave OpenAI total-only unavailable unless a separate Codex/OpenAI pricing capability helper is added in a future plan

Add helper shape:

```swift
private static func pricedAnthropicTotalOnly(
    pricingKey: String,
    breakdown: CursorRecentRequestTokenBreakdown
) -> CursorRequestCostEstimate
```

Explanation must include:

- legacy request-based disclaimer
- `Approximate range from total tokens only`
- pricing source label
- explicit caveat that Cursor did not expose the input/output/cache-read/cache-write split for this row
- explicit caveat that the cache-write scenario uses the app's default 5-minute cache-write assumption

**Step 8: Run GREEN tests**

Run:

```bash
swift test --filter CostUsagePricingTests
swift test --filter CursorModelNormalizerTests
swift test --filter CursorRequestCostEstimatorTests
```

Expected: pass.

---

## Task 4: Propagate Approximate Anthropic Estimates To Menu And Widget Surfaces

**Files:**
- Modify: `Tests/CodexBarTests/MenuCardCursorRequestDetailsTests.swift`
- Modify: `Tests/CodexBarTests/CursorWidgetSnapshotTests.swift`
- Modify: `Sources/CodexBar/MenuCardTokenDetailsView.swift` only if current row presentation filters approximate Anthropic estimates
- Modify: `Sources/CodexBar/UsageStore+WidgetSnapshot.swift` only if current snapshot mapping filters approximate Anthropic estimates

**Step 1: Add menu presentation test for Opus 4.8 total-only row**

Add a `CursorRecentRequest` fixture:

- timestamp local equivalent of `12:43 PM` can be any fixed date/time; the exact date is less important than preserving the time label
- model: `claude-opus-4-8-thinking-max`
- tokens: `252_000`
- requests: `1`
- breakdown confidence: `.totalOnly`

Assert row presentation:

- compact model is `Opus 4.8 · max`
- estimate text starts with `Approx.`
- expanded details include `Tokens: 252K (total only)`
- expanded details include `request-based`
- expanded details include the unknown input/output/cache split caveat

**Step 2: Add widget snapshot test for Opus 4.8 total-only row**

Seed a Cursor usage snapshot with the same row and a billing cycle token total.

Assert:

- `cursorRequestDetails.first?.compactModel == "Opus 4.8 · max"`
- `cursorRequestDetails.first?.estimateText` starts with `Approx.`
- `tokenUsage.sessionCostUSD == nil`
- `tokenUsage.sessionCostText` starts with `Approx.`

**Step 3: Run RED/GREEN tests**

Run:

```bash
swift test --filter MenuCardCursorRequestDetailsTests
swift test --filter CursorWidgetSnapshotTests
```

Expected:

- If Task 3 is implemented correctly, these may pass without UI code changes because existing menu/widget mapping uses `UsageFormatter.cursorEstimateText`.
- If they fail, minimally adjust the mapping to preserve `.approximateTotalOnly` for Anthropic rows.

---

## Task 5: Documentation And Source Notes

**Files:**
- Modify: `docs/cursor.md`
- Modify: `docs/widgets.md` if widget wording needs Anthropic approximate examples
- Modify: `docs/plans/2026-06-11-fable5-cursor-total-only-estimates.md` if implementation decisions change

**Step 1: Update Cursor docs**

Document:

- Fable 5 pricing source and checked date
- total-only priced Anthropic rows now show approximate ranges
- Opus 4.8 `max` total-only rows are priced as standard Opus 4.8 unless a distinct raw model indicates Fast Mode
- estimates are diagnostic; Cursor legacy quota remains request-based

**Step 2: Update widget docs if needed**

Document that `sessionCostText` may hold approximate Anthropic ranges, not just Composer ranges.

**Step 3: Propagation search**

Run:

```bash
rg -n "Fable|fable|Opus 4\\.8|claude-opus-4-8|totalOnlyUnavailable|Approx\\.|sessionCostText|supportedClaudePricingKey|CursorRecentRequest" Sources Tests docs
```

Expected:

- no docs claiming only Composer total-only rows can show ranges
- no tests expecting Anthropic total-only rows to be unavailable

---

## Task 6: Full Verification Against The App

**Files:**
- No new files expected beyond tasks above.

**Step 1: Focused tests**

Run:

```bash
swift test --filter CostUsagePricingTests
swift test --filter CursorModelNormalizerTests
swift test --filter CursorRequestCostEstimatorTests
swift test --filter MenuCardCursorRequestDetailsTests
swift test --filter CursorWidgetSnapshotTests
swift test --filter WidgetSnapshotTests
```

Expected: all pass.

**Step 2: Project check**

Run:

```bash
pnpm check
```

Expected: format/lint pass.

**Step 3: Rebuild and relaunch**

Run:

```bash
./Scripts/compile_and_run.sh
```

Expected:

- build succeeds
- tests complete
- package succeeds
- script prints `OK: CodexBar is running.`

**Step 4: Manual validation in the running app**

Open the CodexBar menu and inspect Cursor:

- Cursor request list opens without crash
- Fable 5 rows, if present, show `Fable 5` compact label and an estimate when token data allows
- Opus 4.8 `max` rows with total-only token data show `Approx. $low-$high`
- A 252K Opus 4.8 total-only row would show approximately `$0.13-$6.30`
- expanded row details still include raw model, timestamp, request count, token breakdown, estimate, pricing assumption, and request-based disclaimer
- widget snapshot generated from the app includes approximate text in `sessionCostText` rather than numeric `sessionCostUSD` for approximate totals

---

## Risks And Guardrails

- The baseline was previously build-broken before the primary Cursor branch was merged; do not skip Task 0 because it prevents regressions before adding Fable 5 behavior.
- Per repo instructions, after each implementation edit batch, run `./Scripts/compile_and_run.sh` so the running app reflects the latest changes. Keep batches small enough that this is practical; at minimum use one batch for pricing/estimator logic and one batch for menu/widget/docs propagation.
- The branch `codex/opencode-multi-workspace-ux` has been merged into `main`; do not blindly replace whole files from it during implementation.
- Anthropic Fast Mode pricing for Opus 4.8 is distinct (`$10/$50` per MTok) but current Cursor raw examples use effort `max`, not a clear `fast` marker. This plan must not treat `max` as Fast Mode.
- Total-only ranges can be wide. Keep the `Approx.` label and do not write a midpoint to `sessionCostUSD`.
- US-only inference has a 1.1x multiplier for Fable 5 and Opus 4.8, but Cursor rows do not expose inference geography. Use global/default pricing unless Cursor exposes a reliable geo flag later.
