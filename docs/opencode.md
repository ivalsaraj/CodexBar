---
summary: "OpenCode provider notes: browser cookie import, workspace page fetches, and usage parsing."
read_when:
  - Adding or modifying the OpenCode provider
  - Debugging OpenCode usage parsing or cookie import
---

# OpenCode provider

## Data sources
- Browser cookies from `opencode.ai`.
- `GET` or fallback `POST https://opencode.ai/_server` for workspace discovery:
  - `workspaces` (`def39973159c7f0483d8793a822b8dbb10d067e12c65455fcb4608459ba0234f`)
- Preferred: `GET https://opencode.ai/workspace/<id>/go`
- Fallback: `GET https://opencode.ai/workspace/<id>/usage`
- Fallback: `GET https://opencode.ai/workspace/<id>/billing`

## Usage mapping
- Preferred mapping comes from the Go dashboard hydration payload:
  - Primary window: `rollingUsage`
  - Secondary window: `weeklyUsage`
  - Tertiary window: `monthlyUsage` when present
- Fallback mapping uses the legacy usage-history parser:
  - Primary window: trailing 5-hour spend derived from `usage.list["<workspace>",0]`.
  - Secondary window: trailing 7-day spend derived from the same usage records.
  - Budget denominator:
    - `monthlyLimit` when present and positive.
    - Otherwise `balance + listed usage cost`.
  - Resets are computed from when the earliest record in each trailing window ages out.

## Notes
- Both the Go dashboard and workspace history pages currently embed the data inside HTML/loader scripts, so parsing still relies on regex over page text.
- Missing workspace ID, usage records, or usable billing budget should raise parse errors.
- OpenCode cards should mirror the dashboard's direct usage windows only. Do not add synthetic weekly pace or reserve overlays for OpenCode.
- OpenCode is workspace-first in settings:
  - `Import current login` imports the current browser session and auto-adds every discovered workspace.
  - `Refresh workspaces` re-discovers workspaces for the saved OpenCode login and dedupes by workspace ID.
  - Manual add only needs a `wrk_…` ID or full workspace URL and reuses the saved OpenCode login.
- Cookie import defaults to Chrome-only to avoid extra browser prompts; pass a browser list to override.
- Set `CODEXBAR_OPENCODE_WORKSPACE_ID` to skip workspace lookup and force a specific workspace.
- When both settings and `CODEXBAR_OPENCODE_WORKSPACE_ID` are present, the environment override wins for both fetching and dashboard navigation.
- Workspace override accepts a raw `wrk_…` ID or a full `https://opencode.ai/workspace/...` URL.
- The OpenCode dashboard action should resolve to `/workspace/<id>/go` only when a workspace override is available from settings or `CODEXBAR_OPENCODE_WORKSPACE_ID`; otherwise it keeps the provider default dashboard URL.
- Cached cookies: Keychain cache `com.steipete.codexbar.cache` (account `cookie.opencode`, source + timestamp). Browser
  import only runs when the cached cookie fails.
