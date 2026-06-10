---
summary: "Cursor provider data sources: browser cookies or stored session; usage + billing via cursor.com APIs."
read_when:
  - Debugging Cursor usage parsing
  - Updating Cursor cookie import or session storage
  - Adjusting Cursor provider UI/menu behavior
---

# Cursor provider

Cursor is web-only. Usage is fetched via browser cookies or a stored WebKit session.

## Data sources + fallback order

1) **Cached cookie header** (preferred)
   - Stored after successful browser import.
   - Keychain cache: `com.steipete.codexbar.cache` (account `cookie.cursor`).

2) **Browser cookie import**
   - Cookie order from provider metadata (default: Safari → Chrome → Firefox).
   - Domain filters: `cursor.com`, `cursor.sh`.
   - Cookie names required (any one counts):
     - `WorkosCursorSessionToken`
     - `__Secure-next-auth.session-token`
     - `next-auth.session-token`

3) **Stored session cookies** (fallback)
   - Captured by the "Add Account" WebKit login flow.
   - Login teardown uses `WebKitTeardown` to avoid Intel WebKit crashes.
   - Stored at: `~/Library/Application Support/CodexBar/cursor-session.json`.

Manual option:
- Preferences → Providers → Cursor → Cookie source → Manual.
- Paste the `Cookie:` header from a cursor.com request.

## API endpoints
- `GET https://cursor.com/api/usage-summary`
  - Plan usage (included), on-demand usage, billing cycle window.
- `GET https://cursor.com/api/auth/me`
  - User email + name.
- `GET https://cursor.com/api/usage?user=ID`
  - Legacy quota usage.
  - Request-backed plans expose request counts + limits.
  - Some legacy plans expose token counts via `numTokens` + `maxTokenUsage`; CodexBar falls back to those fields when request quotas are absent.
  - If `numTokens` is present but `maxTokenUsage` is missing, CodexBar still records billing-cycle token usage for widget display.
- `POST https://cursor.com/api/dashboard/get-filtered-usage-events`
  - Per-request usage rows for the current billing cycle (`usageEventsDisplay`).
  - Requires `Origin: https://cursor.com` with session cookies.
- CodexBar maps rows to menu/widget request details (model, timestamp, token spend, numeric request count from
    `requestsCosts`). Dashboard `kind` is not shown. Fetch failures are non-fatal.
  - When the event includes a token breakdown (`inputTokens`, `outputTokens`, `cacheReadTokens`, `cacheWriteTokens`,
    `totalTokens`), CodexBar preserves it on the request and records a confidence (`exactBreakdown`, `partialBreakdown`,
    `totalOnly`, or `empty`). Missing fields stay unknown and are never coerced to zero.

## Legacy quota stays request-based
- For legacy request-backed plans, the request count (`Requests: used / limit`) remains the primary quota line in the
  menu and the source of truth for the quota. Billing-cycle tokens move to a secondary `Cycle: N tokens` line.
- Request-count rows survive even when an event reports zero tokens, as long as it represents at least one request.

## Model-cost estimates (diagnostic only)
- Recent request rows can show an optional local model-cost estimate, labelled `Est.` when a breakdown-based estimate is
  available, `Approx. $low-$high` when only a total token count is available (Composer 2.5), or `Partial` only when
  CodexBar has an incomplete lower-bound estimate.
- Estimates are computed locally from the shared `CostUsagePricing` catalog for Anthropic/OpenAI models and from Cursor's
  published Composer 2.5 changelog rates for Cursor-owned models (source-versioned in-repo); CodexBar never calls pricing
  docs at runtime. The estimate is diagnostic and never implies Cursor bills the legacy plan by dollars — expanded details
  and hover/help always state the quota is request-based.
- Raw Cursor model strings are normalized for compact display (e.g. `claude-opus-4-8-thinking-xhigh` → `Opus 4.8 · xhigh`).
  Thinking effort never changes the pricing key.
- **Composer 2.5 pricing** (from [Cursor Composer 2.5 changelog](https://cursor.com/changelog/composer-2-5), checked
  2026-06-08): Fast `$3/M` input + `$15/M` output; Standard `$0.50/M` input + `$2.50/M` output. Raw `composer-2.5`
  defaults to Fast unless the model string explicitly includes `standard`. Total-only Composer rows show an approximate
  range (`Approx. $low-$high`) instead of a single exact dollar amount.
- Unknown models without local pricing coverage render cleanly with cost unavailable rather than a fabricated value.
- Claude `cacheWriteTokens` default to Anthropic's 5-minute cache-write rate. Composer cache tokens are counted as
  input-equivalent when input/output fields exist; Cursor does not publish separate Composer cache billing, so expanded
  details mention that caveat when cache fields are present.
- Cursor does not expose the Anthropic cache TTL, so expanded details state the 5-minute cache-write assumption for Claude
  rows; request-plan quota remains request-based.

## Cookie file paths
- Safari: `~/Library/Cookies/Cookies.binarycookies`
- Chrome/Chromium forks: `~/Library/Application Support/Google/Chrome/*/Cookies`
- Firefox: `~/Library/Application Support/Firefox/Profiles/*/cookies.sqlite`

## Snapshot mapping
- Primary: plan usage percent (included plan).
- Legacy quota fallback: if `/api/usage` reports request or token quotas, primary uses that quota percent for legacy plans.
- Secondary: on-demand usage percent (individual usage).
- Provider cost: on-demand usage USD (limit when known).
- Widget token row: uses `/api/usage` `numTokens` as a billing-cycle token total and labels it `Cycle`; when recent
  request rows have priced breakdowns, the row also includes the summed local estimate next to the token total.
- Menu request rows: uses filtered usage events (newest first, capped at 30) when available. Each row is a compact
  two-line layout (compact model + token spend, then time + `Req N` + optional estimate). **Click a row to expand** the
  full detail block (raw model, timestamp, token breakdown, estimate, pricing source, request-based disclaimer). Hover
  help mirrors the same content as a best-effort bonus, but click-to-expand is the primary detail surface because
  `NSMenu`-hosted SwiftUI hover is unreliable inside scroll views. The Cursor menu card keeps the range visible and puts
  overflowing request rows in a fixed-height scroll region whose height does not change when a row expands.
- Widget request rows: uses filtered usage events (newest first, capped at 30) when available, rendered with the
  compact model label and optional estimate (`Est.` or `Approx.`). WidgetKit has no hover or row expansion — breakdown
  detail stays in the macOS menu.
- Reset: billing cycle end date.

## Key files
- `Sources/CodexBarCore/Providers/Cursor/CursorStatusProbe.swift`
- `Sources/CodexBar/CursorLoginRunner.swift` (login flow)
