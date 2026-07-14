# Codex Cost History Missing Days Design

## Problem

`CostHistoryChartMenuView` excludes a daily report entry when `costUSD` is `nil`. A day can still have valid token
usage when its models do not yet have local pricing. Excluding that entry makes hover selection jump across real usage
days and incorrectly suggests that no usage occurred.

## Design

Normalize every valid daily entry into chart data when it has either a nonnegative cost or any positive token field
(`totalTokens`, `inputTokens`, `outputTokens`, `cacheReadTokens`, or `cacheCreationTokens`). Zero-only or negative-only
token fields do not establish usage. A negative cost is treated as unavailable; it does not make an otherwise empty
entry valid, but positive tokens still retain that day. Keep cost optional in the normalized point: use zero only as
the bar's plotting baseline, while detail text shows an em dash for an unavailable cost. Selectable dates and model
breakdowns retain the original entry. Peak highlighting considers only known, positive costs.

The normalization is an internal, Foundation-only model so date inclusion and detail values can be tested without
constructing AppKit menus or Swift Charts views.

## Verification

- A token-bearing entry with no cost remains selectable and retains its token count.
- Positive component tokens retain an entry when `totalTokens` is absent; zero-only and negative-only entries do not.
- A known-cost entry retains its cost and participates in peak selection.
- In mixed known/unknown-cost data, only the known positive cost becomes the peak.
- An entry with neither cost nor tokens remains excluded.
- The complete Swift test suite, formatting/lint checks, packaged build, and relaunched app succeed.
