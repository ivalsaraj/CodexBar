# OpenCode Workspace Accounts — Design Doc

**Date:** 2026-05-10
**Status:** Approved
**Scope:** Add first-class multi-account support for the OpenCode provider by modeling one saved OpenCode account as one saved workspace, while keeping the existing token-account cookie storage as the credential source of truth.

---

## Background

OpenCode already participates in CodexBar's generic token-account system:
- multiple cookie headers can be stored under `tokenAccounts`
- the active token account can be switched
- preview fetches can run account-scoped

That is not yet the same product experience as Codex.

Codex has a provider-specific account model with:
- named, stable accounts in Settings
- account-aware switching in the menu
- explicit identity ownership
- no silent drift between underlying auth states

OpenCode currently lacks that provider-specific layer. It still behaves like "multiple cookie blobs" rather than "multiple trusted accounts." The product goal is to make OpenCode feel like a first-class account provider while respecting OpenCode's real upstream contract.

Upstream OpenCode does not currently expose Codex-like multi-profile account storage. Credentials are stored in a single `~/.local/share/opencode/auth.json` keyed by provider ID, and same-provider credentials replace each other. Because of that, CodexBar should treat the most stable user-visible identity as the OpenCode workspace, not the upstream provider login itself.

---

## Product Decision

An OpenCode account in CodexBar will mean:

> one stored OpenCode session credential plus one selected OpenCode workspace

This makes the saved account stable, user-visible, and fetchable with today's OpenCode site behavior.

---

## Goals

1. Give OpenCode a provider-specific Accounts UI instead of the generic token-account row.
2. Save accounts as stable workspace identities with friendly labels.
3. Keep the existing token-account cookie/header storage as the secret source of truth.
4. Use the saved workspace ID for all runtime fetches, dashboard opens, previews, and history ownership.
5. Never silently substitute a different workspace when discovery order changes.
6. Support manual workspace repair/editing when discovery is incomplete or upstream behavior changes.

---

## Non-Goals

- Recreate Codex's live-vs-managed system-account reconciliation model.
- Add an upstream OpenCode multi-profile auth system.
- Auto-switch accounts based on quota.
- Discover or merge multiple workspaces under one higher-level "human account" object.
- Replace the existing generic token-account infrastructure for other providers.

---

## Current State

### Storage

- OpenCode credentials live in `SettingsStore.tokenAccounts(for: .opencode)`.
- The active account is selected by generic `activeIndex`.
- OpenCode-specific config only persists:
  - `cookieSource`
  - `cookieHeader`
  - `workspaceID`

### Runtime

- `OpenCodeUsageFetcher.fetchUsage(...)` discovers a workspace when none is explicitly provided.
- If no override is set, runtime can effectively depend on "first workspace returned."
- `opencodeDashboardURLOverride` uses the provider-level `workspaceID`, not a named saved account.

### UI

- Settings render OpenCode through the generic token-account row.
- Menu switching is generic and labels come from `ProviderTokenAccount.label`.
- There is no provider-owned workspace identity or repair flow.

---

## Proposed Architecture

### 1. Keep `tokenAccounts` as credential storage

`tokenAccounts(for: .opencode)` remains the only place where the imported cookie/header secret is stored.

This avoids:
- duplicating secret persistence
- inventing a second credential store
- widening the blast radius into other providers

### 2. Add provider-specific OpenCode workspace accounts

Introduce a new OpenCode-specific persisted model that maps a stored token account to a selected workspace.

Proposed shape:

```swift
struct OpenCodeWorkspaceAccount {
    let id: UUID
    let tokenAccountID: UUID
    let label: String
    let workspaceID: String
    let workspaceLabel: String
    let discoveredOwnerLabel: String?
    let addedAt: TimeInterval
    let lastValidatedAt: TimeInterval?
}
```

And a provider-owned container:

```swift
struct OpenCodeWorkspaceAccountData {
    let version: Int
    let activeAccountID: UUID?
    let accounts: [OpenCodeWorkspaceAccount]
}
```

### 3. Treat workspace identity as the stable account identity

The saved workspace ID is the primary identity for:
- settings rows
- active selection
- menu preview/switch
- dashboard destination
- plan/history ownership
- fetch routing

Saved workspace ID always wins over discovery ordering.

### 4. Add a discovery layer

Introduce a small OpenCode workspace discovery fetcher that:
- accepts the normalized request cookie header
- enumerates accessible workspaces for that session
- returns stable metadata for user selection

Proposed result shape:

```swift
struct OpenCodeDiscoveredWorkspace {
    let workspaceID: String
    let workspaceLabel: String
    let ownerLabel: String?
}
```

### 5. Resolve runtime through the selected workspace account

At runtime, OpenCode snapshot creation should resolve in this order:

1. explicit OpenCode workspace-account override for preview/switch flows
2. selected saved OpenCode workspace account
3. provider-level manual `workspaceID` only as migration/fallback
4. live discovery fallback only for unsaved/legacy states

This preserves current behavior where necessary while making saved accounts deterministic.

---

## User Flow

### Add Account

1. User opens OpenCode provider settings.
2. User clicks `Import current login`.
3. CodexBar imports the current OpenCode cookie/header from the browser or manual source.
4. CodexBar attempts workspace discovery for that credential.
5. If discovery succeeds:
   - show all discovered workspaces
   - user picks one
   - default label uses workspace name
6. If discovery fails or the desired workspace is missing:
   - allow manual workspace URL or `wrk_...` entry
   - normalize and validate the entered value
7. Save:
   - generic token account secret
   - OpenCode workspace-account metadata referencing that token account

### Switch Account

1. User selects a saved OpenCode workspace account.
2. CodexBar resolves the referenced token account.
3. Fetches and previews use that credential plus that exact workspace ID.
4. Dashboard opens `/workspace/<saved-id>/go`.

### Repair Account

If a saved workspace no longer resolves:
- show a repair state
- offer rediscovery with the saved credential
- allow manual workspace replacement
- do not silently jump to another discovered workspace

---

## UI Design

### Settings

Replace the generic OpenCode token-account row with an OpenCode-specific Accounts section.

Section behavior:
- active account picker for saved workspace accounts
- rows display saved workspace label and relevant metadata
- actions per row:
  - `Re-discover`
  - `Edit label`
  - `Repair workspace`
  - `Remove`
- `Add Account` / `Import current login` entry point

Fallback behavior:
- manual workspace URL / `wrk_...` entry remains available when discovery fails

### Menu

Reuse the current token-account switcher interaction pattern, but back it with OpenCode workspace accounts.

Display rules:
- show workspace labels first
- keep preview fetches account-scoped
- preserve the existing lightweight switcher feel

### Dashboard

OpenCode dashboard action should resolve from the selected workspace account's saved `workspaceID`, not the loose provider-level override.

---

## Data Ownership and History

OpenCode history should be owned by the saved workspace account identity, not only by provider-level state.

That means:
- preview caches should key off the saved account identity
- menu preview selection and preview snapshot overrides should key off the saved account identity
- any future utilization/history ownership should key off the saved account identity even when two accounts share one credential
- plan/utilization ownership should be extendable to workspace accounts when OpenCode gains history support
- dashboard and menu state should remain stable across cookie rediscovery

This design does not require immediate expansion of the current Codex/Claude-only history feature, but it keeps the ownership model aligned so later OpenCode history work can build on the same account identity.

---

## Migration Strategy

Existing OpenCode users may already have:
- one or more generic token accounts
- a provider-level `workspaceID`

Migration behavior:
- do not discard existing OpenCode token accounts
- if exactly one token account and one provider-level `workspaceID` exist, create one initial OpenCode workspace account from them
- if multiple token accounts exist but no saved workspace accounts exist yet, surface them as unbound credentials and require the user to bind each one through discovery or manual workspace entry; do not require re-import
- keep the provider-level `workspaceID` only as a fallback/migration seam until the provider-specific account model fully owns it

---

## Failure Modes

### Discovery fails

Cause:
- upstream contract changed
- session lacks enough data
- parsing breaks

Handling:
- allow manual workspace URL/ID entry
- save account with manual workspace
- show a recoverable notice, not a hard blocker

### Saved workspace disappears

Cause:
- workspace access removed
- workspace renamed or deleted

Handling:
- keep saved account selected
- show repair state
- do not silently switch to another workspace

### Credential expires

Handling:
- fetch fails with invalid credentials
- existing error path remains
- user re-imports current login or updates the underlying token account

### Token account removed while referenced

Handling:
- remove or invalidate the dependent OpenCode workspace account in the same mutation path
- never leave a dangling `tokenAccountID` reference

---

## Key Files Expected to Change

### New OpenCode account model and discovery
- `Sources/CodexBarCore/Providers/OpenCode/OpenCodeWorkspaceAccounts.swift`
- `Sources/CodexBarCore/Providers/OpenCode/OpenCodeWorkspaceDiscovery.swift`

### OpenCode settings/runtime wiring
- `Sources/CodexBar/Providers/OpenCode/OpenCodeSettingsStore.swift`
- `Sources/CodexBar/Providers/OpenCode/OpenCodeProviderImplementation.swift`
- `Sources/CodexBarCore/Providers/OpenCode/OpenCodeProviderDescriptor.swift`
- `Sources/CodexBarCore/Providers/OpenCode/OpenCodeUsageFetcher.swift`

### Shared UI integration points
- `Sources/CodexBar/PreferencesProvidersPane.swift`
- `Sources/CodexBar/PreferencesProviderDetailView.swift`
- `Sources/CodexBar/PreferencesProviderSettingsRows.swift`
- `Sources/CodexBar/StatusItemController+TokenAccountsMenu.swift`
- `Sources/CodexBar/StatusItemController+Actions.swift`

### Persistence/config support
- `Sources/CodexBarCore/Config/CodexBarConfig.swift`
- `Sources/CodexBarCore/Providers/ProviderSettingsSnapshot.swift`
- `Sources/CodexBarCore/Config/CodexBarConfigValidation.swift`

### Tests
- `Tests/CodexBarTests/OpenCode*`
- `Tests/CodexBarTests/SettingsStoreCoverageTests.swift`
- `Tests/CodexBarTests/ProvidersPaneCoverageTests.swift`
- `Tests/CodexBarTests/OpenCodeStatusMenuTests.swift`

---

## Why This Design

This design gives OpenCode the same user confidence that Codex has:
- stable named accounts
- explicit active selection
- no hidden switching behavior
- provider-owned repair flows

But it does so without forcing Codex's much heavier reconciliation model onto an upstream system that does not expose the same primitives.

It is the smallest architecture that makes OpenCode feel first-class and trustworthy.
