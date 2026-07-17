# Cursor Request Row Display Semantics Fix Plan

## Problem

The live Cursor widget is still showing misleading per-request rows:

- GPT rows display `Req 2`.
- GPT rows with only total/partial token counts display an unrealistic range such as `Approx. $10.46-$627.36`.

Live snapshot evidence from
`/Users/valsaraj/Library/Group Containers/Y5PE65HELJ.com.steipete.codexbar/widget-snapshot.json`:

```text
gpt-5.5-extra-high | tokens=20912049 | requests=2 | estimate=Approx. $10.46-$627.36
gpt-5.5-high       | tokens=219058   | requests=2 | estimate=Approx. $0.11-$6.57
```

The current parser maps Cursor's `requestsCosts` field directly into `CursorRecentRequest.requests`:

```swift
if let costs = event.requestsCosts, costs > 0 {
    return max(1, Int(costs.rounded()))
}
```

That makes the row label read as though there were two request events. In the Cursor dashboard, each row is one usage
event; `requestsCosts` is a weighted quota/request cost for the plan, not the row count.

For GPT total-only or partial rows, Cursor does not expose a complete input/output/cache split. CodexBar currently
computes the full possible OpenAI cost range from all tokens as input/cache-read to all tokens as output. The upper bound
is not useful for Cursor dashboard rows because `$624`-style all-output scenarios are not realistic for these events.
It looks wrong because it is presented as if it were a plausible estimate.

## Goals

1. Make compact request rows display the event count, not the weighted request cost.
2. Preserve weighted request cost data for summaries and expanded details where it is useful.
3. Keep Cursor legacy quota messaging request-based.
4. Make total-only/partial GPT estimates less misleading while still exposing the uncertainty.
5. Add regression coverage using a GPT usage event with `requestsCosts: 2`.

## Non-Goals

- Do not change the top-level Cursor `/api/usage` request quota (`Requests: used / limit`).
- Do not invent an exact GPT cost when Cursor only exposes total/partial tokens.
- Do not change model pricing rates.
- Do not remove estimates for exact breakdown rows.

## Design

Add separate semantics to `CursorRecentRequest`:

- `requests`: the number of visible request events represented by the row. For one Cursor usage-event row this should be
  `1`, even when `requestsCosts` is `2`.
- `requestCost`: optional weighted Cursor request cost from `requestsCosts`.

Add separate semantics to `CursorRangeUsageSummary`:

- Keep `requests` as visible event count if existing call sites expect event counts.
- Add `weightedRequestCost` as the sum of `CursorRecentRequest.requestCost ?? Double(request.requests)`.
- Menu summary lines that are meant to mirror Cursor legacy quota should read from `weightedRequestCost`.
- Compact per-row `Req N` labels should read from `requests`.

Update parsing:

- `recentRequest(from:)` should set `requests: 1` whenever an event is accepted.
- Store `event.requestsCosts` as `requestCost` after clamping invalid/non-positive values to `nil`.
- Keep zero-token rows when `requestsCosts` exists, because they still represent one usage event.

Update aggregation:

- `CursorRangeUsageSummary.requests` should represent accepted usage-event row count.
- `CursorRangeUsageSummary.weightedRequestCost` should represent plan request cost.
- Rewire both Cursor menu summary consumers in `Sources/CodexBar/MenuCardView.swift`:
  - the structured range path that currently reads `summary.requests`
  - the fallback range path that currently reduces `row.requests`
- Both paths should use a shared weighted request-cost helper so quota-style `Requests: N` summary text still matches
  Cursor legacy quota semantics after compact rows switch to event counts.
- Widget compact rows should continue receiving the event-count `requests` field only; the widget does not need weighted
  request cost unless a future UI explicitly displays it.

Update compact row display:

- Menu and widget compact rows should show `Req 1` for a single usage-event row.
- If a row has `requestCost` greater than `1`, expose it in expanded detail/help as `Request cost: 2`, not in the compact
  `Req` label.

Update total-only/partial GPT estimate behavior:

- Add a representable estimate state for one-sided OpenAI estimates, for example
  `CursorRequestCostEstimate.Confidence.approximateLowerBound`.
- Add a one-sided aggregate contract to `CursorRequestCostSummary`:
  - exact rows continue accumulating into `exactUSD`
  - two-sided approximate rows continue accumulating into `lowerBoundUSD` and `upperBoundUSD`
  - one-sided rows accumulate into `lowerBoundUSD` and leave `upperBoundUSD` nil, or set an explicit
    `containsLowerBoundOnly` flag; the formatter must treat that state as lower-bound-only
- Add formatter paths in `UsageFormatter.cursorEstimateText` and `cursorEstimatedTotalText` for one-sided values.
- Stop using the "all tokens as output" upper bound for OpenAI/Codex total-only estimates.
- For OpenAI rows without a complete breakdown, compute a conservative local estimate from the best available input-side
  rate:
  - cache-read rate when Cursor exposes cache-read evidence
  - normal input rate when Cursor exposes no cache-read evidence
- Mark the estimate as approximate/lower-bound in text, not exact.
- Compact menu/widget rows should show a bounded label such as `Approx. $10.46+` or `Est. >= $10.46`, never
  `$10.46-$627.36`.
- Aggregate Cursor range summaries containing any one-sided OpenAI estimates should also render a one-sided total such as
  `Approx. $94.61+`, not a two-sided range.
- `Sources/CodexBar/UsageStore+WidgetSnapshot.swift` must preserve that one-sided aggregate text in
  `WidgetSnapshot.TokenUsageSummary.sessionCostText`; this is the live `widget-snapshot.json` path where the bad
  `$low-$high` string was observed.
- Expanded detail/help should show:
  - the conservative estimate
  - that Cursor did not expose complete input/output/cache split
  - that output tokens would cost more if present, but CodexBar is not displaying an unrealistic all-output upper bound
  - the estimate is not Cursor billing
  - the legacy plan is request-based

This keeps the widget readable and prevents the wide range from looking like a precise charge.

## Tests

Add focused tests:

- `CursorStatusProbeUsageSummaryTests`
  - A GPT usage event with `requestsCosts: 2` decodes to `CursorRecentRequest.requests == 1`.
  - The same row stores `requestCost == 2`.
  - Range summary `requests` counts one accepted event.
  - Range summary `weightedRequestCost` counts weighted request cost as `2`.
- `MenuCardCursorRequestDetailsTests`
  - Compact row shows `Req 1`.
  - Expanded/help details include `Request cost: 2` when present.
  - Range summary line uses `weightedRequestCost` when showing quota-like request totals.
- `CursorWidgetSnapshotTests`
  - Widget detail for `gpt-5.5-extra-high` with `requestsCosts: 2` renders/stores `requests == 1`.
  - Compact estimate for OpenAI total-only/partial row renders a conservative one-sided estimate, not the long
    `$low-$high` range.
  - The persisted widget snapshot top-level `TokenUsageSummary.sessionCostText` for a GPT lower-bound-only aggregate is
    one-sided, for example `Approx. $10.46+`, and never contains a hyphenated dollar range.
- `CursorRequestCostEstimatorTests`
  - OpenAI total-only/partial estimates no longer use all-output upper bounds.
  - OpenAI total-only/partial estimates use the new one-sided confidence/state.
  - Summarized estimates containing one-sided estimates render one-sided aggregate totals.
  - The explanation states the estimate is conservative/lower-bound and incomplete.
- `CodexBarWidgetProviderTests`
  - Widget row meta text contains `Req 1` for a detail with `requests: 1`.

## Docs

Update:

- `docs/cursor.md`: document the distinction between per-row `Req 1` and weighted `requestsCosts`.
- `docs/widgets.md`: document that WidgetKit compact rows keep the event-count label and avoid unrealistic all-output GPT
  ranges.

## Verification

Run:

```bash
swift test --filter "CursorStatusProbeUsageSummaryTests|MenuCardCursorRequestDetailsTests|CursorWidgetSnapshotTests|CodexBarWidgetProviderTests|CursorRequestCostEstimatorTests"
./Scripts/lint.sh format
swift test --filter "CursorStatusProbeUsageSummaryTests|MenuCardCursorRequestDetailsTests|CursorWidgetSnapshotTests|CodexBarWidgetProviderTests|CursorRequestCostEstimatorTests|CursorModelNormalizerTests"
pnpm check
./Scripts/compile_and_run.sh
```

After rebuild, inspect the live widget snapshot again and confirm:

- GPT rows store/display `requests: 1`.
- GPT total-only/partial compact rows do not show the long approximate dollar range.
- Expanded details still expose the weighted request cost and the incomplete-estimate caveat.
