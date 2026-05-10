# OpenCode Workspace Accounts Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add first-class multi-account support for the OpenCode provider by saving one OpenCode account as one selected workspace backed by one stored session credential, with provider-specific settings and menu behavior.

**Architecture:** Reuse the existing generic `tokenAccounts` store as the secret source of truth, then layer a new OpenCode-specific workspace-account model on top for identity, active selection, discovery, dashboard routing, and repair flows. Runtime fetches should always resolve through the selected saved workspace account instead of drifting to whichever workspace discovery returns first.

**Tech Stack:** Swift 6, SwiftPM, Swift Testing/XCTest, existing `SettingsStore` provider config persistence, existing OpenCode cookie import/fetch pipeline, existing token-account preview/switch UI seams

---

### Task 1: Lock the Account Contract in Tests

**Files:**
- Create: `Tests/CodexBarTests/OpenCodeWorkspaceAccountsTests.swift`
- Modify: `Tests/CodexBarTests/SettingsStoreCoverageTests.swift`
- Reference: `Sources/CodexBar/Providers/OpenCode/OpenCodeSettingsStore.swift`
- Reference: `Sources/CodexBarCore/Providers/OpenCode/OpenCodeUsageFetcher.swift`

**Step 1: Write failing tests for the new persisted account shape**

Add tests that describe the provider-specific OpenCode workspace-account model before implementation:
- one saved account references one `tokenAccountID`
- one saved account owns one exact `workspaceID`
- active selection is by saved OpenCode account identity, not by raw token account index
- removing a referenced token account invalidates or removes the dependent OpenCode workspace account

**Step 2: Add failing settings tests for migration/fallback behavior**

Cover:
- provider-level `workspaceID` fallback remains readable for legacy state
- selected saved workspace account overrides provider-level `workspaceID`
- no saved account means existing loose behavior still works until migration completes

**Step 3: Run focused tests and confirm they fail for the expected reason**

Run:

```bash
swift test --filter OpenCodeWorkspaceAccountsTests
swift test --filter SettingsStoreCoverageTests
```

Expected:
- new OpenCode workspace-account tests fail because the model/helpers do not exist yet

**Step 4: Commit nothing yet**

This task is complete only when the tests describe the new behavior clearly enough to drive implementation.

### Task 2: Add the OpenCode Workspace-Account Model and Persistence

**Files:**
- Create: `Sources/CodexBarCore/Providers/OpenCode/OpenCodeWorkspaceAccounts.swift`
- Modify: `Sources/CodexBarCore/Config/CodexBarConfig.swift`
- Modify: `Sources/CodexBarCore/Config/CodexBarConfigValidation.swift`
- Modify: `Sources/CodexBarCore/Providers/ProviderSettingsSnapshot.swift`
- Test: `Tests/CodexBarTests/OpenCodeWorkspaceAccountsTests.swift`

**Step 1: Define the persisted account types**

Add small, typed models for:
- `OpenCodeWorkspaceAccount`
- `OpenCodeWorkspaceAccountData`
- any small helper types needed for validation/selection

The persisted shape should include:
- stable account ID
- `tokenAccountID`
- `label`
- `workspaceID`
- `workspaceLabel`
- optional owner/discovery hints
- timestamps needed for display/repair flows

**Step 2: Wire the new shape into provider config**

Update provider config models so OpenCode can persist workspace accounts alongside existing provider config fields.

Requirements:
- no impact on unrelated providers
- legacy config remains readable
- validation rejects malformed workspace-account references where possible

**Step 3: Add focused normalization helpers**

Implement helpers for:
- resolving active saved OpenCode account
- finding an account by ID
- pruning or invalidating accounts that reference missing token accounts

Keep these helpers near the OpenCode account model, not scattered across the app layer.

**Step 4: Run focused tests**

Run:

```bash
swift test --filter OpenCodeWorkspaceAccountsTests
```

Expected:
- workspace-account model tests pass

**Step 5: Commit**

```bash
git add Sources/CodexBarCore/Providers/OpenCode/OpenCodeWorkspaceAccounts.swift Sources/CodexBarCore/Config/CodexBarConfig.swift Sources/CodexBarCore/Config/CodexBarConfigValidation.swift Sources/CodexBarCore/Providers/ProviderSettingsSnapshot.swift Tests/CodexBarTests/OpenCodeWorkspaceAccountsTests.swift Tests/CodexBarTests/SettingsStoreCoverageTests.swift
git commit -m "feat(opencode): add workspace account persistence"
```

### Task 3: Build Workspace Discovery and Manual Fallback Parsing

**Files:**
- Create: `Sources/CodexBarCore/Providers/OpenCode/OpenCodeWorkspaceDiscovery.swift`
- Modify: `Sources/CodexBarCore/Providers/OpenCode/OpenCodeUsageFetcher.swift`
- Modify: `Sources/CodexBarCore/Providers/OpenCode/OpenCodeWebCookieSupport.swift`
- Create: `Tests/CodexBarTests/OpenCodeWorkspaceDiscoveryTests.swift`

**Step 1: Write failing discovery tests**

Cover:
- parsing multiple accessible workspaces from the current OpenCode discovery source
- normalizing a raw `wrk_...` ID
- normalizing a full workspace URL
- retaining stable workspace labels
- returning a recoverable failure when discovery cannot enumerate workspaces

**Step 2: Implement a small discovery fetcher**

Add a focused OpenCode discovery component that:
- accepts the same normalized request cookie header used by runtime fetches
- enumerates accessible workspaces
- returns stable metadata for user selection

Do not mix this logic into the UI layer.

**Step 3: Keep manual fallback explicit**

Add helpers that:
- accept raw `wrk_...` IDs
- accept full workspace URLs
- reject malformed values early

Manual entry must remain available even if discovery fails.

**Step 4: Re-run focused tests**

Run:

```bash
swift test --filter OpenCodeWorkspaceDiscoveryTests
swift test --filter OpenCodeUsageParserTests
```

Expected:
- discovery tests pass
- existing OpenCode parsing tests remain green

**Step 5: Commit**

```bash
git add Sources/CodexBarCore/Providers/OpenCode/OpenCodeWorkspaceDiscovery.swift Sources/CodexBarCore/Providers/OpenCode/OpenCodeUsageFetcher.swift Sources/CodexBarCore/Providers/OpenCode/OpenCodeWebCookieSupport.swift Tests/CodexBarTests/OpenCodeWorkspaceDiscoveryTests.swift
git commit -m "feat(opencode): add workspace discovery and normalization"
```

### Task 4: Add OpenCode-Specific SettingsStore Account Helpers

**Files:**
- Modify: `Sources/CodexBar/Providers/OpenCode/OpenCodeSettingsStore.swift`
- Modify: `Tests/CodexBarTests/SettingsStoreCoverageTests.swift`
- Modify: `Tests/CodexBarTests/OpenCodeStatusMenuTests.swift`

**Step 1: Add OpenCode-specific account accessors**

Implement `SettingsStore` helpers for:
- reading saved OpenCode workspace accounts
- selecting the active OpenCode workspace account
- adding/saving a workspace account from `tokenAccountID + workspace`
- editing account label/workspace metadata
- removing a workspace account
- repairing/rebinding workspace metadata when discovery changes

**Step 2: Make dashboard routing resolve through the saved account**

Update `opencodeDashboardURLOverride` so the selected saved OpenCode workspace account wins over loose provider-level config.

Fallback order should be:
1. selected saved OpenCode account
2. legacy/manual provider-level `workspaceID`
3. no override

**Step 3: Add migration behavior**

When appropriate, support a lightweight migration path from:
- existing token account + provider-level workspace ID

Do not silently invent workspace bindings for multiple old token accounts.

**Step 4: Run focused tests**

Run:

```bash
swift test --filter SettingsStoreCoverageTests
swift test --filter OpenCodeStatusMenuTests
```

Expected:
- OpenCode settings selection and dashboard URL tests pass

**Step 5: Commit**

```bash
git add Sources/CodexBar/Providers/OpenCode/OpenCodeSettingsStore.swift Tests/CodexBarTests/SettingsStoreCoverageTests.swift Tests/CodexBarTests/OpenCodeStatusMenuTests.swift
git commit -m "feat(opencode): add workspace account settings helpers"
```

### Task 5: Replace the Generic Settings Row With an OpenCode Accounts Section

**Files:**
- Modify: `Sources/CodexBar/PreferencesProvidersPane.swift`
- Modify: `Sources/CodexBar/PreferencesProviderDetailView.swift`
- Modify: `Sources/CodexBar/PreferencesProviderSettingsRows.swift`
- Modify: `Sources/CodexBar/Providers/OpenCode/OpenCodeProviderImplementation.swift`
- Create if needed: `Sources/CodexBar/Providers/OpenCode/OpenCodeAccountsSection.swift`
- Modify: `Tests/CodexBarTests/ProvidersPaneCoverageTests.swift`

**Step 1: Add a provider-specific OpenCode Accounts section descriptor or view model**

Do not force this through the generic token-account row if it makes the flow awkward.

The OpenCode settings surface needs:
- active account picker
- list of saved workspace accounts
- import/add account flow
- rediscover/repair actions
- remove action
- manual workspace fallback path

**Step 2: Keep secret handling delegated to the existing token-account storage**

The settings UI can create the underlying token account as part of the add-account flow, but it should present the product as “workspace accounts,” not “paste raw cookies.”

**Step 3: Preserve the rest of the OpenCode settings surface**

Keep existing settings such as cookie source and manual workspace override only where still needed for fallback/debug behavior. Remove or demote redundant UI if the new account model supersedes it.

**Step 4: Run focused UI/state tests**

Run:

```bash
swift test --filter ProvidersPaneCoverageTests
swift test --filter PreferencesPaneSmokeTests
```

Expected:
- preferences coverage remains green
- OpenCode provider now renders the new account surface

**Step 5: Commit**

```bash
git add Sources/CodexBar/PreferencesProvidersPane.swift Sources/CodexBar/PreferencesProviderDetailView.swift Sources/CodexBar/PreferencesProviderSettingsRows.swift Sources/CodexBar/Providers/OpenCode/OpenCodeProviderImplementation.swift Sources/CodexBar/Providers/OpenCode/OpenCodeAccountsSection.swift Tests/CodexBarTests/ProvidersPaneCoverageTests.swift
git commit -m "feat(opencode): add workspace account settings UI"
```

### Task 6: Make Menu Preview and Switching Workspace-Account Aware

**Files:**
- Modify: `Sources/CodexBar/StatusItemController+TokenAccountsMenu.swift`
- Modify: `Sources/CodexBar/StatusItemController+Menu.swift`
- Modify: `Sources/CodexBar/StatusItemController+Actions.swift`
- Modify: `Sources/CodexBar/UsageStore+TokenAccounts.swift`
- Modify: `Tests/CodexBarTests/OpenCodeStatusMenuTests.swift`
- Create: `Tests/CodexBarTests/OpenCodeAccountMenuStateTests.swift`

**Step 1: Add a workspace-account projection for OpenCode**

Menu switching should render saved OpenCode workspace accounts, not loose token accounts.

Projection must provide:
- visible label
- linked token account
- workspace ID
- active selection
- preview selection

**Step 2: Keep preview fetches account-scoped**

When previewing/switching OpenCode accounts:
- use the linked credential
- use the saved workspace ID
- never allow runtime fallback to a different discovered workspace

**Step 3: Update dashboard action routing**

When the user opens the OpenCode dashboard from the menu, route directly to the selected saved workspace account's `/go` page.

**Step 4: Add tests for no silent workspace drift**

Explicitly cover:
- multiple discovered workspaces returned in different order
- selected saved workspace still wins
- menu labels use saved workspace labels

**Step 5: Run focused tests**

Run:

```bash
swift test --filter OpenCodeStatusMenuTests
swift test --filter OpenCodeAccountMenuStateTests
```

Expected:
- OpenCode menu switching behaves deterministically

**Step 6: Commit**

```bash
git add Sources/CodexBar/StatusItemController+TokenAccountsMenu.swift Sources/CodexBar/StatusItemController+Menu.swift Sources/CodexBar/StatusItemController+Actions.swift Sources/CodexBar/UsageStore+TokenAccounts.swift Tests/CodexBarTests/OpenCodeStatusMenuTests.swift Tests/CodexBarTests/OpenCodeAccountMenuStateTests.swift
git commit -m "feat(opencode): add workspace account menu switching"
```

### Task 7: Align Runtime Fetching With Saved Workspace Accounts

**Files:**
- Modify: `Sources/CodexBarCore/Providers/OpenCode/OpenCodeProviderDescriptor.swift`
- Modify: `Sources/CodexBarCore/Providers/OpenCode/OpenCodeUsageFetcher.swift`
- Modify: `Sources/CodexBar/UsageStore+Refresh.swift`
- Modify: `Tests/CodexBarTests/OpenCodeUsageFetcherErrorTests.swift`
- Modify: `Tests/CodexBarTests/OpenCodeUsageParserTests.swift`

**Step 1: Resolve the effective workspace from the saved account first**

Update the OpenCode fetch path so the effective workspace is chosen in this order:
1. preview/switch override from a saved OpenCode workspace account
2. selected saved OpenCode workspace account
3. legacy/manual provider-level `workspaceID`
4. discovery fallback only for unsaved legacy states

**Step 2: Preserve current cookie and retry behavior**

Do not regress:
- manual cookie semantics
- cached cookie reuse
- invalid-credential retry behavior for non-manual cookie sources

**Step 3: Add regression tests for deterministic workspace routing**

Cover:
- saved workspace used even when discovery returns another workspace first
- saved workspace missing produces a repair/error state instead of silent substitution
- manual workspace fallback still works

**Step 4: Run focused OpenCode tests**

Run:

```bash
swift test --filter OpenCodeUsageFetcherErrorTests
swift test --filter OpenCodeUsageParserTests
swift test --filter OpenCodeWebCookieSupportTests
```

Expected:
- all focused OpenCode fetch/path tests pass

**Step 5: Commit**

```bash
git add Sources/CodexBarCore/Providers/OpenCode/OpenCodeProviderDescriptor.swift Sources/CodexBarCore/Providers/OpenCode/OpenCodeUsageFetcher.swift Sources/CodexBar/UsageStore+Refresh.swift Tests/CodexBarTests/OpenCodeUsageFetcherErrorTests.swift Tests/CodexBarTests/OpenCodeUsageParserTests.swift Tests/CodexBarTests/OpenCodeWebCookieSupportTests.swift
git commit -m "feat(opencode): route fetches through saved workspace accounts"
```

### Task 8: Documentation Pass

**Files:**
- Modify: `docs/opencode.md`
- Modify: `docs/configuration.md`
- Modify: `docs/ui.md`
- Reference: `docs/plans/2026-05-10-opencode-workspace-accounts-design.md`

**Step 1: Update operator docs**

Document:
- what an OpenCode account means now
- import/discovery/manual fallback behavior
- saved workspace determinism
- repair flow expectations

**Step 2: Update config docs**

Document the new persisted OpenCode workspace-account shape and how it relates to `tokenAccounts`.

**Step 3: Update UI docs**

Document the provider-specific account surface and how OpenCode differs from generic token-account providers.

**Step 4: Commit**

```bash
git add docs/opencode.md docs/configuration.md docs/ui.md
git commit -m "docs(opencode): document workspace accounts"
```

### Task 9: Full Verification

**Files:**
- No new product files expected

**Step 1: Run formatting and lint checks**

Run:

```bash
swiftformat Sources Tests
swiftlint --strict
pnpm check
```

Expected:
- formatting and lint checks pass

**Step 2: Run focused OpenCode tests first**

Run:

```bash
swift test --filter OpenCode
```

Expected:
- all OpenCode-specific tests pass

**Step 3: Run full test suite**

Run:

```bash
swift test
```

Expected:
- full suite passes, or any unrelated pre-existing failures are documented explicitly

**Step 4: Run the required app rebuild cycle**

Run:

```bash
./Scripts/compile_and_run.sh
```

Expected:
- build, package, relaunch, and running-app verification succeed

**Step 5: Spot-check the user-visible flow**

Verify in the rebuilt app:
- OpenCode provider shows the new Accounts UI
- saved workspace labels appear correctly
- switching accounts updates the dashboard destination and preview state
- invalid workspace states surface repair behavior instead of drifting

### Task 10: Final Diff Review

**Files:**
- Review the complete diff before handoff

**Step 1: Confirm scope stayed narrow**

Expected primary touch areas:
- `Sources/CodexBarCore/Providers/OpenCode/*`
- `Sources/CodexBar/Providers/OpenCode/*`
- targeted settings/menu wiring
- targeted OpenCode tests
- OpenCode docs

**Step 2: Confirm no accidental provider regressions**

Specifically re-check:
- generic token-account providers still render and switch normally
- Codex account-specific flows were not broadened or broken
- provider-level `workspaceID` fallback still behaves for legacy OpenCode state

**Step 3: Prepare final handoff**

The final implementation handoff should include:
- summary of account model changes
- commands run
- whether any repair/migration edge cases remain
- screenshots or screen recording for the new OpenCode accounts flow if UI changed visibly
