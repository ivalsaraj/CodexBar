# Cursor Legacy Request Cost Details Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Improve Cursor legacy-plan request details so the menu/widget shows compact model, time, token spend, numeric request count, token breakdown, and optional estimated model cost without implying Cursor is billing the legacy plan by dollars.

**Architecture:** Preserve request count as the primary quota truth for legacy Cursor plans. Extend the existing Cursor usage-event pipeline to keep token breakdowns, normalize raw Cursor model strings for compact display, and calculate best-effort model-cost estimates by extending the existing `CostUsagePricing` source of truth only when a known pricing rule and sufficient breakdown data exist. Render compact rows in both the macOS menu and WidgetKit Cursor request lists, with full model/breakdown/estimate details exposed through hover help where the platform supports it.

**Tech Stack:** Swift 6.2, Swift Testing, SwiftUI, AppKit `NSMenuItem`/`NSHostingView`, WidgetKit where current Cursor snapshot rows are rendered, existing Cursor cookie/API fetcher, SwiftPM.

---

## Research Snapshot

- Cursor legacy request-backed plans must keep `requestsCosts`/request count as the quota display. The cost estimate is diagnostic only.
- Cursor's dashboard usage-events endpoint already returns per-request rows through `usageEventsDisplay`. Local code decodes `inputTokens`, `outputTokens`, `cacheReadTokens`, `cacheWriteTokens`, and `totalTokens`, but `CursorRecentRequest` currently stores only total `tokens`.
- Cursor docs state users can view usage and token breakdowns on the dashboard, and that direct model/Max usage can be based on provider API prices. Legacy team-style included usage can still be request-count based.
- Anthropic publishes separate rates for base input, 5-minute cache writes, 1-hour cache writes, cache hits/refreshes, and output. Cursor currently exposes one `cacheWriteTokens` bucket in decoded events, not the cache-write duration/tier, so Claude rows with nonzero cache writes cannot be labeled exact unless Cursor later exposes that missing dimension. Current Claude Opus 4.8/4.7/4.6 rows are flat across the 1M context window at standard pricing; no long-context surcharge applies for those rows today.
- OpenAI and Google pricing prove the estimator must support tiered pricing, cached input, and thinking tokens/output semantics. Google Gemini Pro-family pricing can vary above a prompt-size threshold, and OpenAI publishes separate short/long context columns for some models.
- Thinking effort must not get an invented multiplier. If the provider prices effort differently, encode that explicit pricing rule. Otherwise effort affects cost only through the actual token counts Cursor reports.

Sources checked on 2026-06-06:
- Cursor pricing/docs: `https://docs.cursor.com/account/pricing`, `https://docs.cursor.com/models`
- Anthropic pricing: `https://platform.claude.com/docs/en/about-claude/pricing?selectAccount=true`
- OpenAI pricing: `https://developers.openai.com/api/docs/pricing`
- Google Gemini pricing: `https://ai.google.dev/gemini-api/docs/pricing`

2026-06-07 superseding decision:
- Cursor still does not expose the Anthropic cache TTL, but CodexBar now defaults Claude `cacheWriteTokens` to Anthropic's
  5-minute cache-write rate and states that assumption in help text. `Partial` is reserved for genuinely incomplete
  lower-bound estimates rather than normal Claude cache-write rows.
- Cursor menu/widget cycle-token summaries can include a summed local estimate from recent request rows. This remains
  diagnostic only; legacy Cursor quota display remains request-based.

## Current State

- `Sources/CodexBarCore/Providers/Cursor/CursorStatusProbe.swift` decodes `CursorUsageEventTokenUsage` with:
  - `inputTokens`
  - `outputTokens`
  - `cacheReadTokens`
  - `cacheWriteTokens`
  - `totalTokens`
- `CursorStatusProbe.recentRequest(from:)` collapses breakdown into one total through `tokenSpend(for:)`.
- `Sources/CodexBarCore/Providers/Cursor/CursorRecentRequest.swift` stores only:
  - `timestamp`
  - `model`
  - `tokens`
  - `requests`
- `Sources/CodexBar/MenuCardTokenDetailsView.swift` formats each request as one string. Long model names consume most of the row width.
- `Sources/CodexBarWidget/CodexBarWidgetViews.swift` renders WidgetKit Cursor rows through `CursorWidgetRequestPresentation` and `CursorRequestDetailsView`; it is a separate consumer from the menu.
- `Sources/CodexBar/UsageStore+WidgetSnapshot.swift` maps `CursorRecentRequest` into `WidgetSnapshot.CursorRequestDetail` and currently filters out rows where `row.tokens <= 0`.
- `Sources/CodexBarCore/Vendored/CostUsage/CostUsagePricing.swift` already contains model normalization and threshold/cache-aware pricing for Codex and Claude cost scanning. Cursor estimates should reuse or extend that source of truth instead of creating a second pricing catalog.
- The existing fixed-height scroll work should stay intact. This plan changes row content and detail metadata, not the core scroll mechanism.
- The repository is dirty with many user/previous-session changes. Implementation must stage only files touched by this plan.

## Non-Negotiable Product Contract

- For Cursor legacy request plans, `Requests: used / limit` remains the primary quota line.
- Per-request `Req N` remains numeric and visible in the compact row.
- Do not show Cursor dashboard `kind`/`Type`.
- Do not call pricing docs from the running menu/widget.
- Do not imply estimated cost is billed cost. Use labels like `Est.` and hover text like `model-cost estimate; legacy quota is request-based`.
- Unknown or proprietary Cursor models must still render cleanly with cost unavailable.
- If only `totalTokens` exists and breakdown fields are absent, show total tokens and mark breakdown/cost confidence as total-only or unavailable.
- A request can have an exact token breakdown but still have a partial or unavailable cost estimate when pricing-relevant
  parts are missing. Claude `cacheWriteTokens` default to Anthropic's 5-minute cache-write rate because Cursor does not
  expose cache TTL metadata.
- Request-count-only rows with zero tokens must not disappear from legacy request-plan UI. They should render `0 tokens` or `tokens unavailable` according to the formatter decision made in Task 8.

---

## Task 1: Add RED Tests For Preserving Cursor Token Breakdown

**Files:**
- Modify: `Tests/CodexBarTests/CursorStatusProbeUsageSummaryTests.swift`
- Modify: `Tests/CodexBarTests/Fixtures/cursor-usage-events.json`
- Modify: `Tests/CodexBarTests/WidgetSnapshotTests.swift`

**Step 1: Add a parser test with full token breakdown**

Add a test event with:

```swift
CursorUsageEvent(
    timestamp: "1770201720000",
    model: "claude-opus-4-8-thinking-xhigh",
    requestsCosts: 1,
    tokenUsage: CursorUsageEventTokenUsage(
        inputTokens: 120_000,
        outputTokens: 42_000,
        cacheReadTokens: 34_600_000,
        cacheWriteTokens: 210_000,
        totalTokens: nil))
```

Expected assertions:
- one `CursorRecentRequest` is produced
- `tokens == 34_972_000`
- `requests == 1`
- breakdown preserves input/output/cache read/cache write
- `hasExactBreakdown == true` or equivalent status exists

**Step 2: Add a parser test with total-only usage**

Add a second event with `totalTokens: 35_000_000` and all breakdown parts `nil`.

Expected assertions:
- row still renders with total tokens
- breakdown is marked total-only/unavailable
- cost estimate is not exact

**Step 3: Add a parser test with partial token parts**

Add an event with some, but not all, part fields present, for example `inputTokens` and `outputTokens` without cache buckets.

Expected assertions:
- row still renders with the sum of known parts or explicit `totalTokens` when present
- breakdown is marked partial/incomplete, not exact
- estimator does not treat missing optional buckets as zero unless a fixture or Cursor API contract verifies that omission means zero

**Step 4: Add a widget snapshot compatibility test**

Encode/decode a snapshot containing a Cursor request with breakdown metadata.

Expected assertions:
- new fields survive round trip
- old JSON without the new fields still decodes
- request count and total tokens remain unchanged

**Step 5: Verify RED**

Run:

```bash
swift test --filter CursorStatusProbeUsageSummaryTests
swift test --filter WidgetSnapshotTests
```

Expected: fail because `CursorRecentRequest` has no breakdown fields.

---

## Task 2: Add Core Cursor Request Breakdown Models

**Files:**
- Modify: `Sources/CodexBarCore/Providers/Cursor/CursorRecentRequest.swift`

**Step 1: Add a breakdown value type**

Add:

```swift
public struct CursorRecentRequestTokenBreakdown: Codable, Equatable, Sendable {
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let cacheReadTokens: Int?
    public let cacheWriteTokens: Int?
    public let totalTokens: Int
    public let confidence: Confidence

    public enum Confidence: String, Codable, Equatable, Sendable {
        case exactBreakdown
        case partialBreakdown
        case totalOnly
        case empty
    }
}
```

Implementation notes:
- Clamp negative token fields to zero if Cursor ever sends invalid values.
- `totalTokens` should equal explicit `totalTokens` when present; otherwise sum known parts.
- `exactBreakdown` means all pricing-relevant part fields currently decoded from Cursor are present: `inputTokens`, `outputTokens`, `cacheReadTokens`, and `cacheWriteTokens`. Explicit zero values count as present; missing fields do not.
- `partialBreakdown` means at least one part field exists but one or more pricing-relevant part fields are missing. Preserve the known values, but downstream cost estimation must not assume missing buckets are zero unless a fixture or Cursor API contract verifies that omission means zero.
- `totalOnly` means `totalTokens` exists and no part fields exist.

**Step 2: Extend `CursorRecentRequest`**

Add:

```swift
public let tokenBreakdown: CursorRecentRequestTokenBreakdown?
```

Keep the existing initializer source-compatible by giving `tokenBreakdown` a default of `nil`.

**Step 3: Run focused tests**

Run:

```bash
swift test --filter CursorStatusProbeUsageSummaryTests
swift test --filter WidgetSnapshotTests
```

Expected: model compile errors move to parser/plumbing.

---

## Task 3: Preserve Breakdown In Cursor Usage Event Mapping

**Files:**
- Modify: `Sources/CodexBarCore/Providers/Cursor/CursorStatusProbe.swift`
- Modify: `Tests/CodexBarTests/CursorStatusProbeUsageSummaryTests.swift`

**Step 1: Add a mapping helper**

Add a helper near `tokenSpend(for:)`:

```swift
private static func requestTokenBreakdown(
    for usage: CursorUsageEventTokenUsage?
) -> CursorRecentRequestTokenBreakdown?
```

Rules:
- return `nil` when `usage == nil`
- if all pricing-relevant part fields exist, store each clamped part and mark `confidence == .exactBreakdown`
- if only some part fields exist, store known clamped parts, use explicit `totalTokens` when present or sum known parts otherwise, and mark `confidence == .partialBreakdown`
- if only `totalTokens` exists, store total with `confidence == .totalOnly`
- if `usage` exists but all fields are absent, return `.empty` with total `0` only if the existing parser needs to keep a request-count-only row

**Step 2: Update `recentRequest(from:)`**

Use the helper:

```swift
let breakdown = Self.requestTokenBreakdown(for: event.tokenUsage)
let tokens = breakdown?.totalTokens ?? Self.tokenSpend(for: event.tokenUsage) ?? 0
return CursorRecentRequest(
    timestamp: timestamp,
    model: model,
    tokens: tokens,
    requests: requests,
    tokenBreakdown: breakdown)
```

**Step 3: Verify**

Run:

```bash
swift test --filter CursorStatusProbeUsageSummaryTests
```

Expected: pass for parser tests.

---

## Task 4: Add Cursor Model Normalizer

**Files:**
- Create: `Sources/CodexBarCore/Providers/Cursor/CursorModelNormalizer.swift`
- Create or Modify: `Tests/CodexBarTests/CursorModelNormalizerTests.swift`

**Step 1: Write RED normalizer tests**

Cover:

```swift
claude-opus-4-8-thinking-xhigh -> Opus 4.8, provider anthropic, effort xhigh, pricing key claude-opus-4-8
claude-opus-4-7-thinking-max -> Opus 4.7, provider anthropic, effort max, pricing key claude-opus-4-7
claude-sonnet-4-6-thinking -> Sonnet 4.6, provider anthropic, effort unknown/standard, pricing key claude-sonnet-4-6
composer-2.5 -> Composer 2.5, provider cursor, pricing key composer-2.5-fast (or -standard); other composer versions have no pricing key
gpt-5.4 -> GPT-5.4, provider openai, pricing key gpt-5.4 only if existing `CostUsagePricing` supports it
gemini-3.1-pro-preview -> Gemini 3.1 Pro Preview, provider google, pricing key nil until Gemini pricing is added to the shared pricing source
```

Expected:
- raw model is always preserved
- display name is compact
- unknown model returns a humanized display name and `pricingKey == nil`
- effort never changes pricing key unless a future explicit pricing rule needs it
- no model gets a non-nil pricing key unless Task 5 provides or already has shared pricing coverage for that exact normalized key

**Step 2: Implement `CursorNormalizedModel`**

Add:

```swift
public enum CursorModelProvider: String, Codable, Equatable, Sendable {
    case anthropic
    case openai
    case google
    case cursor
    case unknown
}

public struct CursorNormalizedModel: Equatable, Sendable {
    public let rawName: String
    public let displayName: String
    public let provider: CursorModelProvider
    public let family: String?
    public let version: String?
    public let mode: String?
    public let effort: String?
    public let pricingKey: String?
}
```

Use small regex/string parsing helpers. Keep the parser tolerant; do not maintain a brittle "all Cursor models" allowlist.

Pricing-key rule:
- `CursorModelNormalizer` may own Cursor-specific display cleanup, such as removing `thinking-xhigh` from visible labels.
- It must not independently decide whether a pricing key is billable.
- For Claude/OpenAI pricing keys, delegate through shared `CostUsagePricing` normalization/coverage helpers, adding narrowly scoped helper APIs there if needed, so display normalization cannot drift from pricing coverage.
- If shared pricing coverage returns no supported key, `pricingKey` must be `nil`.

**Step 3: Verify**

Run:

```bash
swift test --filter CursorModelNormalizerTests
```

Expected: pass.

---

## Task 5: Extend Shared Pricing Infrastructure For Cursor Estimates

**Files:**
- Modify: `Sources/CodexBarCore/Vendored/CostUsage/CostUsagePricing.swift`
- Modify: `Tests/CodexBarTests/CostUsagePricingTests.swift`

**Step 1: Write RED shared-pricing tests**

Cover:
- Anthropic Claude Opus 4.8 normalization and rate math
- Anthropic Claude Opus 4.7 normalization and rate math
- Anthropic cache read pricing
- existing OpenAI short/long context rule shape if Cursor normalizer assigns an OpenAI pricing key
- threshold pricing behavior through existing `CostUsagePricing` tier support
- unknown model returns no estimate

**Step 2: Extend `CostUsagePricing` instead of creating a parallel catalog**

Implementation notes:
- Add missing Claude model aliases required by observed Cursor strings, including `claude-opus-4-7` and `claude-opus-4-8`.
- Keep existing per-token units and threshold logic unless a broader cost-pricing refactor is explicitly approved.
- Keep this layer limited to normalization, pricing catalog coverage, and rate math. Do not add Cursor-specific confidence, partial/unavailable estimate policy, or request-plan semantics to `CostUsagePricing`.
- Add a narrowly scoped pricing metadata helper if needed, for example `claudePricingCapabilities(model:)`, that can tell callers whether Claude pricing distinguishes cache-write tiers. The helper must not know about Cursor; it only exposes provider pricing shape so `CursorRequestCostEstimator` can decide confidence safely.
- Add source/verified-date comments near updated rate groups if the file does not already have metadata fields.
- Do not add a network updater.
- Do not add Gemini pricing in this task unless the implementation also adds full Gemini pricing tests and shared estimator support. Until then Gemini models may have compact display names but `pricingKey == nil`.
- Composer 2.5 pricing is now covered locally (see `docs/plans/2026-06-08-cursor-composer-pricing-expanded-details.md`).

**Step 3: Refresh stale Claude threshold assumptions**

Compare existing Claude 4.6+ threshold entries with the verified Anthropic docs. If official docs say a model has no long-context surcharge at standard pricing, update the shared pricing entry and tests in this task. Do not silently preserve stale threshold values.

**Step 4: Verify**

Run:

```bash
swift test --filter CostUsagePricingTests
```

Expected: shared pricing tests pass.

---

## Task 6: Add Legacy-Aware Request Cost Estimator

**Files:**
- Create: `Sources/CodexBarCore/Providers/Cursor/CursorRequestCostEstimator.swift`
- Modify: `Tests/CodexBarTests/CursorRequestCostEstimatorTests.swift`

**Step 1: Add estimate result type**

Write RED tests in `CursorRequestCostEstimatorTests` for:
- exact estimates when a known model has complete input/output/cache-read data and no ambiguous cache-write tokens
- partial breakdowns returning no exact estimate
- exact Claude estimates when `cacheWriteTokens > 0`, priced with the 5-minute cache-write default
- total-only breakdown returning no exact estimate
- unknown/proprietary models returning no estimate
- the legacy request-plan disclaimer being present in every explanation

Add:

```swift
public struct CursorRequestCostEstimate: Equatable, Sendable {
    public let usd: Decimal?
    public let confidence: Confidence
    public let pricingKey: String?
    public let pricingSource: String?
    public let explanation: String

    public enum Confidence: String, Equatable, Sendable {
        case exactBreakdown
        case partialMissingCacheWriteTier
        case totalOnlyUnavailable
        case partialBreakdownUnavailable
        case unknownModel
        case missingPricing
        case missingBreakdown
    }
}
```

**Step 2: Add formula**

For exact breakdown with sufficient pricing metadata:

```text
inputCost = inputTokens / 1_000_000 * inputRate
outputCost = outputTokens / 1_000_000 * outputRate
cacheReadCost = cacheReadTokens / 1_000_000 * cacheReadRate
cacheWriteCost = cacheWriteTokens / 1_000_000 * cacheWriteRate; Cursor Claude rows use the 5-minute cache-write default
total = sum
```

Fallbacks:
- if `pricingKey == nil`: `.unknownModel`
- if `pricingKey` has no shared pricing rule: `.missingPricing`
- if breakdown is nil: `.missingBreakdown`
- if breakdown is partial/incomplete: `.partialBreakdownUnavailable`
- if breakdown is total-only: `.totalOnlyUnavailable` unless a future requirement explicitly allows rough blended estimates
- if `cacheWriteTokens > 0` for Claude, use the 5-minute cache-write default and include the assumption in explanatory UI text
- if the normalized model is display-only, return unavailable even if the raw provider family looks familiar

**Step 3: Keep legacy request-plan labeling in the result**

The explanation must include a stable phrase similar to:

```text
Model-cost estimate only. Cursor legacy quota is request-based.
```

This text will be used in hover/help.

For Claude cache writes, the explanation must state the 5-minute cache-write assumption because Cursor does not expose
cache TTL metadata.

**Step 4: Verify**

Run:

```bash
swift test --filter CursorRequestCostEstimatorTests
swift test --filter CostUsagePricingTests
```

Expected: pass.

---

## Task 7: Add Compact Cursor Request Row Presentation

**Files:**
- Modify: `Sources/CodexBar/MenuCardView.swift`
- Modify: `Sources/CodexBar/MenuCardTokenDetailsView.swift`
- Modify: `Sources/CodexBarCore/UsageFormatter.swift`
- Modify: `Tests/CodexBarTests/MenuCardModelTests.swift`
- Modify: `Tests/CodexBarTests/MenuCardCursorRequestDetailsTests.swift`

**Step 1: Write RED legacy quota precedence tests**

Update menu model tests so a Cursor legacy request-plan snapshot with both `cursorRequests` and `cursorTokenUsage` produces:
- `sessionLine == "Requests: used / limit"` when `cursorRequests.metric == .requests`
- `monthLine == "Cycle: N tokens"` when billing-cycle tokens are available
- both lines still visible when recent request rows exist

The current `UsageMenuCardView.Model.tokenUsageSection` prefers `Cycle: ... tokens` as `sessionLine` whenever cycle tokens are present. This task must change that precedence for request-backed Cursor legacy plans so the request quota remains visually primary.

Update the existing `MenuCardModelTests.cursor model includes billing cycle token usage` expectations from the old `Cycle`-first ordering to the new request-primary ordering.

Token-backed legacy plans may keep `Tokens: used / limit` as the quota line; do not force a request label when `cursorRequests.metric == .tokens`.

**Step 2: Write RED presentation tests**

Expected compact row shape:
- primary left: compact model and effort, for example `Opus 4.8 - xhigh`
- primary right: token count, for example `35M`
- secondary left: time and request count, for example `5:52 PM - Req 1`
- secondary right: estimate, for example `Est. $12.34`, or no value when no honest estimate exists

Expected hover/help content:
- full raw model
- exact date/time
- request count
- token breakdown labels
- cost estimate/explanation
- legacy request-plan disclaimer
- Claude 5-minute cache-write assumption when cache-write tokens are included

**Step 3: Replace string-only presentation with structured rows**

Evolve `CursorMenuRequestDetailPresentation` and update every caller. In particular, `Sources/CodexBar/MenuCardView.swift` currently builds legacy `detailLines` with:

```swift
let presentation = CursorMenuRequestDetailPresentation(...)
let recentLines = presentation.fixedRows + presentation.scrollRows
```

That string concatenation must be removed or replaced with a compatibility fallback before `scrollRows` becomes structured.

Evolve:

```swift
struct CursorMenuRequestDetailPresentation: Equatable {
    let fixedRows: [String]
    let scrollRows: [String]
}
```

into something like:

```swift
struct CursorMenuRequestDetailPresentation: Equatable {
    let fixedRows: [String]
    let requestRows: [CursorMenuRequestRowPresentation]
}

struct CursorMenuRequestRowPresentation: Equatable, Identifiable {
    let id: String
    let primaryLeft: String
    let primaryRight: String
    let secondaryLeft: String
    let secondaryRight: String?
    let help: String
}
```

**Step 4: Render two-line compact rows**

Use `HStack`/`VStack` with fixed alignment so long model names cannot consume the full width. Keep the scroll view's existing fixed height; adjust `rowHeight` for two-line rows.

Rules:
- model display is line-limited
- right-side token/estimate values use monospaced digits if consistent with local style
- row width remains stable
- request rows are not blue full-card selected while scrolling

**Step 5: Add hover/help**

Use SwiftUI `.help(row.help)` first. Only switch to a click-to-expand detail if `.help` is insufficient in manual validation.

**Step 6: Verify focused tests**

Run:

```bash
swift test --filter MenuCardCursorRequestDetailsTests
swift test --filter MenuCardInteractionPolicyTests
```

Expected: pass.

---

## Task 8: Preserve Request-Count Rows And Carry Details Into Widget Snapshot

**Files:**
- Inspect: `Sources/CodexBar/UsageStore+WidgetSnapshot.swift`
- Modify: `Sources/CodexBarCore/WidgetSnapshot.swift`
- Modify: `Sources/CodexBar/UsageStore+WidgetSnapshot.swift`
- Test: `Tests/CodexBarTests/CursorWidgetSnapshotTests.swift`
- Test: `Tests/CodexBarTests/WidgetSnapshotTests.swift`

**Step 1: Inspect current widget data path**

Run:

```bash
rg -n "cursorRecentRequests|cursorRequestDetails|CursorRecentRequest|TokenUsageSummary" Sources/CodexBar Sources/CodexBarCore Sources/CodexBarWidget Tests
```

Expected: identify whether WidgetKit renders request rows from `CursorRecentRequest` directly or from a separate snapshot DTO.

**Step 2: Adjust zero-token row filtering**

Current code filters:

```swift
return !model.isEmpty && row.tokens > 0
```

Change the plan-driven behavior to:
- keep non-empty model rows when `row.requests > 0`, even if `tokens == 0`
- keep token-positive rows as before
- filter rows only when model is empty or both tokens and request count are non-positive

Add tests for:
- zero-token, one-request row survives into the widget snapshot
- zero-token, zero-request row is filtered
- request count remains visible for legacy plans

**Step 3: Add DTO fields for compact details**

Extend `WidgetSnapshot.CursorRequestDetail` only with optional fields needed by the widget:
- compact model display
- optional estimate label or raw estimate fields
- optional breakdown/help text if WidgetKit can surface it

Keep the raw model field for compatibility and diagnostics.

Compatibility rule:
- decoding older widget JSON must continue to work.
- non-Cursor provider snapshots must not gain Cursor-only display data.

**Step 4: Verify**

Run:

```bash
swift test --filter CursorWidgetSnapshotTests
swift test --filter WidgetSnapshotTests
```

Expected: pass.

---

## Task 9: Render Compact Cursor Rows In WidgetKit

**Files:**
- Modify: `Sources/CodexBarWidget/CodexBarWidgetViews.swift`
- Modify: `Tests/CodexBarTests/CodexBarWidgetProviderTests.swift`

**Step 1: Write RED widget presentation tests**

Extend the existing `CursorWidgetRequestPresentation` tests to assert:
- medium widgets still show at most 3 rows
- large widgets still show at most 5 rows
- visible row model text uses compact display, not raw `claude-opus-...`
- request count remains visible for zero-token request-count rows
- optional estimate text appears only when available
- unknown estimates do not render as fake dollars

**Step 2: Update `CursorWidgetRequestPresentation`**

Add a small row presentation DTO parallel to the menu presentation:

```swift
struct Row: Equatable {
    let modelText: String
    let metaText: String
    let tokenText: String
    let estimateText: String?
}
```

Keep selection/hidden-count behavior unchanged.

**Step 3: Update `CursorRequestDetailsView`**

Render compact model text and keep right-side token/request/estimate text from pushing the row wider. WidgetKit has no hover, so keep any breakdown detail out of the visible row unless it fits the compact design.

**Step 4: Verify**

Run:

```bash
swift test --filter CodexBarWidgetProviderTests
swift test --filter CursorWidgetSnapshotTests
```

Expected: pass.

---

## Task 10: Update Cursor Docs

**Files:**
- Modify: `docs/cursor.md`
- Modify: `docs/widgets.md` only if WidgetKit rendering changes

**Step 1: Update Cursor provider docs**

Add:
- legacy request-backed quota remains request-based
- usage-events rows can include token breakdown
- model-cost estimates are local, source-versioned, and diagnostic
- unknown/proprietary models show cost unavailable

**Step 2: Update widget docs if needed**

Only update `docs/widgets.md` if the implementation changes WidgetKit rendering or snapshot fields.

**Step 3: Verify docs references**

Run:

```bash
rg -n "Cursor|legacy|request|token breakdown|estimate|pricing" docs/cursor.md docs/widgets.md
```

Expected: docs mention the new behavior without implying billing changes.

---

## Task 11: Full Verification And App Validation

**Files:**
- No new files unless previous tasks require docs.

**Step 1: Run focused tests**

```bash
swift test --filter CursorStatusProbeUsageSummaryTests
swift test --filter CursorModelNormalizerTests
swift test --filter CursorRequestCostEstimatorTests
swift test --filter MenuCardCursorRequestDetailsTests
swift test --filter CursorWidgetSnapshotTests
swift test --filter WidgetSnapshotTests
swift test --filter CodexBarWidgetProviderTests
swift test --filter CostUsagePricingTests
```

Expected: pass.

**Step 2: Run full test/build loop**

```bash
./Scripts/compile_and_run.sh
```

Expected:
- Swift build passes
- Swift tests pass
- app package is refreshed
- running app uses the rebuilt bundle

**Step 3: Manual UI validation**

With Cursor logged in:
- open the CodexBar menu
- verify `Requests: used / 500` remains visible and primary
- verify `Cycle: N tokens` remains visible
- verify `Range: ...` remains visible
- verify request rows use compact model names
- verify long raw model names appear in hover/help, not as layout-breaking row text
- verify rows scroll when more than visible count exists
- verify hover does not trigger full-card blue selected state that blocks scroll
- verify cost labels say `Est.` or equivalent
- verify unknown pricing displays `Est. $-` or no cost, not a made-up value

**Step 4: Run formatting/lint commands required by repo docs**

```bash
swiftformat Sources Tests
swiftlint --strict
pnpm check
```

Expected:
- pass, or document unavailable tooling precisely if a command is not installed in this repo environment

**Step 5: Propagation search**

Run:

```bash
rg -n "CursorRecentRequest|CursorRecentRequestTokenBreakdown|CursorModelNormalizer|CursorRequestCostEstimate|cursorRecentRequestLine|usageEventsDisplay|requestsCosts" Sources Tests docs
```

Expected:
- all model initializers compile with the new defaulted fields
- no stale string-only formatter assumptions remain in Cursor request UI
- docs match implemented behavior

**Step 6: Commit only plan-related implementation files**

After implementation and verification, stage only files touched by the implementation. Do not stage unrelated dirty worktree files.

Example:

```bash
git add Sources/CodexBarCore/Providers/Cursor/CursorRecentRequest.swift \
  Sources/CodexBarCore/Providers/Cursor/CursorModelNormalizer.swift \
  Sources/CodexBarCore/Providers/Cursor/CursorRequestCostEstimator.swift \
  Sources/CodexBarCore/Vendored/CostUsage/CostUsagePricing.swift \
  Sources/CodexBarCore/Providers/Cursor/CursorStatusProbe.swift \
  Sources/CodexBar/MenuCardView.swift \
  Sources/CodexBar/MenuCardTokenDetailsView.swift \
  Sources/CodexBar/UsageStore+WidgetSnapshot.swift \
  Sources/CodexBarCore/WidgetSnapshot.swift \
  Sources/CodexBarWidget/CodexBarWidgetViews.swift \
  Sources/CodexBarCore/UsageFormatter.swift \
  Tests/CodexBarTests/CursorStatusProbeUsageSummaryTests.swift \
  Tests/CodexBarTests/CursorModelNormalizerTests.swift \
  Tests/CodexBarTests/CursorRequestCostEstimatorTests.swift \
  Tests/CodexBarTests/CostUsagePricingTests.swift \
  Tests/CodexBarTests/MenuCardCursorRequestDetailsTests.swift \
  Tests/CodexBarTests/WidgetSnapshotTests.swift \
  Tests/CodexBarTests/CursorWidgetSnapshotTests.swift \
  Tests/CodexBarTests/CodexBarWidgetProviderTests.swift \
  docs/cursor.md docs/widgets.md
git commit -m "Improve Cursor legacy request cost details"
```

Expected: commit includes only this feature's files.

---

## Open Decisions For The Implementer

- If `.help(...)` does not appear reliably inside the menu, use click-to-expand rows only for Cursor request rows. Do not expand by default.
- If Cursor publishes a direct billable USD field for request rows later, add it as a separate `cursorReportedCostUSD` field and render it differently from local estimates.
- Composer 2.5 now uses published Fast/Standard changelog rates; see the 2026-06-08 composer pricing plan.
- If the plan execution finds the current widget does not render scrollable details because WidgetKit cannot scroll, keep WidgetKit bounded and put richer hover details only in the macOS menu.

## Success Criteria

- Legacy Cursor request quota remains request-based and visually primary.
- Every recent row shows compact model, time, token spend, and numeric request count.
- Token breakdown is preserved when Cursor provides it.
- Cost estimate appears only when the pricing rule and breakdown support it.
- The UI never invents thinking-effort multipliers.
- Long model names no longer consume the whole row.
- Fixed-height scrolling still works for more than the visible row count.
- Unknown models degrade gracefully.
