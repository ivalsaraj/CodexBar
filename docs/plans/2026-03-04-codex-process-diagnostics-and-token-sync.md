# Codex Token Rotation Resilience + Dependent Process Diagnostics Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Eliminate stale-token switch regressions that trigger `refresh_token_reused` noise and add an in-menu Codex diagnostics panel that shows dependent running processes with contextual restart guidance.

**Architecture:** Implement two coordinated paths. First, make stored Codex account payloads self-healing by (a) normalizing switch-write payloads and (b) syncing active-account auth blobs back into CodexBar storage after successful OAuth fetches. Second, add an event-driven process probe (`menu open`, `after switch`, `manual refresh`) and render a collapsible, fixed-height diagnostics table inside the Codex section of the CodexBar menu.

**Tech Stack:** Swift 6, AppKit + SwiftUI menu-hosted views, existing `SubprocessRunner`, existing Codex OAuth parsing/writer utilities, Swift Testing (`import Testing`).

---

### Task 1: Define Token-Sync Behavior with Failing Tests

**Files:**
- Modify: `Tests/CodexBarTests/CodexOAuthAccountWriterTests.swift`
- Modify: `Tests/CodexBarTests/CodexAccountSwitchTests.swift`
- Create: `Tests/CodexBarTests/CodexActiveAccountTokenSyncTests.swift`

**Step 1: Write failing tests for switch payload normalization**

Add tests covering:
- switch-write payload keeps `tokens.*` unchanged
- `last_refresh` is rewritten to current timestamp at switch normalization time
- malformed payload still throws validation error

```swift
@Test("prepareForSwitch rewrites last_refresh but preserves tokens")
func prepareForSwitchRewritesLastRefresh() throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let prepared = try CodexOAuthAccountWriter.prepareForSwitch(jsonString: sampleJSON, now: now)
    let parsed = try JSONSerialization.jsonObject(with: Data(prepared.utf8)) as? [String: Any]
    let tokens = parsed?["tokens"] as? [String: Any]
    #expect(tokens?["refresh_token"] as? String == "ref_abc")
    #expect(parsed?["last_refresh"] as? String == "2023-11-14T22:13:20Z")
}
```

**Step 2: Write failing tests for active-account sync-back**

Add tests covering:
- when latest `auth.json` differs from stored active account token, stored token is updated
- when equivalent payload is unchanged, no config write is performed
- sync path is no-op when no active account exists

```swift
@Test("sync updates only active codex account token when changed")
func syncUpdatesActiveAccountToken() async throws {
    // Arrange settings with two Codex accounts and active index = 0
    // Write newer auth.json to temp CODEX_HOME
    // Invoke sync helper
    // Assert account[0].token updated, account[1].token unchanged
}
```

**Step 3: Run tests to verify failure**

Run:
```bash
swift test --filter CodexOAuthAccountWriterTests
swift test --filter CodexAccountSwitchTests
swift test --filter CodexActiveAccountTokenSyncTests
```

Expected:
- new tests fail with missing symbols (`prepareForSwitch`, sync helper)

**Step 4: Commit test-only scaffold**

```bash
git add Tests/CodexBarTests/CodexOAuthAccountWriterTests.swift \
        Tests/CodexBarTests/CodexAccountSwitchTests.swift \
        Tests/CodexBarTests/CodexActiveAccountTokenSyncTests.swift
git commit -m "test(codex): capture token normalization and active-account sync behavior"
```

---

### Task 2: Implement Codex Switch-Payload Normalization

**Files:**
- Modify: `Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexOAuthAccountWriter.swift`
- Modify: `Sources/CodexBar/Providers/Codex/CodexAccountSwitcher.swift`

**Step 1: Add normalization API to writer**

Implement:
- `prepareForSwitch(jsonString:now:) throws -> String`
- validate JSON first, parse object, set `last_refresh` to ISO8601 UTC for provided `now`, emit canonical JSON (sorted keys)

```swift
public static func prepareForSwitch(jsonString: String, now: Date = Date()) throws -> String
```

**Step 2: Use normalized payload in switch flow**

In `CodexAccountSwitcher.switchToAccount(token:...)`:
- call `prepareForSwitch`
- write normalized payload instead of raw stored token

**Step 3: Run focused tests**

Run:
```bash
swift test --filter CodexOAuthAccountWriterTests
swift test --filter CodexAccountSwitchTests
```

Expected:
- all tests pass

**Step 4: Commit**

```bash
git add Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexOAuthAccountWriter.swift \
        Sources/CodexBar/Providers/Codex/CodexAccountSwitcher.swift
git commit -m "feat(codex): normalize auth payload at account switch"
```

---

### Task 3: Implement Active Codex Account Token Sync-Back

**Files:**
- Modify: `Sources/CodexBar/SettingsStore+TokenAccounts.swift`
- Modify: `Sources/CodexBar/UsageStore+TokenAccounts.swift`
- Modify: `Sources/CodexBar/UsageStore+Refresh.swift`

**Step 1: Add SettingsStore token replacement API**

Implement method:

```swift
func replaceTokenAccountToken(
    provider: UsageProvider,
    accountID: UUID,
    token: String
)
```

Rules:
- no-op if provider unsupported, account missing, or token unchanged
- update only the targeted account, keep ordering + `activeIndex`

**Step 2: Add UsageStore sync helper**

Implement helper in `UsageStore+TokenAccounts`:

```swift
func syncActiveCodexAccountTokenFromDiskIfNeeded() async
```

Behavior:
- read active Codex account
- import current `auth.json` (default CODEX_HOME)
- if different from stored token, replace active token in settings

**Step 3: Trigger sync after successful Codex OAuth fetch**

In refresh success path (`UsageStore+Refresh`), when:
- `provider == .codex`
- source label is OAuth (`"oauth"`)

then call `syncActiveCodexAccountTokenFromDiskIfNeeded()`.

**Step 4: Run focused tests**

Run:
```bash
swift test --filter CodexActiveAccountTokenSyncTests
swift test --filter CodexOAuthTests
```

Expected:
- token sync tests pass
- existing OAuth tests still pass

**Step 5: Commit**

```bash
git add Sources/CodexBar/SettingsStore+TokenAccounts.swift \
        Sources/CodexBar/UsageStore+TokenAccounts.swift \
        Sources/CodexBar/UsageStore+Refresh.swift
git commit -m "feat(codex): sync rotated auth token back to active stored account"
```

---

### Task 4: Add Codex Dependent Process Probe (Read-Only Snapshot)

**Files:**
- Create: `Sources/CodexBarCore/Providers/Codex/CodexDependentProcessProbe.swift`
- Create: `Tests/CodexBarTests/CodexDependentProcessProbeTests.swift`

**Step 1: Write failing parser/classification tests**

Cover:
- parsing `ps -axo pid=,lstart=,comm=,command=` lines (headerless output)
- classifying known process sources (`BrowserForce`, `Codex.app`, `Cursor`, `Terminal/Other`)
- stale-risk detection vs `lastSwitchAt`

```swift
@Test("classifies browserforce mcp process")
func classifiesBrowserforceProcess() throws { ... }

@Test("marks app-server started before switch as stale-risk")
func staleRiskDetection() throws { ... }
```

**Step 2: Implement probe**

Implement API:

```swift
public struct CodexDependentProcessSnapshot: Sendable { ... }
public enum CodexDependentProcessProbe {
    public static func snapshot(now: Date = .init()) async throws -> CodexDependentProcessSnapshot
}
```

Use:
- `SubprocessRunner.run(binary: "/bin/ps", arguments: ["-axo", "pid=,lstart=,comm=,command="])`
- parse + filter codex-related entries
- include display-ready fields (`process`, `pid`, `source`, `startedAt`, `command`)

**Step 3: Run tests**

Run:
```bash
swift test --filter CodexDependentProcessProbeTests
```

Expected:
- pass

**Step 4: Commit**

```bash
git add Sources/CodexBarCore/Providers/Codex/CodexDependentProcessProbe.swift \
        Tests/CodexBarTests/CodexDependentProcessProbeTests.swift
git commit -m "feat(codex): add dependent-process snapshot probe"
```

---

### Task 5: Add Menu State + Event-Driven Fetch Hooks

**Files:**
- Modify: `Sources/CodexBar/StatusItemController.swift`
- Modify: `Sources/CodexBar/StatusItemController+Menu.swift`
- Modify: `Sources/CodexBar/StatusItemController+TokenAccountsMenu.swift`

**Step 1: Add controller state for diagnostics**

Add state:
- `codexDependentProcessesExpanded: Bool`
- `codexDependentProcessesSnapshot: CodexDependentProcessSnapshot?`
- `codexDependentProcessesLoading: Bool`
- `codexDependentProcessesTask: Task<Void, Never>?`
- `codexLastAccountSwitchAt: Date?`

**Step 2: Add refresh entry points**

Implement methods:
- `refreshCodexDependentProcesses(reason:)`
- `toggleCodexDependentProcessesExpanded()`
- `refreshCodexDependentProcessesOnMenuOpenIfNeeded(provider:)`
- Ensure `refreshCodexDependentProcesses(reason:)` cancels any in-flight `codexDependentProcessesTask`
  before starting a new task, so rapid menu opens/switches cannot race and overwrite newer results.

Trigger points:
- `menuWillOpen` for Codex menu/provider
- after successful `switchTokenAccount` completion
- manual refresh action from panel

**Step 3: Mark switch timestamp**

When Codex switch starts/succeeds, set `codexLastAccountSwitchAt = Date()` and use it for stale-risk labeling.

**Step 4: Add tests for state transitions**

Extend `StatusItemControllerMenuTests`:
- toggling expand/collapse
- post-switch refresh trigger
- stale-risk flag when process started before switch time

**Step 5: Run tests**

Run:
```bash
swift test --filter StatusItemControllerMenuTests
```

Expected:
- pass

**Step 6: Commit**

```bash
git add Sources/CodexBar/StatusItemController.swift \
        Sources/CodexBar/StatusItemController+Menu.swift \
        Sources/CodexBar/StatusItemController+TokenAccountsMenu.swift \
        Tests/CodexBarTests/StatusItemControllerMenuTests.swift
git commit -m "feat(codex): add event-driven dependent-process diagnostics state"
```

---

### Task 6: Add Collapsible Fixed-Height Diagnostics UI in Codex Menu

**Files:**
- Modify: `Sources/CodexBar/StatusItemController+SwitcherViews.swift`
- Modify: `Sources/CodexBar/StatusItemController+TokenAccountsMenu.swift`

**Step 1: Create panel view**

Add a new menu-hosted view:

```swift
final class CodexDependentProcessesPanelView: NSView { ... }
```

UI requirements:
- always visible header row: `Dependent Codex Processes (N)`
- collapsible content area
- fixed max height (e.g. 140-180pt) + scroll
- columns: Process, PID, Source, Started, Auth Risk
- per-row contextual hint (`Restart Cursor Codex session`, `Restart BrowserForce MCP`, etc.)

**Step 2: Wire into Codex section only**

In token-account menu composition:
- render panel under account switch controls for `.codex`
- preserve existing switcher UX

**Step 3: Add manual Refresh action**

Expose callback from panel header/button to `refreshCodexDependentProcesses(reason: .manual)`.

**Step 4: Run targeted tests/build**

Run:
```bash
swift test --filter StatusItemControllerMenuTests
swift build
```

Expected:
- pass

**Step 5: Commit**

```bash
git add Sources/CodexBar/StatusItemController+SwitcherViews.swift \
        Sources/CodexBar/StatusItemController+TokenAccountsMenu.swift
git commit -m "feat(codex): add collapsible dependent-process diagnostics panel"
```

---

### Task 7: Verification + Docs + App Validation

**Files:**
- Modify: `docs/codex.md`
- Modify: `docs/codex-oauth.md`

**Step 1: Document behavior**

Add:
- event-driven diagnostics fetch policy (menu open / post-switch / manual refresh)
- meaning of stale-risk label
- token sync-back behavior for active Codex account

**Step 2: Run full verification suite**

Run:
```bash
pnpm check
swift test
./Scripts/compile_and_run.sh
```

Expected:
- lint clean
- tests pass
- packaged app relaunches with `OK: CodexBar is running.`

**Step 3: Manual validation checklist**

1. Open CodexBar menu on Codex -> panel appears collapsed with process count.
2. Expand panel -> list scrolls within fixed height.
3. Switch Codex account -> list refreshes automatically.
4. If stale long-lived process exists -> row shows `May hold old token` + targeted restart hint.
5. Verify no generic “kill all codex processes” messaging appears.

**Step 4: Final commit**

```bash
git add docs/codex.md docs/codex-oauth.md
git commit -m "docs(codex): document token sync and dependent-process diagnostics"
```

---

Plan complete and saved to `docs/plans/2026-03-04-codex-process-diagnostics-and-token-sync.md`. Two execution options:

**1. Subagent-Driven (this session)** - I dispatch fresh subagent per task, review between tasks, fast iteration

**2. Parallel Session (separate)** - Open new session with executing-plans, batch execution with checkpoints

**Which approach?**
