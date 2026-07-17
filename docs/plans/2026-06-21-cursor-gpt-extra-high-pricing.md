# Cursor GPT Extra-High Pricing Fix Plan

## Problem

The live widget snapshot shows GPT pricing still missing for Cursor rows whose model is `gpt-5.5-extra-high`.

Observed from the current persisted widget snapshot:

- `gpt-5.5-high` normalizes to `GPT-5.5 · high` and shows estimates such as `Approx. $0.11-$6.57`.
- `gpt-5.5-extra-high` normalizes to `GPT-5.5 Extra · high` and has `estimateText == nil`.

That means GPT pricing works for ordinary `high`, but the normalizer does not understand Cursor's two-token
`extra-high` effort suffix. It strips only the final `high`, leaves `extra` in the priced model key, and therefore looks
for unsupported `gpt-5.5-extra`.

## Goals

1. Normalize Cursor GPT aliases with `extra-high` as an effort suffix.
2. Price `gpt-5.5-extra-high` through the existing `gpt-5.5` pricing key.
3. Keep unsupported aliases unpriced; do not allow broad prefix matching to come back.
4. Cover the live widget failure path with tests.

## Non-Goals

- Do not add new pricing rates.
- Do not change Cursor request quota accounting.
- Do not change supported GPT variants beyond recognizing the `extra-high` effort suffix.

## Design

Update `CursorModelNormalizer.normalizeOpenAI`:

- Extract OpenAI effort suffixes with a small helper that consumes effort tokens from the right edge only.
- Preserve the current repeated single-token behavior for inputs such as `gpt-5.4-mini-high-medium`: strip all trailing
  single-token efforts and keep the leftmost stripped effort (`high`) as the display effort.
- When the right-edge suffix sequence contains the adjacent token pair `extra`, `high`, treat that pair as one canonical
  effort value, `extra-high`, and remove both tokens from the pricing/display token list.
- Do not treat `extra` as a model-name token when it is part of that right-edge effort pair, including chained suffixes:
  - `gpt-5.5-extra-high` -> display `GPT-5.5`, effort `extra-high`, pricing key `gpt-5.5`
  - `gpt-5.4-mini-extra-high-medium` -> display `GPT-5.4 Mini`, effort `extra-high`, pricing key `gpt-5.4-mini`
  - `gpt-5.5-ultra` -> display `GPT-5.5 Ultra`, no pricing key
- Continue using exact supported-pricing lookup only:
  - `gpt-5.5-extra-high` -> pricing key `gpt-5.5`
  - `openai:gpt-5.5-extra-high` -> pricing key `gpt-5.5`
  - `gpt-5.4-mini-extra-high` -> pricing key `gpt-5.4-mini`
  - `gpt-5.5-ultra` -> no pricing key

Update display behavior:

- Compact rows should render `GPT-5.5 · extra-high`, not `GPT-5.5 Extra · high`.

## Tests

Add focused tests:

- `CursorModelNormalizerTests`
  - `gpt-5.5-extra-high` normalizes to display `GPT-5.5`, effort `extra-high`, pricing key `gpt-5.5`.
  - `openai:gpt-5.4-mini-extra-high` normalizes to pricing key `gpt-5.4-mini`.
  - `gpt-5.4-mini-extra-high-medium` keeps `extra-high` as the display effort and pricing key `gpt-5.4-mini`.
  - `gpt-5.5-ultra` remains unpriced.
- `CursorRequestCostEstimatorTests`
  - total-only `gpt-5.5-extra-high` produces the same approximate range as `gpt-5.5`.
- `CursorWidgetSnapshotTests`
  - live-like `gpt-5.5-extra-high` row gets compact label `GPT-5.5 · extra-high` and a non-nil estimate.

## Docs

Update the docs that describe this behavior:

- `docs/cursor.md`: mention that multi-token thinking efforts such as `extra-high` are removed from the pricing key.
- `docs/widgets.md`: update the compact-model example to include GPT `extra-high` estimates, so the widget snapshot
  contract reflects the newly covered live case.

## Verification

Run:

```bash
swift test --filter "CursorModelNormalizerTests|CursorRequestCostEstimatorTests|CursorWidgetSnapshotTests"
./Scripts/lint.sh format
swift test --filter "CursorModelNormalizerTests|CursorRequestCostEstimatorTests|CostUsagePricingTests|MenuCardCursorRequestDetailsTests|CursorWidgetSnapshotTests"
pnpm check
./Scripts/compile_and_run.sh
```

After rebuild, inspect the live `widget-snapshot.json` again and confirm `gpt-5.5-extra-high` rows have `estimateText`.
