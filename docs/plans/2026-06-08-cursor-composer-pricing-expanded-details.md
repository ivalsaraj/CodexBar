# Cursor Composer Pricing And Expanded Details Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Show useful estimated costs for Cursor Composer 2.5 rows and make Cursor request details accessible through click-to-expand rows instead of relying on unreliable hover help.

**Architecture:** Extend Cursor-owned model normalization/pricing locally for Composer 2.5, keeping Cursor legacy quota request-based while showing diagnostic estimates. Add deterministic menu expansion state to `TokenUsageDetailLinesView` so every request row can reveal the same detail payload currently hidden in `.help(...)`. Widget rows stay compact because WidgetKit does not support hover or arbitrary expanded menu interactions.

**Tech Stack:** Swift 6.2, Swift Testing, SwiftUI, AppKit-hosted `NSMenu` content, WidgetKit snapshot mapping, existing Cursor usage-event models, SwiftPM.

---

## Source Facts And Decisions

- Official Cursor source: `https://cursor.com/changelog/composer-2-5`, checked 2026-06-08.
- Composer 2.5 Standard pricing: `$0.50/M input`, `$2.50/M output`.
- Composer 2.5 Fast pricing: `$3.00/M input`, `$15.00/M output`.
- Cursor says Fast is the default. Therefore raw `composer-2.5` rows default to Fast pricing unless the model string explicitly indicates Standard.
- Cursor legacy plan quota remains request-based. Estimated dollars are diagnostic only and must not replace `Requests: used / limit`.
- User asked to “add both”; this plan treats that as:
  - support both Composer 2.5 Fast and Standard pricing modes, and
  - show a total-only approximate Composer estimate when Cursor does not expose input/output breakdown, clearly labelled as approximate/range rather than exact.
- Existing hover help is unreliable in `NSMenu`-hosted SwiftUI, especially inside a `ScrollView`. Click-to-expand is the primary detail path; `.help(...)` can remain as a bonus.

## Current State

- `Sources/CodexBarCore/Providers/Cursor/CursorModelNormalizer.swift`
  - treats `composer-2.5` as provider `.cursor`
  - sets `pricingKey == nil`
- `Sources/CodexBarCore/Providers/Cursor/CursorRequestCostEstimator.swift`
  - prices Anthropic/OpenAI only
  - returns `.unknownModel` for provider `.cursor`
- `Sources/CodexBar/MenuCardTokenDetailsView.swift`
  - builds `CursorMenuRequestRowPresentation.help`
  - attaches `.help(row.help)` to the row
  - has no row expansion state
- `Sources/CodexBarCore/UsageFormatter.swift`
  - can already produce the multi-line detail text via `cursorRequestHelpText`
- `Sources/CodexBarCore/WidgetSnapshot.swift`
  - `WidgetSnapshot.TokenUsageSummary` currently carries numeric `sessionCostUSD`
  - widgets need a display-text override before approximate cost ranges can be rendered safely
- `Sources/CodexBar/UsageStore+WidgetSnapshot.swift`
  - sums row estimates into the Cursor cycle total when estimates exist
  - maps per-row `estimateText` into widget snapshot details
- `Sources/CodexBarWidget/CodexBarWidgetViews.swift`
  - renders token summary cost text from snapshot values

## Product Contract

- Keep `Requests: N / limit` primary for Cursor legacy request plans.
- Keep `Cycle: N tokens · Est. $X` where a summed estimate exists.
- Show Composer 2.5 row estimates:
  - Exact: when `inputTokens` and `outputTokens` are available.
  - Approx/range: when only `totalTokens` is available.
  - Unavailable: when there are no tokens or pricing-relevant values.
- Do not invent cache pricing for Composer. If Composer rows include `cacheReadTokens`/`cacheWriteTokens`, count them only as input-equivalent in the exact estimate if the event already exposes input/output fields; otherwise mention in expanded details that Composer cache handling is not separately priced by CodexBar.
- Expanded details must include:
  - raw model
  - exact timestamp
  - request count
  - token breakdown
  - estimate text
  - pricing assumption/source note
  - request-based legacy disclaimer
- Do not add hover-only behavior. Hover may remain, but it cannot be the only way to see details.
- Do not change non-Cursor provider menu rows.

---

## Task 1: Add RED Tests For Composer 2.5 Normalization And Pricing

**Files:**
- Modify: `Tests/CodexBarTests/CursorModelNormalizerTests.swift`
- Modify: `Tests/CodexBarTests/CursorRequestCostEstimatorTests.swift`

**Step 1: Update Composer normalization test**

Change the existing `normalizes cursor composer model with no pricing key` test to expect a pricing key and Fast default metadata:

```swift
@Test
func `normalizes cursor composer model with fast pricing key by default`() {
    let model = CursorModelNormalizer.normalize("composer-2.5")
    #expect(model.displayName == "Composer 2.5")
    #expect(model.provider == .cursor)
    #expect(model.family == "composer")
    #expect(model.version == "2.5")
    #expect(model.mode == "fast")
    #expect(model.pricingKey == "composer-2.5-fast")
}
```

**Step 2: Add Standard variant normalization test**

Add:

```swift
@Test
func `normalizes cursor composer standard pricing key`() {
    let model = CursorModelNormalizer.normalize("composer-2.5-standard")
    #expect(model.displayName == "Composer 2.5")
    #expect(model.provider == .cursor)
    #expect(model.mode == "standard")
    #expect(model.pricingKey == "composer-2.5-standard")
}
```

**Step 3: Replace unknown Composer cost test**

Replace `unknown model returns no estimate` so Composer is no longer the unknown-model fixture. Use `some-internal-model-x1` for unknown coverage.

**Step 4: Add exact Composer Fast estimate test**

Add:

```swift
@Test
func `composer fast estimate prices exact input and output breakdown`() {
    let bd = self.breakdown(
        (input: 1_000_000, output: 1_000_000, cacheRead: 0, cacheWrite: 0),
        total: 2_000_000,
        confidence: .exactBreakdown)
    let estimate = CursorRequestCostEstimator.estimate(model: "composer-2.5", breakdown: bd)
    #expect(estimate.confidence == .exactBreakdown)
    #expect(estimate.pricingKey == "composer-2.5-fast")
    #expect(estimate.usd == self.usd(18))
    #expect(estimate.explanation.contains("Fast"))
    #expect(estimate.explanation.contains("request-based"))
}
```

**Step 5: Add exact Composer Standard estimate test**

Add:

```swift
@Test
func `composer standard estimate prices exact input and output breakdown`() {
    let bd = self.breakdown(
        (input: 1_000_000, output: 1_000_000, cacheRead: 0, cacheWrite: 0),
        total: 2_000_000,
        confidence: .exactBreakdown)
    let estimate = CursorRequestCostEstimator.estimate(model: "composer-2.5-standard", breakdown: bd)
    #expect(estimate.confidence == .exactBreakdown)
    #expect(estimate.pricingKey == "composer-2.5-standard")
    #expect(estimate.usd == self.usd(3))
}
```

**Step 6: Add Composer total-only approximate test**

Add a new confidence case expectation such as `.approximateTotalOnly`:

```swift
@Test
func `composer total only estimate returns approximate range`() {
    let bd = self.breakdown(
        (input: nil, output: nil, cacheRead: nil, cacheWrite: nil),
        total: 2_000_000,
        confidence: .totalOnly)
    let estimate = CursorRequestCostEstimator.estimate(model: "composer-2.5", breakdown: bd)
    #expect(estimate.confidence == .approximateTotalOnly)
    #expect(estimate.lowerBoundUSD != nil)
    #expect(estimate.upperBoundUSD != nil)
    #expect(estimate.explanation.lowercased().contains("approx"))
}
```

The implementation must not render a midpoint as an exact-looking dollar amount. If a representative value is ever needed internally for sorting, keep it internal and expose lower/upper display bounds to UI and snapshot formatting.

**Step 7: Verify RED**

Run:

```bash
swift test --filter CursorModelNormalizerTests
swift test --filter CursorRequestCostEstimatorTests
```

Expected: failures for Composer pricing keys and estimator support.

---

## Task 2: Implement Composer Pricing In Core Estimator

**Files:**
- Modify: `Sources/CodexBarCore/Providers/Cursor/CursorModelNormalizer.swift`
- Modify: `Sources/CodexBarCore/Providers/Cursor/CursorRequestCostEstimator.swift`
- Modify: `Sources/CodexBarCore/UsageFormatter.swift`

**Step 1: Add Composer model parsing**

In `CursorModelNormalizer.normalizeGeneric` or a new `normalizeComposer` helper, parse:

- `composer-2.5` -> mode `fast`, pricing key `composer-2.5-fast`
- `composer-2.5-fast` -> mode `fast`, pricing key `composer-2.5-fast`
- `composer-2.5-standard` -> mode `standard`, pricing key `composer-2.5-standard`

Keep display as `Composer 2.5`; do not render `· fast` unless UX explicitly wants it later.

**Step 2: Add Composer pricing constants**

In `CursorRequestCostEstimator`, add local constants:

```swift
private struct CursorModelPricing: Equatable, Sendable {
    let inputUSDPerToken: Double
    let outputUSDPerToken: Double
    let label: String
    let source: String
}

private static let cursorPricing: [String: CursorModelPricing] = [
    "composer-2.5-fast": .init(
        inputUSDPerToken: 3.0 / 1_000_000,
        outputUSDPerToken: 15.0 / 1_000_000,
        label: "Composer 2.5 Fast",
        source: "Cursor Composer 2.5 changelog, checked 2026-06-08"),
    "composer-2.5-standard": .init(
        inputUSDPerToken: 0.5 / 1_000_000,
        outputUSDPerToken: 2.5 / 1_000_000,
        label: "Composer 2.5 Standard",
        source: "Cursor Composer 2.5 changelog, checked 2026-06-08"),
]
```

**Step 3: Add confidence shape for approximate total-only**

Extend `CursorRequestCostEstimate.Confidence` with:

```swift
case approximateTotalOnly
```

Extend `CursorRequestCostEstimate` with optional range fields:

```swift
public let lowerBoundUSD: Decimal?
public let upperBoundUSD: Decimal?
```

Migration impact: update existing initializers/tests. Prefer this over encoding a fake exact `usd` when rendering a range.

Add a summary shape for aggregating exact and approximate rows:

```swift
public struct CursorRequestCostSummary: Equatable, Sendable {
    public let exactUSD: Decimal?
    public let lowerBoundUSD: Decimal?
    public let upperBoundUSD: Decimal?
    public let containsApproximation: Bool
}
```

Use this summary anywhere the cycle-level total is displayed. Exact-only summaries can render `Est. $X`; summaries containing ranges render `Approx. $low-$high`.

**Step 4: Price provider `.cursor`**

In `priced(provider:pricingKey:breakdown:)`, for `.cursor`:

- if pricing key exists in `cursorPricing`
- exact breakdown:
  - `billableInput = input + cacheRead + cacheWrite`
  - `billableOutput = output`
  - cost = input * input rate + output * output rate
  - return `.exactBreakdown`
- total-only:
  - lower bound = all tokens input-priced
  - upper bound = all tokens output-priced
  - `usd` remains nil or internal-only so the UI cannot accidentally present a range as an exact estimate
  - return `.approximateTotalOnly`
- partial/empty/missing: keep unavailable behavior

**Step 5: Add explicit request detail formatter contract**

Add a dedicated formatter API instead of relying on `.help(...)` string splitting:

```swift
public static func cursorRequestDetailLines(
    request: CursorRecentRequest,
    estimate: CursorRequestCostEstimate?,
    now: Date
) -> [String]
```

The formatter owns the expanded detail contract and must include:

- raw model
- exact timestamp
- request count
- token breakdown
- estimate text
- pricing assumption/source note
- request-based legacy disclaimer
- cache-pricing caveat when Composer cache fields exist but Cursor does not publish separate cache billing details

Add formatter tests for:

- exact Composer estimate includes Composer pricing source/assumption text
- approximate total-only Composer estimate includes approximate/range text and source/assumption text
- unavailable estimate still includes request-based disclaimer and token breakdown where available

Keep `cursorRequestHelpText` as a wrapper around `cursorRequestDetailLines(...).joined(separator: "\n")` if existing call sites still need a string.

**Step 6: Format approximate estimates**

Update `UsageFormatter.cursorEstimateText`:

- `.exactBreakdown` -> `Est. $X`
- `.approximateTotalOnly` with range -> `Approx. $low-$high`
- unavailable -> nil

Update `cursorEstimatedTotalText` so cycle totals can use approximate labels if any row total is approximate. Sum lower bounds and upper bounds across rows.

**Step 7: Verify GREEN**

Run:

```bash
swift test --filter CursorModelNormalizerTests
swift test --filter CursorRequestCostEstimatorTests
```

Expected: all pass.

---

## Task 3: Add RED Tests For Click-To-Expand Menu Details

**Files:**
- Modify: `Tests/CodexBarTests/MenuCardCursorRequestDetailsTests.swift`
- Modify: `Sources/CodexBar/MenuCardTokenDetailsView.swift` only after RED tests are in place

**Step 1: Add presentation detail lines test**

Add a test that ensures each `CursorMenuRequestRowPresentation` exposes deterministic detail lines, not only a `help` string:

```swift
@Test
func `cursor request row exposes expanded detail lines`() throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let request = CursorRecentRequest(
        timestamp: now,
        model: "composer-2.5",
        tokens: 2_000_000,
        requests: 1,
        tokenBreakdown: CursorRecentRequestTokenBreakdown(
            inputTokens: 1_000_000,
            outputTokens: 1_000_000,
            cacheReadTokens: 0,
            cacheWriteTokens: 0,
            totalTokens: 2_000_000,
            confidence: .exactBreakdown))

    let row = CursorMenuRequestRowPresentation.make(request: request, index: 0, now: now)

    #expect(row.detailLines.contains { $0.contains("composer-2.5") })
    #expect(row.detailLines.contains { $0.contains("1M in") })
    #expect(row.detailLines.contains { $0.contains("Est.") })
    #expect(row.detailLines.contains { $0.contains("Cursor Composer 2.5 changelog") })
    #expect(row.detailLines.contains { $0.contains("request-based") })
}
```

Expected RED: `detailLines` does not exist.

**Step 2: Add detail formatter contract tests**

Add tests for `UsageFormatter.cursorRequestDetailLines(...)` directly. Cover exact, approximate, and unavailable estimates so the menu and hover string cannot drift from the required expanded diagnostic contract.

**Step 3: Add scroll height policy test for expanded row**

Add a presentation-level test that expanded details do not change the fixed scroll container decision:

```swift
@Test
func `cursor request detail presentation keeps fixed scroll height independent of expansion`() {
    #expect(CursorMenuRequestDetailPresentation.scrollHeight == CGFloat(
        CursorMenuRequestDetailPresentation.maxVisibleRequestRows
    ) * CursorMenuRequestDetailPresentation.rowHeight)
}
```

This protects the existing fixed-height behavior.

**Step 4: Verify RED**

Run:

```bash
swift test --filter MenuCardCursorRequestDetailsTests
```

Expected: failure for missing `detailLines`.

---

## Task 4: Implement Click-To-Expand Cursor Menu Rows

**Files:**
- Modify: `Sources/CodexBar/MenuCardTokenDetailsView.swift`
- Modify: `Sources/CodexBarCore/UsageFormatter.swift` if detail-line formatting should move into core

**Step 1: Add detail lines to row presentation**

Update:

```swift
struct CursorMenuRequestRowPresentation: Equatable, Identifiable {
    let id: String
    let primaryLeft: String
    let primaryRight: String
    let secondaryLeft: String
    let secondaryRight: String?
    let detailLines: [String]
    let help: String
}
```

Build `detailLines` from `UsageFormatter.cursorRequestDetailLines(...)`. Set `help` to `detailLines.joined(separator: "\n")` so hover remains a best-effort duplicate of the click-accessible content.

**Step 2: Add expansion state**

In `TokenUsageDetailLinesView`, add:

```swift
@State private var expandedRequestID: String?
```

**Step 3: Make rows buttons**

Wrap each row in a `Button` or `.contentShape(Rectangle()).onTapGesture`:

```swift
.contentShape(Rectangle())
.onTapGesture {
    self.expandedRequestID = self.expandedRequestID == row.id ? nil : row.id
}
```

Prefer `onTapGesture` to avoid button styling inside an `NSMenu` row unless tests/manual validation indicate it is inaccessible.

**Step 4: Render expanded detail block**

Below the two-line compact row:

```swift
if self.expandedRequestID == row.id {
    VStack(alignment: .leading, spacing: 2) {
        ForEach(row.detailLines, id: \.self) { detail in
            Text(detail)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    .padding(.top, 4)
}
```

Keep styling muted with `MenuHighlightStyle.secondary(self.isHighlighted)`.

**Step 5: Keep hover help as bonus**

Leave `.help(row.help)` on the outer row. It is no longer relied on for access.

**Step 6: Prevent long detail lines from breaking layout**

Use:

```swift
.frame(maxWidth: .infinity, alignment: .leading)
.lineLimit(2)
.truncationMode(.middle)
```

Do not let expanded text widen the menu beyond the existing menu card width.

**Step 7: Verify GREEN**

Run:

```bash
swift test --filter MenuCardCursorRequestDetailsTests
```

Expected: all pass.

---

## Task 5: Wire Composer Estimates Into Widget And Cycle Totals

**Files:**
- Modify: `Tests/CodexBarTests/CursorWidgetSnapshotTests.swift`
- Modify: `Tests/CodexBarTests/WidgetSnapshotTests.swift`
- Modify: `Sources/CodexBarCore/WidgetSnapshot.swift`
- Modify: `Sources/CodexBar/UsageStore+WidgetSnapshot.swift`
- Modify: `Sources/CodexBarWidget/CodexBarWidgetViews.swift`

**Step 1: Add widget test for Composer exact row**

Seed a Cursor snapshot with a Composer 2.5 exact breakdown and assert:

- row `compactModel == "Composer 2.5"`
- row `estimateText` starts with `Est.`
- token usage has exact `sessionCostUSD` for exact-only rows or approximate `sessionCostText` for range summaries

**Step 2: Add widget test for Composer total-only row**

Seed total-only Composer row and assert:

- row estimate starts with `Approx.`
- cycle total uses approximate text without claiming exactness

**Step 3: Add snapshot schema tests**

In `WidgetSnapshotTests`, add:

- a new-field round-trip test proving `sessionCostText` encodes/decodes
- a legacy decode test proving snapshots without `sessionCostText` still decode and render from `sessionCostUSD`

**Step 4: Implement aggregation support**

Add a helper:

```swift
public static func summarizedEstimate(for requests: [CursorRecentRequest]) -> CursorRequestCostSummary?
```

Use it for menu/widget cycle text instead of `summedUSD(for:)`.

For WidgetKit, avoid showing approximate ranges as exact numeric costs. Extend the snapshot summary with a backward-compatible optional display override:

```swift
public let sessionCostText: String?
```

Widget rendering should prefer `sessionCostText` when present, then fall back to the existing numeric `sessionCostUSD` path for exact-only totals. Existing callers that only know `sessionCostUSD` continue to compile after adding default initializer values.

Update every widget view call site that displays token summary cost text so approximate Cursor ranges use `sessionCostText`; non-Cursor providers should keep the existing exact numeric path unchanged.

**Step 5: Verify**

Run:

```bash
swift test --filter CursorWidgetSnapshotTests
swift test --filter WidgetSnapshotTests
```

Expected: all pass.

---

## Task 6: Update Documentation And Propagation References

**Files:**
- Modify: `docs/cursor.md`
- Modify: `docs/widgets.md`
- Modify: `docs/plans/2026-06-06-cursor-legacy-request-cost-details.md`
- Modify this plan if implementation decisions change during review

**Step 1: Update Cursor docs**

Document:

- Composer 2.5 Fast/Standard pricing source
- raw `composer-2.5` defaults to Fast
- total-only Composer rows show approximate/range estimate
- click-to-expand menu rows are primary detail surface
- hover is best-effort only

**Step 2: Update widget docs**

Document:

- widgets show compact estimates only
- widgets can show `Approx. $low-$high` from `sessionCostText` without requiring hover or expansion
- no hover/expansion in WidgetKit
- menu is the place for expanded per-request detail

**Step 3: Propagation search**

Run:

```bash
rg -n "composer-2\\.5|Composer 2.5|Partial|hover|\\.help|cursorRequestHelpText|summedUSD|approximateTotalOnly" Sources Tests docs
```

Expected: no stale docs claiming Composer is unavailable; no tests expecting `composer-2.5` to be unpriced.

---

## Task 7: Final Verification And App Relaunch

**Files:**
- No new source files expected beyond tasks above.

**Step 1: Focused tests**

Run:

```bash
swift test --filter CursorModelNormalizerTests
swift test --filter CursorRequestCostEstimatorTests
swift test --filter MenuCardCursorRequestDetailsTests
swift test --filter CursorWidgetSnapshotTests
swift test --filter WidgetSnapshotTests
```

Expected: all pass.

**Step 2: Lint/check**

Run:

```bash
pnpm check
```

Expected: SwiftFormat reports no formatting changes needed; SwiftLint reports 0 violations.

**Step 3: Rebuild and restart**

Run:

```bash
./Scripts/compile_and_run.sh
```

Expected: production build/package succeeds and the script prints `OK: CodexBar is running.`

**Step 4: Manual validation**

Open CodexBar menu and inspect Cursor:

- Composer 2.5 rows show `Est.` or `Approx.` instead of blank cost.
- Cycle line includes Composer estimates in the total.
- Clicking a request row expands details.
- Clicking the same row collapses it.
- Expanding one row does not break the fixed-height scroll region.
- Hover is no longer required to see details.

---

## Risks And Open Decisions

- Cursor does not currently expose whether a total-only Composer token count is input-heavy or output-heavy. The safest UI is a range (`Approx. $low-$high`), not a single exact dollar amount.
- The current snapshot model only supports a single `sessionCostUSD`; this plan resolves that by adding a backward-compatible `sessionCostText` override so approximate ranges are never displayed as exact values.
- `NSMenu` plus SwiftUI `onTapGesture` should work, but manual validation is required because AppKit menu event routing can be odd inside hosted scroll views.
- The repo currently has many unrelated dirty files. Implementation must stage only files changed for this plan.
