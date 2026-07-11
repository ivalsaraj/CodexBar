# Cursor Upstream Replay Design

## Goal

Rebuild the current Cursor request-cost and usage-range work on top of `upstream/main` without carrying forward unrelated fork features or regressing upstream Cursor enterprise support.

## Context

`codex/fable5-cursor-estimates` diverged from `upstream/main` at `91146a28`. A direct merge produces 45 conflicts across provider, menu, usage-snapshot, and test infrastructure. The current branch contains custom Codex account, chart, z.ai, OpenCode workspace, and Cursor work; this replay intentionally scopes the first migration to Cursor only.

The selected committed Cursor stack is:

- `992b6157` as the source for request-cost behaviour, but not as a whole cherry-pick because it combines 70 Cursor and OpenCode files.
- `01024560`, `f5c2a138`, `13ff60df`, and `3c33bfeb` for Fable pricing, partial-token estimates, widget estimates, and paginated-event aggregation.
- The uncommitted Cursor usage-range work, including weighted request-cost semantics, conservative GPT lower-bound estimates, and menu range selection.

## Scope

### Included

- Cursor usage-event parsing and aggregation, preserving upstream enterprise overall/pooled usage parsing.
- Cursor model normalization, exact and conservative estimated pricing, and request-row presentation.
- Menu-card request details, Cursor usage-range selection, and WidgetKit summary/detail rendering.
- Focused regression tests and updates to `docs/cursor.md` and `docs/widgets.md`.

### Explicitly Deferred

- Codex multi-account switching and dependent-process diagnostics.
- Provider utilization charts and median reference line.
- z.ai five-hour window changes.
- OpenCode multi-workspace and OpenCode Go changes.
- Other branch-wide backports or shared-default changes.
- `ClickToCopyOverlay` and its all-provider token-error interaction change.

## Decision

Create a new integration branch rooted at `upstream/main`. Port Cursor behaviour as small functional slices, not with `git cherry-pick 992b6157`. Upstream has changed 43 paths touched by that commit, so a whole-commit replay would restore obsolete menu, provider, and OpenCode code.

The port keeps upstream as the authority for shared infrastructure and composes Cursor-specific behaviour into its current seams:

1. Extend the upstream Cursor probe to retain enterprise parsing while collecting paginated usage events into per-range summaries.
2. Add the Cursor-only request-cost model, model normalizer, pricing lookup, and conservative lower-bound estimate state.
3. Feed those details through the current usage snapshot and menu-card models into WidgetKit.
4. Add the selected Cursor range setting and segmented menu control; persist the chosen range to WidgetSnapshot.

## Diagnostics Completeness Contract

Cursor event diagnostics are all-or-nothing. `CursorStatusProbe` will model the page-fetch result explicitly as either
complete events plus their range/raw JSON, or unavailable diagnostics. It creates one deadline before requesting page one
and passes only the remaining time to every event-page request.

- Pages contain 200 events and page 20 is always the final allowed request.
- The first non-`nil` `totalUsageEventsCount` is the authoritative expected total for the whole fetch. Later omitted
  totals retain that value; a later non-`nil` value must match it or diagnostics become unavailable. This prevents
  page-to-page API inconsistencies from being misreported as a complete range.
- With an authoritative expected total, diagnostics are complete only when it is at most 4,000 and the fetched count
  reaches that total. A total above 4,000 is unavailable without requesting page 21.
- Without an advertised total, diagnostics are complete only when a page contains fewer than 200 events. A full twentieth
  page is unavailable.
- A page error, decode error, deadline expiry, or capped/incomplete response is unavailable. `parseUsageSummary` then
  leaves recent requests, range summaries, and request-cost diagnostics absent; it retains independently fetched primary
  quota, token, and legacy request-quota data.
- Menu and widget consumers treat absent diagnostics as unavailable, never as a complete zero-request range.

## Data and Presentation Rules

- A Cursor usage event is one compact `Req 1` row. One canonical row formatter accepts only `requests`; menu and widget
  request rows must use it. `requestsCosts` remains a separate optional weighted request cost used only by
  `CursorRangeUsageSummary.weightedRequestCost` and an explicit expanded `Request cost: N` detail line.
- Exact token breakdowns use exact local pricing. GPT rows with total-only or partial tokens show a conservative lower-bound estimate such as `Approx. $10.46+`; they never present the implausible all-output upper bound.
- Model aliases with effort suffixes normalize only to explicitly priced local keys. `extra-high` is one effort suffix, not part of the pricing key.
- Cursor request-cost estimates are diagnostics, not Cursor billing. Legacy request quota remains request-based.
- The selected Cursor range controls menu-card and persisted widget summary presentation without changing the top-level Cursor API quota.
- Use `upstream/main`'s `CostUsagePricing` as the GPT pricing source of truth: its `gpt-5.5` entry is input `5e-6`,
  cached input `5e-7`, and output `3e-5` USD/token. Before implementation, verify and record the applicable official
  provider pricing source and date for every added or changed model rate, including Fable; tests assert the resulting
  numeric costs rather than only the estimate labels.

## Compatibility Boundaries

- Retain `upstream/main` Cursor enterprise overall/pooled handling when modifying `CursorStatusProbe`.
- Retain upstream's injected `URLSession` initializer and route summary, auth, legacy quota, and every paged usage-event
  request through that instance. The request-body regression test invokes public `fetchWithManualCookies` or `fetch`, not
  a parsing helper, with an injected `URLProtocol`-backed session.
- Do not replace current `UsageSnapshot`, `UsageFetcher`, provider registry, menu controller, or cost scanner structures with versions from the fork.
- Use existing SwiftUI/Observation patterns and focused model-level Swift Testing `@Test` suites rather than live AppKit status-menu tests.
- Fetch Cursor usage events in pages of 200, with a hard cap of 20 pages and one absolute deadline equal to the probe
  timeout (15 seconds by default). Each page request uses only the deadline's remaining time. If the response advertises
  more events than the cap can cover, the count is absent and page 20 is full, a later page fails, or the deadline expires,
  omit request diagnostics rather than present a partial range summary; keep the independently fetched primary quota.

## Acceptance Criteria

- The fresh branch builds and its existing tests pass before the port starts.
- An injected `URLProtocol` test asserts the first and second Cursor usage-event request bodies, then proves that an
  event available only on page two contributes to the range summary. When a later page fails or the total event count
  is absent/excessive, preserve primary quota data, omit partial request diagnostics, and finish the refresh inside the
  15-second overall deadline. Tests assert that page 20 is the final attempted page regardless of an advertised total,
  that a full twentieth page with no total also suppresses partial diagnostics, that page one's total survives a missing
  total on page two, and that conflicting non-`nil` totals suppress diagnostics.
- Cursor events from a complete paginated result contribute to range summaries while enterprise overall/pooled usage remains correct.
- A `requestsCosts: 2` event renders `Req 1`, retains a weighted request cost of `2`, and shows the weighted value only where quota semantics require it.
- Priced GPT/Fable rows display exact or conservative estimates; GPT total-only rows do not render a broad dollar range.
- `gpt-5.5-extra-high` resolves to `gpt-5.5` pricing and displays `extra-high` as effort metadata.
- A fixture produced by the pre-replay WidgetSnapshot schema decodes and renders without dropping existing provider
  entries. A newly persisted snapshot contains the selected Cursor range and its corresponding presentation.
- Menu and widget selection/persistence of the Cursor range work, and all focused tests, `pnpm check`, and `./Scripts/compile_and_run.sh` pass.

## Implementation Sequence

Port only the listed functional slices, with one commit per numbered stage:

1. Create the integration branch at `upstream/main`; run its baseline build, targeted Cursor tests, and snapshot decode
   test before adding any fork code.
2. Port probe/models/pricing: `CursorStatusProbe.swift`, `CursorRequestUsage.swift`, `CursorRecentRequest.swift`,
   `CursorTokenUsage.swift`, `CursorModelNormalizer.swift`, `CursorRequestCostEstimator.swift`, and `CostUsagePricing.swift`;
   add Swift Testing `@Test` coverage for the injected-session paging contract, the complete/unavailable result, retained
   first-page total when page two omits it, conflicting totals, model normalization, and numeric rates.
3. Port snapshot/widget compatibility: `UsageFetcher.swift`, `UsageStore+WidgetSnapshot.swift`, `WidgetSnapshot.swift`,
   `CodexBarWidgetViews.swift`, and their focused tests. Preserve every Cursor field through
   `UsageSnapshot.withIdentity`, including `cursorRangeSummaries`, before decoding a pre-replay fixture and persisting the
   new selected range and request-detail shape.
4. Port menu/settings range UI: `UsageFormatter.swift`, `MenuCardView.swift`, `MenuCardTokenDetailsView.swift`,
   `MenuCardTokenUsageContentView.swift`, `MenuCardTokenUsageTitleRow.swift`, `StatusItemController+Menu.swift`,
   `StatusItemController+MenuCardInteractionPolicy.swift`, `StatusItemController+CursorUsageRange.swift`,
   `SettingsStore+Defaults.swift`, `SettingsStore+MenuObservation.swift`, `SettingsStoreState.swift`, `SettingsStore.swift`,
   and focused menu/settings tests. From `MenuCardTokenUsageContentView.swift`, port only the Cursor range-picker state and
   callback, wired through `selectCursorUsageRange`; preserve the interaction policy's check across every range presentation
   so a newly selected range with many rows remains scrollable. Do not port the overlay block or create
   `ClickToCopyOverlay.swift`.
5. Update `docs/cursor.md` and `docs/widgets.md`, run the focused suite, `pnpm check`, and
   `./Scripts/compile_and_run.sh`; obtain a final `gpt-5.6-terra` Codex review approval before handoff.
