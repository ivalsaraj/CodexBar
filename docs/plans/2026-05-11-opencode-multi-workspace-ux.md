# OpenCode Multi-Workspace UX Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make OpenCode feel cookie-free in normal use by auto-importing all discovered workspaces from one OpenCode login, allowing manual workspace add by workspace ID alone, and adding a widget switcher for per-workspace usage.

**Architecture:** Keep one OpenCode session credential in the existing `tokenAccounts` store, but treat discovered OpenCode workspaces as the primary product objects. Extend the OpenCode workspace-account layer so one credential can back many saved workspaces, then thread those workspace identities through settings, menu switching, widget snapshots, and widget selection state.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI, WidgetKit/AppIntents, existing `SettingsStore` provider config persistence, existing OpenCode workspace discovery pipeline, existing widget snapshot persistence

---

## Fixed Design Decisions

### Widget workspace model

Use a workspace-aware widget entry model for OpenCode:
- allow multiple `WidgetSnapshot.ProviderEntry` values for `.opencode`
- add `accountID: UUID?` and `accountLabel: String?` to widget entries
- treat OpenCode widget selection as `(provider, accountID)` rather than provider-only
- keep `accountID == nil` for non-OpenCode providers so other widget providers stay unchanged

This keeps the widget switcher scoped to the saved OpenCode workspace identity instead of forcing provider-level ambiguity.

### Save callback contract

The `OpenCodeAccountsSectionView` save callback must become result-driven:
- change from `(OpenCodeAccountDraft) async -> Void`
- to `(OpenCodeAccountDraft) async -> OpenCodeAccountSaveResult`

The UI must only reset its form on explicit success. Failure, duplicate/no-op, and missing-credential states must keep the typed values and display a visible notice.

### Import current login flow

The primary OpenCode import path should be:
1. import the current OpenCode browser session
2. save or reuse the `.opencode` token account
3. discover all accessible OpenCode workspaces
4. bulk save all discovered workspaces with deduping
5. preserve the current active workspace when possible, otherwise select the first discovered workspace
6. return a typed result and success/error notice to the Accounts section

This import path is the default steady-state UX and should replace cookie re-entry as the main workflow.

## Product Decision

**Recommended approach:** OpenCode should become “workspace-first.”

That means:
- importing one OpenCode login should discover all accessible workspaces and save them all automatically
- the Accounts section should show those workspaces directly
- manual add should accept a `wrk_...` ID or workspace URL only and reuse the current OpenCode credential
- the widget should switch between saved OpenCode workspaces without requiring cookie re-entry

## Alternative Approaches Considered

### 1. Recommended: Workspace-first auto-import

- One credential can own many saved OpenCode workspaces
- Import adds every discovered workspace automatically
- Manual add only needs a workspace ID and reuses the saved credential
- Widget switcher operates on saved workspace accounts

**Why this is the recommendation:** It matches the user mental model and removes cookie handling from steady-state use.

### 2. Minimal patch: Keep the current form but allow rebinding

- Keep the existing “Accounts” form mostly intact
- Add a way to reuse an already-bound credential
- Do not auto-import every discovered workspace
- Leave widget provider-level only

**Why not recommended:** It fixes the bug but not the product problem.

### 3. Full generic account-aware widget system

- Generalize widgets around “provider source identities” for all providers
- Use the same abstraction for OpenCode workspaces and future provider subaccounts

**Why not recommended now:** It is broader than the immediate need and will slow down the OpenCode fix.

---

### Task 1: Lock the Multi-Workspace Contract in Tests

**Files:**
- Modify: `Tests/CodexBarTests/SettingsStoreCoverageTests.swift`
- Modify: `Tests/CodexBarTests/ProvidersPaneCoverageTests.swift`
- Modify: `Tests/CodexBarTests/OpenCodeStatusMenuTests.swift`
- Create: `Tests/CodexBarTests/OpenCodeWidgetSnapshotTests.swift`
- Reference: `Sources/CodexBar/PreferencesProvidersPane.swift`
- Reference: `Sources/CodexBar/Providers/OpenCode/OpenCodeSettingsStore.swift`
- Reference: `Sources/CodexBar/UsageStore+WidgetSnapshot.swift`
- Reference: `Sources/CodexBarWidget/CodexBarWidgetProvider.swift`

**Step 1: Write failing tests for bulk workspace import**

Add tests that describe the desired contract:
- one imported OpenCode credential can save multiple `OpenCodeWorkspaceAccount`s
- bulk import saves all discovered workspaces from one credential in one action
- duplicate imports do not create duplicate workspace accounts for the same `workspaceID + tokenAccountID`
- active selection stays stable after bulk import
- tests may need small signature updates after Task 2 finalizes the exact result type and helper API surface

**Step 2: Write failing tests for manual workspace-ID-only add**

Cover:
- manual add accepts a raw `wrk_...` ID
- manual add accepts a full workspace URL
- manual add reuses the active OpenCode credential without requiring a new cookie
- if there is no reusable OpenCode credential, the UI shows a clear action-required notice instead of silently clearing the form

**Step 3: Write failing tests for the current UX bug**

Cover:
- a failed add attempt preserves the typed workspace ID
- the Accounts section shows the failure notice
- the form does not reset on failure

**Step 4: Write failing tests for widget workspace switching**

Cover:
- widget snapshot can carry multiple OpenCode workspace entries
- widget selection can target a specific OpenCode workspace account
- switching OpenCode workspaces in the widget changes the displayed usage rows

**Step 5: Run focused tests and confirm they fail for the expected reason**

Run:

```bash
swift test --filter SettingsStoreCoverageTests
swift test --filter ProvidersPaneCoverageTests
swift test --filter OpenCodeStatusMenuTests
swift test --filter OpenCodeWidgetSnapshotTests
```

Expected:
- new tests fail because bulk import, credential reuse, failure-state preservation, and widget workspace selection are not implemented yet

**Step 6: Commit nothing yet**

This task is complete only when the tests describe the desired experience clearly enough to drive implementation.

### Task 2: Add Bulk Import and Credential-Reuse Helpers

**Files:**
- Modify: `Sources/CodexBar/Providers/OpenCode/OpenCodeSettingsStore.swift`
- Modify: `Sources/CodexBar/SettingsStore+TokenAccounts.swift`
- Modify: `Sources/CodexBarCore/Providers/OpenCode/OpenCodeWorkspaceAccounts.swift`
- Modify: `Tests/CodexBarTests/SettingsStoreCoverageTests.swift`

**Step 1: Write the failing helper-level tests first**

Add tests for:
- saving many workspace accounts for one credential
- finding the reusable OpenCode credential for manual workspace add
- deduping an existing saved workspace account
- preserving active selection when new workspaces are added

**Step 2: Implement minimal settings helpers**

Add or extend helpers for:
- bulk saving discovered workspaces for one `tokenAccountID`
- resolving the “current reusable OpenCode credential”
- adding one workspace account by `workspaceID` only
- updating existing workspace metadata during rediscovery
- deduping by `(tokenAccountID, workspaceID)`

“Reusable OpenCode credential” means any saved `.opencode` token account, whether already bound to saved workspaces or still unbound. Prefer the currently active/selected OpenCode credential when there is more than one.

**Step 3: Make failure-state behavior explicit**

Add a result type or helper contract so the UI can distinguish:
- saved successfully
- duplicate/no-op
- missing reusable credential
- invalid workspace ID
- discovery failure

Do not force the UI to infer success from side effects.

Make this explicit in the view API too:
- update `OpenCodeAccountsSectionView.saveAccount`
- update the `PreferencesProvidersPane.saveOpenCodeAccount(_:)` call site
- write the failure-preserves-form test against the new result-driven contract

**Step 4: Run focused tests**

Run:

```bash
swift test --filter SettingsStoreCoverageTests
```

Expected:
- settings helper tests pass

Also verify bulk save dedupes correctly against workspace accounts already created by `ensureOpenCodeWorkspaceAccountMigrationIfNeeded()`.

**Step 5: Commit**

```bash
git add Sources/CodexBar/Providers/OpenCode/OpenCodeSettingsStore.swift Sources/CodexBar/SettingsStore+TokenAccounts.swift Sources/CodexBarCore/Providers/OpenCode/OpenCodeWorkspaceAccounts.swift Tests/CodexBarTests/SettingsStoreCoverageTests.swift
git commit -m "feat(opencode): add multi-workspace account helpers"
```

### Task 3: Replace the Cookie-Oriented Settings Flow With Workspace Import UX

**Files:**
- Modify: `Sources/CodexBar/PreferencesProvidersPane.swift`
- Modify: `Sources/CodexBar/Providers/OpenCode/OpenCodeAccountsSection.swift`
- Modify: `Sources/CodexBar/Providers/OpenCode/OpenCodeProviderImplementation.swift`
- Modify: `Tests/CodexBarTests/ProvidersPaneCoverageTests.swift`

**Step 1: Write failing UI-state tests**

Cover:
- importing the current OpenCode login auto-saves all discovered workspaces
- the Accounts section shows all discovered workspaces immediately
- manual workspace add only requires a workspace ID when a reusable credential exists
- the form preserves the entered workspace ID on failure
- the old “new credential cookie” path is hidden or demoted once a reusable OpenCode credential exists

**Step 2: Reshape the OpenCode Accounts section**

Change the UI so it centers these actions:
- `Import current login`
- `Refresh workspaces`
- saved workspace list
- `Add workspace by ID`

The default steady-state UI should not ask for a cookie.

**Step 3: Implement auto-import-all behavior**

Implement a concrete `Import current login` path that does exactly this:
1. call `OpenCodeCookieImporter.importSession()` and surface a clear notice when no OpenCode browser session is available
2. save or reuse the `.opencode` token account for that imported credential
3. call `OpenCodeWorkspaceDiscovery.discoverWorkspaces(cookieHeader:)`
4. bulk save all discovered workspaces for that credential with deduping by `(tokenAccountID, workspaceID)`
5. preserve the current active workspace when still valid, otherwise select the first discovered workspace if nothing is active
6. return a success/error result and notice such as `3 workspaces imported`, `All workspaces already saved`, or a discovery/import failure message

**Step 4: Implement manual workspace-ID-only add**

Manual add should:
- accept `wrk_...` or workspace URL
- reuse the current OpenCode credential
- save the workspace account without re-pasting a cookie

If there is no reusable credential, show a clear notice such as:
- “Import your current OpenCode login first.”

**Step 5: Fix the failure-state UX bug**

On failure:
- keep the typed workspace ID in the form
- keep the typed workspace label in the form
- keep the notice visible
- do not clear the fields until success

For power users and fallback/debug cases, decide explicitly whether raw cookie paste is:
- removed entirely
- hidden behind an advanced disclosure
- or preserved as a secondary fallback path

Do not leave this ambiguous during implementation.

**Step 6: Run focused tests**

Run:

```bash
swift test --filter ProvidersPaneCoverageTests
swift test --filter OpenCodeStatusMenuTests
```

Expected:
- settings-surface tests pass
- OpenCode menu tests stay green

**Step 7: Commit**

```bash
git add Sources/CodexBar/PreferencesProvidersPane.swift Sources/CodexBar/Providers/OpenCode/OpenCodeAccountsSection.swift Sources/CodexBar/Providers/OpenCode/OpenCodeProviderImplementation.swift Tests/CodexBarTests/ProvidersPaneCoverageTests.swift Tests/CodexBarTests/OpenCodeStatusMenuTests.swift
git commit -m "feat(opencode): make workspace import cookie-free"
```

### Task 4: Extend Runtime and Menu Flows for Imported Workspace Sets

**Files:**
- Modify: `Sources/CodexBar/UsageStore+TokenAccounts.swift`
- Modify: `Sources/CodexBar/UsageStore+Refresh.swift`
- Modify: `Sources/CodexBar/StatusItemController+TokenAccountsMenu.swift`
- Modify: `Tests/CodexBarTests/OpenCodeStatusMenuTests.swift`

**Step 1: Write failing tests for multi-workspace reuse**

Cover:
- multiple saved OpenCode workspaces can share one credential cleanly
- menu switching works across those workspaces
- preview fetches stay pinned to the selected workspace ID
- runtime usage never drifts to discovery order after accounts are saved

**Step 2: Keep menu switching workspace-first**

Ensure the menu:
- displays saved workspaces, not cookies
- switches by workspace account ID
- caches previews by workspace account identity

**Step 3: Verify runtime routing**

Ensure runtime uses:
1. previewed workspace account
2. selected saved workspace account
3. legacy fallback only for migration/debug states

**Step 4: Run focused tests**

Run:

```bash
swift test --filter OpenCodeStatusMenuTests
swift test --filter OpenCodeUsageFetcherErrorTests
swift test --filter OpenCodeUsageParserTests
```

Expected:
- menu/runtime tests pass

**Step 5: Commit**

```bash
git add Sources/CodexBar/UsageStore+TokenAccounts.swift Sources/CodexBar/UsageStore+Refresh.swift Sources/CodexBar/StatusItemController+TokenAccountsMenu.swift Tests/CodexBarTests/OpenCodeStatusMenuTests.swift
git commit -m "feat(opencode): stabilize multi-workspace menu routing"
```

### Task 5: Add OpenCode Workspace Entries to Widget Snapshots

**Files:**
- Modify: `Sources/CodexBarCore/WidgetSnapshot.swift`
- Modify: `Sources/CodexBar/UsageStore+WidgetSnapshot.swift`
- Modify: `Tests/CodexBarTests/OpenCodeWidgetSnapshotTests.swift`
- Modify: `Tests/CodexBarTests/CodexBarWidgetProviderTests.swift`

**Step 1: Write the failing widget snapshot tests**

Cover:
- widget snapshot can encode multiple OpenCode workspace entries
- each OpenCode widget entry carries a stable saved workspace-account ID
- workspace label is available for widget display/switching

**Step 2: Extend the widget snapshot shape minimally**

Add optional fields needed for OpenCode workspace switching, such as:
- `accountID`
- `accountLabel`
- or an OpenCode-specific workspace identity block

Keep the change backward-compatible for non-OpenCode providers.

**Step 3: Persist all saved OpenCode workspaces into the snapshot**

When OpenCode has multiple saved workspace accounts:
- write one widget entry per saved workspace account
- keep other providers unchanged

**Step 4: Run focused tests**

Run:

```bash
swift test --filter OpenCodeWidgetSnapshotTests
swift test --filter CodexBarWidgetProviderTests
```

Expected:
- widget snapshot tests pass

**Step 5: Commit**

```bash
git add Sources/CodexBarCore/WidgetSnapshot.swift Sources/CodexBar/UsageStore+WidgetSnapshot.swift Tests/CodexBarTests/OpenCodeWidgetSnapshotTests.swift Tests/CodexBarTests/CodexBarWidgetProviderTests.swift
git commit -m "feat(widget): persist opencode workspace entries"
```

### Task 6: Add a Widget Workspace Switcher for OpenCode

**Files:**
- Modify: `Sources/CodexBarWidget/CodexBarWidgetProvider.swift`
- Modify: `Sources/CodexBarWidget/CodexBarWidgetViews.swift`
- Modify: `Sources/CodexBarCore/WidgetSnapshot.swift`
- Create if needed: `Tests/CodexBarTests/OpenCodeWidgetSwitcherTests.swift`
- Modify: `Tests/CodexBarTests/CodexBarWidgetProviderTests.swift`

**Step 1: Write failing widget switcher tests**

Cover:
- widget provider can choose among multiple OpenCode workspace entries
- widget selection persists a specific OpenCode workspace target
- switching the widget changes the displayed usage balance

**Step 2: Add widget selection state for OpenCode workspaces**

Extend widget selection so it can persist:
- provider
- optional OpenCode workspace account ID

Do not rewrite the whole widget system into a generic subaccount architecture unless the implementation truly needs it.

**Step 3: Add an OpenCode workspace switcher surface**

Implement the smallest widget UX that satisfies the goal:
- when provider is `.opencode` and multiple saved workspaces exist, show a switcher control for those workspaces
- use saved workspace labels for display

**Step 4: Keep non-OpenCode providers unchanged**

Do not regress the current provider switcher behavior for other widget providers.

**Step 5: Run focused tests**

Run:

```bash
swift test --filter OpenCodeWidgetSwitcherTests
swift test --filter CodexBarWidgetProviderTests
```

Expected:
- widget switching tests pass

**Step 6: Commit**

```bash
git add Sources/CodexBarWidget/CodexBarWidgetProvider.swift Sources/CodexBarWidget/CodexBarWidgetViews.swift Sources/CodexBarCore/WidgetSnapshot.swift Tests/CodexBarTests/OpenCodeWidgetSwitcherTests.swift Tests/CodexBarTests/CodexBarWidgetProviderTests.swift
git commit -m "feat(widget): add opencode workspace switcher"
```

### Task 7: Docs, Validation, and Cleanup

**Files:**
- Modify: `docs/opencode.md`
- Modify: `docs/widgets.md`
- Reference: `Scripts/compile_and_run.sh`

**Step 1: Update OpenCode docs**

Document:
- importing one OpenCode login now auto-adds all discovered workspaces
- manual add only needs workspace ID or URL
- cookies are no longer part of the normal steady-state OpenCode UX

**Step 2: Update widget docs**

Document:
- OpenCode widget switching behavior
- any limitations in compact vs switcher widget variants

**Step 3: Run validation**

Run:

```bash
swift build
swift test
pnpm check
./Scripts/compile_and_run.sh
```

Expected:
- build passes
- lint/format passes
- full test suite passes, or any unrelated pre-existing failures are documented explicitly
- app rebuilds and relaunches successfully

**Step 4: Commit**

```bash
git add docs/opencode.md docs/widgets.md
git commit -m "docs(opencode): document multi-workspace import and widget switching"
```

---

## Execution Notes

- The first milestone should be the workspace-first settings UX, because that is the primary user pain.
- The widget work should build on the saved workspace-account model rather than reintroducing cookie or provider-level ambiguity.
- The current add form bug is part of the acceptance criteria: failed manual add must preserve entered values and show a visible reason.
- If the full suite remains blocked by the existing unrelated Swift Testing/compiler failures, the execution session should record those separately rather than treating them as OpenCode regressions.
