# Codex Multi-Account Support — Design Doc

**Date:** 2026-02-26
**Status:** Approved
**Scope:** Add multi-account switching for the Codex (OpenAI) provider inside CodexBar, propagating instantly to the CLI, IDE extension, and Codex.app via `~/.codex/auth.json`.

---

## Background

CodexBar already ships a complete multi-account system (account switcher UI, per-account usage display, macOS quota notifications) for Claude, Cursor, Zai, OpenCode, and others. Codex is absent from `TokenAccountSupportCatalog+Data.swift` — the sole registry that gates this feature — because its auth mechanism differs from cookie/env-var injection.

The Codex CLI, IDE extension (openai.chatgpt), and Codex.app all read from `~/.codex/auth.json` (overridable via `$CODEX_HOME`). Switching accounts means atomically rewriting that file. This design adds a new `codexOAuth` injection type that handles that write, plugging Codex into the existing infrastructure with minimal surface area change.

---

## Architecture

### New injection case

```swift
// TokenAccountSupport.swift
public enum TokenAccountInjection: Sendable {
    case cookieHeader
    case environment(key: String)
    case codexOAuth   // NEW: writes JSON blob to ~/.codex/auth.json
}
```

### Catalog registration

```swift
// TokenAccountSupportCatalog+Data.swift
.codex: TokenAccountSupport(
    title: "Codex accounts",
    subtitle: "Import from ~/.codex/auth.json after each codex login.",
    placeholder: "Paste auth.json contents or use Import button…",
    injection: .codexOAuth,
    requiresManualCookieSource: false,
    cookieName: nil)
```

### Auth file write (on switch)

```swift
// TokenAccountSupportCatalog.swift — new handler in envOverride()
case .codexOAuth:
    let written = CodexOAuthAccountWriter.write(jsonString: token)
    return written ? ["CODEX_HOME": NSHomeDirectory() + "/.codex"] : nil
```

`CodexOAuthAccountWriter` (new file in `CodexBarCore/Providers/Codex/`) performs:
1. Validate JSON is parseable and contains required keys (`tokens.access_token`, `tokens.refresh_token`)
2. Atomic write via temp file + `FileManager.replaceItem(at:withItemAt:)` to `~/.codex/auth.json`
3. Return success/failure

### Multi-account usage fetching

For CodexBar to display live usage for **all** registered accounts (not just the active one), it needs to fetch each account without overwriting the shared auth.json. Strategy: create per-account temp `CODEX_HOME` dirs.

```
~/.codex-bar-tmp/<account-uuid>/auth.json   ← ephemeral, written before fetch
```

`ProviderRegistry.makeEnvironment()` already threads `env` through to `ProviderFetchContext`. For `codexOAuth` accounts, override `CODEX_HOME` per-fetch to point at the temp dir. Temp dirs are cleaned up after each fetch cycle.

### Switch propagation

| Surface | How it picks up the change |
|---|---|
| Codex CLI | Reads `~/.codex/auth.json` fresh on every invocation ✅ |
| IDE extension | Spawns `codex app-server` on demand; reads same file ✅ |
| Codex.app | Reads same file on launch (requires manual restart — acceptable) ✅ |
| CodexBar usage fetch | Uses `CODEX_HOME` env override per-fetch ✅ |

### Notifications

`SessionQuotaNotifier` already fires:
- `depleted` → "Codex session depleted — 0% left."
- `restored` → "Codex session restored."

No new notification code needed. When the user switches to an account with quota remaining after the active one depletes, the `restored` transition fires automatically on the next usage refresh.

---

## User Flow

### First-time setup (per account)

1. In terminal: `codex login` → complete browser OAuth
2. Open Preferences → Codex → Token Accounts
3. Click **Import current login** (reads `~/.codex/auth.json`, stores it, prompts for a label)
   — OR — paste the raw `auth.json` JSON into the text field manually
4. Repeat for second account: `codex login` (which overwrites auth.json) → Import

### Switching

- In the CodexBar menu: click the account pill in the Codex section → instant switch
- OR via CLI/script: `codexbar-switch codex <label>` (optional CLI wrapper, out of scope v1)

---

## Edge Cases

### 1. Expired tokens in stored account
**Scenario:** Stored auth.json tokens are expired; switch succeeds but CLI returns 401.
**Handling:** CodexBar shows a fetch error for that account in the UI (existing error path). User must `codex login` and re-import.
**Future:** Wire `CodexTokenRefresher` to attempt a token refresh before writing, storing the refreshed tokens back.

### 2. Auth.json write failure (permissions / disk full)
**Scenario:** `FileManager.replaceItem` fails.
**Handling:** `CodexOAuthAccountWriter.write()` returns `false`. `envOverride()` returns `nil`. Treat as "switch failed" — show an error banner in the menu and do NOT update `activeIndex` in the store. The previous account remains active.

### 3. Invalid or malformed JSON stored in token field
**Scenario:** User pastes garbage or a truncated auth.json.
**Handling:** Validate at add-time in the input field. Block save if JSON is not parseable or missing `tokens.access_token` + `tokens.refresh_token`. Show inline error: "Invalid auth.json — must contain tokens.access_token and tokens.refresh_token."

### 4. External `codex login` while CodexBar is running
**Scenario:** User runs `codex login` in the terminal while CodexBar has a stored account active. `~/.codex/auth.json` is now overwritten by the new login.
**Handling:** CodexBar does not monitor auth.json for external changes. On the next refresh cycle, it will fetch using `~/.codex/auth.json` as-is. The stored accounts are unaffected — they are in `~/.config/CodexBar/config.json`. The user should Import the new login to persist it.
**Future:** FSEvents watcher on auth.json to detect external writes and prompt "Detected a new codex login — import as account?"

### 5. Only one account registered
**Handling:** Existing behavior — `TokenAccountSupportCatalog` returns an account list of size 1, the switcher UI is not shown, single-account mode operates as before.

### 6. Startup — active account reconciliation
**Scenario:** CodexBar launches and `~/.codex/auth.json` does not match any stored account (e.g., user logged in manually after last session).
**Handling:** CodexBar reads the stored `activeIndex` from config and writes that account's JSON to auth.json on first switch. Until a switch happens, the current auth.json is used as-is (no silent overwrite on startup). This preserves any manual session the user started.

### 7. Concurrent switch while fetch in progress
**Handling:** `UsageStore.refreshTokenAccounts()` is `async` and runs on a task. A switch (write to auth.json + `setActiveTokenAccountIndex`) can happen mid-fetch for another account. The temp `CODEX_HOME` dirs isolate concurrent fetches from the live auth.json. The switch completes immediately; the in-flight fetch for the old account completes and its result is discarded if `activeIndex` has changed.

### 8. Temp CODEX_HOME dir cleanup
**Scenario:** App crashes mid-fetch, leaving stale dirs in `~/.codex-bar-tmp/`.
**Handling:** On CodexBar launch, delete the entire `~/.codex-bar-tmp/` tree. Also clean up after each fetch cycle in a `defer` block.

### 9. Account limit (6 accounts)
**Handling:** Existing `limitedTokenAccounts()` cap of 6. Enforced at the UI layer — the "Add account" button is disabled when 6 accounts are stored. Error shown: "Maximum 6 Codex accounts supported."

### 10. Keychain-stored credentials (non-file auth)
**Scenario:** User has `cli_auth_credentials_store = "keyring"` in codex config; tokens live in OS keychain, not auth.json.
**Handling:** CodexBar's import reads `auth.json` which may be absent or stale. Detect at import time: if auth.json is missing or empty, show: "No auth.json found. Set `cli_auth_credentials_store = \"file\"` in ~/.codex/config.toml and run `codex login` again." Out of scope: direct keychain read.

### 11. auth.json written but codex CLI is running interactively
**Scenario:** User switches accounts while `codex` is already open in a terminal session.
**Handling:** The running session uses its in-memory tokens. The switch affects only new invocations. This is the same behavior as any credential rotation and requires no special handling.

### 12. Renewal date display
**What's there:** `UsageStore` already surfaces `quotaResetDate` from the API response if present. CodexBar shows this in the menu card where available.
**No new code needed** — once Codex is wired into the fetch pipeline, its reset date will display automatically if the API returns it.

---

## Files Changed

| File | Change type |
|---|---|
| `Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexOAuthAccountWriter.swift` | New — atomic auth.json writer + validator |
| `Sources/CodexBarCore/TokenAccountSupport.swift` | Add `case codexOAuth` to `TokenAccountInjection` |
| `Sources/CodexBarCore/TokenAccountSupportCatalog+Data.swift` | Register `.codex` entry |
| `Sources/CodexBarCore/TokenAccountSupportCatalog.swift` | Handle `.codexOAuth` in `envOverride()` |
| `Sources/CodexBar/ProviderRegistry.swift` | Handle `.codexOAuth` in `makeEnvironment()` — CODEX_HOME temp dir per-fetch |
| `Sources/CodexBar/UsageStore+TokenAccounts.swift` | Temp dir lifecycle (create before fetch, cleanup after) |
| `Sources/CodexBar/PreferencesProviderDetailView.swift` | "Import current login" button for `.codex` provider |
| `Tests/CodexBarTests/CodexOAuthAccountWriterTests.swift` | New — validation + atomic write tests |
| `Tests/CodexBarTests/TokenAccountSupportCatalogTests.swift` | Extend — `.codexOAuth` cases |

---

## Out of Scope (v1)

- Auto-switch when quota depletes (quota-based auto-routing)
- Token refresh for expired stored accounts
- FSEvents watcher for external auth.json changes
- Keychain-stored credential support
- CLI wrapper script (`codexbar-switch`)
