# Cursor GPT Pricing Estimates Implementation Plan

## Problem

Cursor request rows for GPT/OpenAI models can render without an estimated cost even when OpenAI pricing is available.
The likely causes are:

- Cursor model names may include effort suffixes such as `gpt-5.5-medium`, `gpt-5.4-high`, or `gpt-5.4-mini-medium`,
  while `CursorModelNormalizer` currently passes the whole string to `CostUsagePricing.supportedCodexPricingKey`.
- The shared pricing catalog has `gpt-5.4` and `gpt-5.4-mini`, but not `gpt-5.5`.
- `CursorRequestCostEstimator` supports approximate total-only estimates for Anthropic and Composer, but not OpenAI/GPT.
- OpenAI pricing exposes input, cached input, and output rates. There is no separate Anthropic-style cache-write tier in
  the published pricing table, so GPT estimates must be explicit about how Cursor cache fields are interpreted.

Current official OpenAI API pricing checked 2026-06-21:

- `gpt-5.5`: `$5.00 / 1M` input, `$0.50 / 1M` cached input, `$30.00 / 1M` output.
- `gpt-5.4`: `$2.50 / 1M` input, `$0.25 / 1M` cached input, `$15.00 / 1M` output.
- `gpt-5.4 mini`: `$0.75 / 1M` input, `$0.075 / 1M` cached input, `$4.50 / 1M` output.

Source: https://openai.com/api/pricing/

## Goals

1. Show estimates for covered GPT rows in the Cursor request list and widget.
2. Normalize Cursor GPT model strings with effort suffixes to the priced base key.
3. Add current `gpt-5.5` pricing to the local catalog.
4. Return approximate ranges for total-only GPT rows instead of blank/unavailable pricing.
5. Keep legacy Cursor quota messaging request-based; these are diagnostic model-cost estimates only.

## Non-Goals

- Do not call pricing docs at runtime.
- Do not fabricate estimates for GPT models missing from the local catalog.
- Do not change Cursor request quota accounting.
- Do not change Anthropic or Composer pricing behavior except where shared helpers need small generalization.

## Design

### 1. Pricing Catalog

Update `Sources/CodexBarCore/Vendored/CostUsage/CostUsagePricing.swift`:

- Add `gpt-5.5` with input `5e-6`, cached input `5e-7`, output `3e-5`.
- Confirm the existing `codexCostUSD(model:inputTokens:cachedInputTokens:outputTokens:)` behavior with tests: it should
  charge non-cached input at the input rate, cached input at the cached-input rate, and output at the output rate.
- Add a small OpenAI/Codex pricing capability accessor, similar to `claudePricingCapabilities`, so Cursor code can build
  total-only approximate ranges without duplicating private catalog constants.
- Keep `supportedCodexPricingKey` as the gate for whether a normalized GPT model is actually priced.

### 2. GPT Model Normalization

Update `Sources/CodexBarCore/Providers/Cursor/CursorModelNormalizer.swift`:

- Treat the existing effort tokens (`minimal`, `low`, `medium`, `high`, `xhigh`, `max`) as removable suffixes for OpenAI
  model pricing.
- Also strip known provider aliases/prefixes that Cursor may emit before normalizing GPT names:
  - `openai/`
  - `openai:`
  - existing case-insensitive handling via lowercasing
- Preserve display labels with effort/mode where useful, but set `pricingKey` to the longest supported priced base:
  - `gpt-5.5-medium` -> `gpt-5.5`
  - `gpt-5.4-high` -> `gpt-5.4`
  - `gpt-5.4-mini-medium` -> `gpt-5.4-mini`
  - `openai/gpt-5.4-mini-high` -> `gpt-5.4-mini`
- Support multi-suffix strings by stripping trailing effort tokens repeatedly, then choosing the longest supported key
  from the remaining tokens.
- Keep unknown GPT-like strings unpriced when no supported base exists.

### 3. GPT Estimate Behavior

Update `Sources/CodexBarCore/Providers/Cursor/CursorRequestCostEstimator.swift`:

- For exact GPT breakdowns, use the shared catalog through `CostUsagePricing.codexCostUSD`.
- For GPT total-only rows, return `approximateTotalOnly` with a range from the cheapest plausible GPT token class to the
  most expensive output class:
  - If the row explicitly reports cache-hit/cache-read evidence, use cached-input as the low end.
  - Otherwise use uncached input as the low end so the estimate does not imply cache savings that Cursor did not expose.
  - Use output as the high end.
- For missing or partial GPT breakdowns with a positive request total, reuse the total-only fallback path so the row still
  shows an approximate range when possible.
- Keep explanations explicit: "Approximate range from total tokens only", "unknown input/output/cache split", and
  "Cursor legacy quota is request-based."
- Preserve no-fabrication behavior: if a GPT-like model does not normalize to a supported local pricing key, return no
  estimate even when tokens are present.

### 4. Tests

Add/extend focused tests:

- `CursorModelNormalizerTests`
  - `gpt-5.5-medium` normalizes to `pricingKey == "gpt-5.5"`.
  - `gpt-5.4-mini-high` normalizes to `pricingKey == "gpt-5.4-mini"`.
  - `openai:gpt-5.5-high` and mixed-case/prefix variants normalize to `gpt-5.5`.
  - multi-suffix variants such as `gpt-5.4-mini-high-medium` normalize to `gpt-5.4-mini`.
  - unsupported GPT variants remain unpriced.
- `CostUsagePricingTests`
  - `codexCostUSD` prices non-cached input, cached input, and output separately for `gpt-5.5`.
- `CursorRequestCostEstimatorTests`
  - exact `gpt-5.5-medium` breakdown prices from the `gpt-5.5` catalog.
  - total-only `gpt-5.5-medium` produces `Approx. $low-$high`.
  - recent request with no breakdown but positive tokens for GPT produces an approximate estimate.
  - total-only unsupported GPT variant returns no estimate.
  - GPT estimate explanations contain `request-based`.
- Widget/menu row tests if needed, only if formatter coverage does not already prove the visible `Approx.`/`Est.` string.

### 5. Docs

Update `docs/cursor.md`:

- Mention GPT total-only rows can show approximate ranges when local OpenAI pricing covers the normalized model.
- Record the OpenAI pricing source/date for `gpt-5.5`, `gpt-5.4`, and `gpt-5.4 mini`.

## Verification

Run:

```bash
./Scripts/lint.sh format
swift test --filter "CursorModelNormalizerTests|CursorRequestCostEstimatorTests|MenuCardCursorRequestDetailsTests|CursorWidgetSnapshotTests"
pnpm check
./Scripts/compile_and_run.sh
```

If implementation touches broader shared pricing helpers, also run:

```bash
swift test --filter "CostUsagePricingTests|CLICostTests"
```

## Risks

- Cursor may introduce GPT aliases that are not direct OpenAI API model IDs. The normalizer should only price aliases that
  collapse to an explicitly supported local key.
- Total-only GPT estimates are inherently approximate. The UI must continue to label them as `Approx.` rather than `Est.`
  or an exact dollar amount.
- The existing worktree has prior uncommitted Cursor range-switch changes. Implementation must preserve those changes and
  only add narrowly scoped GPT-pricing updates.
