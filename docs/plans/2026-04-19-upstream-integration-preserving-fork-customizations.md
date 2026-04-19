# Upstream Integration Preserving Fork Customizations Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Bring in upstream fixes and selected new features from `upstream/main` while preserving the fork's custom Codex multi-account, token sync, dependent-process diagnostics, and utilization-history behavior.

**Architecture:** Treat upstream adoption as a staged reconciliation program, not a single merge. Land low-risk upstream changes first, then medium-risk feature buckets, and finally a guarded Codex-core integration lane where each conflicting file is reviewed against fork invariants before any upstream code is accepted.

**Tech Stack:** Swift 6, SwiftPM, XCTest, AppKit, SwiftUI, WebKit, git, ripgrep.

---

### Task 1: Freeze the fork baseline and capture invariants

**Files:**
- Modify: `docs/plans/2026-04-19-upstream-integration-preserving-fork-customizations.md`
- Reference: `AGENTS.md`
- Reference: `docs/UPSTREAM_STRATEGY.md`
- Reference: `docs/FORK_ROADMAP.md`

**Step 1: Create the integration branch**

Run:
```bash
git checkout -b codex/upstream-integration-2026-04-19
```

Expected:
- all reconciliation work happens on a dedicated branch with simple rollback to the pre-integration baseline

**Step 2: Write the preservation checklist into the working notes**

Capture these non-negotiable fork invariants:
- Codex multi-account behavior and explicit switching
- active OAuth token sync-back
- dependent-process diagnostics panel and controls
- utilization history charts and related models
- current provider-data siloing rules for Codex vs Claude

**Step 3: Run the invariant inventory search**

Run:
```bash
rg -n "multi-account|token sync|dependent process|utilization history|CodexAccount|CodexDependentProcess|ProviderUtilization" \
  Sources Tests docs
```

Expected:
- matches across the fork-only Codex account and diagnostics files

**Step 4: Record the protected file set**

Protected file groups to carry forward during all later tasks:
- `Sources/CodexBar/Providers/Codex/*`
- `Sources/CodexBar/Codex*`
- `Sources/CodexBar/StatusItemController+TokenAccountsMenu.swift`
- `Sources/CodexBar/StatusItemController+SwitcherViews.swift`
- `Sources/CodexBar/ProviderUtilization*`
- `Sources/CodexBar/UsageStore+TokenAccounts.swift`
- `Sources/CodexBarCore/Providers/Codex/*`
- matching `Tests/CodexBarTests/Codex*`

**Step 5: Commit**

```bash
git add docs/plans/2026-04-19-upstream-integration-preserving-fork-customizations.md
git commit -m "docs: add staged upstream integration plan"
```

### Task 2: Create a conflict map against upstream

**Files:**
- Reference: `git diff --name-only upstream/main..HEAD`
- Reference: `git diff --name-only HEAD..upstream/main`
- Reference: `git log --oneline HEAD..upstream/main`
- Reference: `Sources/CodexBar/*`
- Reference: `Sources/CodexBarCore/*`

**Step 1: Produce the high-conflict file list**

Run:
```bash
git diff --name-only upstream/main..HEAD > /tmp/codexbar-upstream-conflicts.txt
```

Expected:
- file list covering all divergent fork files

**Step 2: Produce the inbound upstream candidate list**

Run:
```bash
git diff --name-only HEAD..upstream/main > /tmp/codexbar-upstream-candidates.txt
git log --oneline HEAD..upstream/main > /tmp/codexbar-upstream-commits.txt
```

Expected:
- a concrete file list of what upstream has that the fork has not adopted yet
- a concrete commit list for later cherry-pick and manual-backport decisions

**Step 3: Bucket the divergent files by risk**

Use three buckets:
- Low risk: docs, release metadata, provider additions with no fork overlap
- Medium risk: shared infra, fetchers, parsers, widget/app-group paths
- High risk: Codex account/menu/state/controller files with fork customizations

**Step 4: Verify no high-risk file is scheduled for blind merge**

Run:
```bash
rg -n "Sources/CodexBar/(Codex|StatusItemController|UsageStore)|Sources/CodexBarCore/Providers/Codex" \
  /tmp/codexbar-upstream-conflicts.txt
```

Expected:
- all Codex-sensitive files identified for manual review only

**Step 5: Commit**

```bash
git add docs/plans/2026-04-19-upstream-integration-preserving-fork-customizations.md
git commit -m "docs: record upstream conflict risk buckets"
```

### Task 3: Capture the current Codex behavior baseline before integration

**Files:**
- Modify: `docs/UPSTREAM_STRATEGY.md`
- Reference: `Sources/CodexBarCore/Providers/Codex/CodexProviderDescriptor.swift`
- Reference: `Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexOAuthUsageFetcher.swift`
- Reference: `Sources/CodexBarCore/Providers/Codex/CodexWebDashboardStrategy.swift`
- Reference: `Sources/CodexBar/Providers/Codex/CodexConsumerProjection.swift`
- Reference: `Sources/CodexBar/UsageStore+OpenAIWeb.swift`

**Step 1: Document the current Codex fetch route**

Capture:
- app auto mode uses OAuth first, then CLI
- OAuth uses `https://chatgpt.com/backend-api/wham/usage` by default
- the dashboard path is separate from the main usage route

**Step 2: Document the dashboard vs menu discrepancy**

Capture:
- dashboard-backed Codex extras are gated by attachment authorization
- display-only dashboards remain visible in state but do not expose attached-only extras in the menu
- this is policy behavior, not just a rendering bug

**Step 3: Verify live Spark quota presence**

Run:
```bash
AUTH_FILE="${CODEX_HOME:-$HOME/.codex}/auth.json"
ACCESS=$(jq -r '.tokens.access_token // empty' "$AUTH_FILE")
ACCOUNT=$(jq -r '.tokens.account_id // empty' "$AUTH_FILE")
curl -sS \
  -H "Authorization: Bearer $ACCESS" \
  -H "Accept: application/json" \
  -H "User-Agent: CodexBar" \
  ${ACCOUNT:+-H "ChatGPT-Account-Id: $ACCOUNT"} \
  https://chatgpt.com/backend-api/wham/usage | jq '{plan_type, rate_limit, additional_rate_limits, credits}'
```

Expected:
- confirmation of the current live `plan_type`
- confirmation whether `additional_rate_limits` contains Spark quota data

**Step 4: Write the findings into `docs/UPSTREAM_STRATEGY.md`**

Document:
- current fetch route
- current dashboard/menu gating explanation
- whether live Spark quota is present
- which of these behaviors upstream already fixes and which still need fork work

**Step 5: Commit**

```bash
git add docs/UPSTREAM_STRATEGY.md docs/plans/2026-04-19-upstream-integration-preserving-fork-customizations.md
git commit -m "docs: capture Codex baseline before upstream integration"
```

### Task 4: Land the low-risk upstream batch first

**Files:**
- Modify: low-risk files only after explicit review
- Test: relevant lightweight tests for touched areas

**Step 1: Select upstream commits with no protected-file overlap**

Candidate areas:
- changelog and release metadata where desired
- non-Codex provider additions like Abacus or OpenCodeGo
- isolated docs and packaging fixes

**Step 2: Cherry-pick one commit at a time without committing**

Run:
```bash
git cherry-pick -n <commit>
```

Expected:
- no protected-file conflicts

**Step 3: Revert any accidental overlap before proceeding**

If the cherry-pick touches protected files, unstage those files and discard only that cherry-pick attempt, then re-apply manually from clean hunks.

**Step 4: Run focused verification for the adopted change**

Examples:
```bash
swift test --filter <RelevantTestName>
```

Expected:
- passing tests for the adopted low-risk area

**Step 5: Commit**

```bash
git add <accepted files>
git commit -m "feat: backport low-risk upstream fixes"
```

### Task 5: Backport Codex Pro Lite compatibility before broader Codex work

**Files:**
- Modify: `Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexOAuthUsageFetcher.swift`
- Modify: `Sources/CodexBarCore/Providers/Codex/CodexProviderDescriptor.swift`
- Modify: `Sources/CodexBarCore/UsageFetcher.swift`
- Add or Modify: `Sources/CodexBarCore/Providers/Codex/CodexPlanFormatting.swift`
- Test: `Tests/CodexBarTests/CodexOAuthTests.swift`
- Test: `Tests/CodexBarTests/CodexUsageFetcherFallbackTests.swift`
- Test: `Tests/CodexBarTests/CodexPlanFormattingTests.swift`

**Step 1: Write the failing tests for the live `prolite` payload**

Cover:
- `plan_type: "prolite"` decodes successfully
- OAuth mapping still returns primary and secondary windows
- auto mode falls back correctly when rate-limit windows partially decode
- plan formatting stays user-friendly

**Step 2: Run the new tests to verify they fail**

Run:
```bash
swift test --filter CodexOAuthTests
swift test --filter CodexUsageFetcherFallbackTests
swift test --filter CodexPlanFormattingTests
```

Expected:
- failures on unknown `prolite` or missing formatting behavior

**Step 3: Backport only the upstream Pro Lite handling**

Pull in:
- tolerant decode for `CodexUsageResponse`
- `prolite` plan handling
- fallback behavior from upstream commit `a1813708`

Do not pull:
- unrelated menu refactors
- non-Codex provider edits

**Step 4: Run the same tests to verify they pass**

Run:
```bash
swift test --filter CodexOAuthTests
swift test --filter CodexUsageFetcherFallbackTests
swift test --filter CodexPlanFormattingTests
```

Expected:
- all selected Codex tests pass

**Step 5: Commit**

```bash
git add Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexOAuthUsageFetcher.swift \
        Sources/CodexBarCore/Providers/Codex/CodexProviderDescriptor.swift \
        Sources/CodexBarCore/UsageFetcher.swift \
        Sources/CodexBarCore/Providers/Codex/CodexPlanFormatting.swift \
        Tests/CodexBarTests/CodexOAuthTests.swift \
        Tests/CodexBarTests/CodexUsageFetcherFallbackTests.swift \
        Tests/CodexBarTests/CodexPlanFormattingTests.swift
git commit -m "fix: backport upstream Codex Pro Lite compatibility"
```

### Task 6: Reconcile Codex web/dashboard fixes without losing fork gating

**Files:**
- Modify: `Sources/CodexBar/UsageStore+OpenAIWeb.swift`
- Modify: `Sources/CodexBar/UsageStore.swift`
- Modify: `Sources/CodexBar/Providers/Codex/CodexConsumerProjection.swift`
- Modify: `Sources/CodexBar/StatusItemController+Menu.swift`
- Modify: `Sources/CodexBar/PreferencesProvidersPane.swift`
- Test: `Tests/CodexBarTests/StatusMenuTests.swift`
- Test: `Tests/CodexBarTests/CodexConsumerProjectionTests.swift`
- Test: `Tests/CodexBarTests/CodexManagedOpenAIWebTests.swift`

**Step 1: Write characterization tests for fork-specific gating**

Protect:
- display-only dashboards stay hidden from attached-only extras
- attached dashboards still surface allowed extras
- fork account-scoped cleanup behavior remains intact

**Step 2: Run those tests to verify current baseline**

Run:
```bash
swift test --filter StatusMenuTests
swift test --filter CodexConsumerProjectionTests
swift test --filter CodexManagedOpenAIWebTests
```

Expected:
- baseline passing before adoption

**Step 3: Manually inspect upstream dashboard-related commits**

Review candidate commits:
- `719fae5c`
- `441d1a40`
- `2d070c2a`

Accept only changes that improve fetch reliability or cache behavior without altering fork account-attachment rules.

**Step 4: Re-run characterization tests**

Run:
```bash
swift test --filter StatusMenuTests
swift test --filter CodexConsumerProjectionTests
swift test --filter CodexManagedOpenAIWebTests
```

Expected:
- no regression in fork-specific dashboard gating

**Step 5: Commit**

```bash
git add Sources/CodexBar/UsageStore+OpenAIWeb.swift \
        Sources/CodexBar/UsageStore.swift \
        Sources/CodexBar/Providers/Codex/CodexConsumerProjection.swift \
        Sources/CodexBar/StatusItemController+Menu.swift \
        Sources/CodexBar/PreferencesProvidersPane.swift \
        Tests/CodexBarTests/StatusMenuTests.swift \
        Tests/CodexBarTests/CodexConsumerProjectionTests.swift \
        Tests/CodexBarTests/CodexManagedOpenAIWebTests.swift
git commit -m "fix: backport selected Codex web reliability changes"
```

### Task 7: Reconcile shared infrastructure changes in isolation

**Files:**
- Modify: `Sources/CodexBarCore/Host/PTY/TTYCommandRunner.swift`
- Modify: `Sources/CodexBarCore/Host/Process/SubprocessRunner.swift`
- Modify: `Sources/CodexBarCore/KeychainCacheStore.swift`
- Modify: `Sources/CodexBarCore/Logging/*`
- Test: `Tests/CodexBarTests/SubprocessRunnerTests.swift`
- Test: `Tests/CodexBarTests/TTYCommandRunnerTests.swift`
- Test: `Tests/CodexBarTests/KeychainCacheStoreTests.swift`

**Step 1: Add failing tests for the specific upstream bugfix you want**

Examples:
- wake-related keychain cache preservation
- subprocess exit/drain correctness
- PTY timeout/race classification

**Step 2: Run the focused tests to verify red**

Run:
```bash
swift test --filter SubprocessRunnerTests
swift test --filter TTYCommandRunnerTests
swift test --filter KeychainCacheStoreTests
```

Expected:
- at least one failing case for each selected backport

**Step 3: Backport one infra fix at a time**

Do not bundle PTY, subprocess, and keychain changes into one commit.

**Step 4: Re-run the same focused tests**

Run:
```bash
swift test --filter SubprocessRunnerTests
swift test --filter TTYCommandRunnerTests
swift test --filter KeychainCacheStoreTests
```

Expected:
- target tests pass after each small backport

**Step 5: Commit**

```bash
git add <infra files and tests>
git commit -m "fix: backport upstream process and keychain reliability updates"
```

### Task 8: Adopt medium-risk upstream features only behind explicit acceptance gates

**Files:**
- Modify: feature-specific files only
- Test: matching provider or UI tests

**Step 1: Decide feature-by-feature, not commit-by-commit**

Candidate feature buckets:
- Edge cookie import for Codex
- app-group shared defaults migration
- selected provider additions
- menu or settings polish that does not conflict with fork menu/account UX

**Step 2: For each bucket, answer three questions before coding**

Questions:
- does it touch protected Codex files
- does it change user-visible behavior in the fork’s custom surfaces
- can it be isolated behind existing settings or defaults

**Step 3: Backport only if all answers are acceptable**

Run:
```bash
git show <commit> --stat --summary
git show <commit> -- <candidate files>
```

Expected:
- precise understanding of the blast radius

**Step 4: Verify with focused tests**

Run the smallest relevant test group for that feature before committing.

**Step 5: Commit**

```bash
git add <accepted files>
git commit -m "feat: backport selected upstream <feature>"
```

### Task 9: Preserve fork-specific Codex UX with characterization tests before any menu/controller reconciliation

**Files:**
- Test: `Tests/CodexBarTests/CodexAccountSwitchTests.swift`
- Test: `Tests/CodexBarTests/CodexActiveAccountTokenSyncTests.swift`
- Test: `Tests/CodexBarTests/CodexDependentProcessProbeTests.swift`
- Test: `Tests/CodexBarTests/StatusItemControllerMenuTests.swift`
- Test: `Tests/CodexBarTests/UsageStoreHistoryRecordingTests.swift`

**Step 1: Identify current missing characterization coverage**

Add tests for:
- active account tab behavior
- token sync after OAuth refresh
- dependent-process control visibility and refresh
- utilization-history menu/chart behavior

**Step 2: Run the fork protection suite**

Run:
```bash
swift test --filter CodexAccountSwitchTests
swift test --filter CodexActiveAccountTokenSyncTests
swift test --filter CodexDependentProcessProbeTests
swift test --filter StatusItemControllerMenuTests
swift test --filter UsageStoreHistoryRecordingTests
```

Expected:
- all fork-critical behavior covered and green

**Step 3: Only after this suite is green, inspect any remaining upstream Codex menu/controller patches**

If an upstream patch overlaps:
- re-implement the narrow fix manually
- do not cherry-pick the whole refactor

**Step 4: Re-run the fork protection suite after each patch**

Use the same command set as Step 2.

**Step 5: Commit**

```bash
git add <new tests and accepted Codex patches>
git commit -m "test: lock fork-specific Codex behavior before reconciliation"
```

### Task 10: Run the full project verification gate

**Files:**
- Modify: any final follow-up fixes from verification

**Step 1: Run formatting and lint checks**

Run:
```bash
swiftformat Sources Tests
swiftlint --strict
pnpm check
```

Expected:
- no formatting or lint failures

**Step 2: Run the full Swift test suite**

Run:
```bash
swift test
```

Expected:
- full test suite passes

**Step 3: Rebuild and relaunch the app per project rule**

Run:
```bash
./Scripts/compile_and_run.sh
```

Expected:
- build succeeds
- tests succeed
- app relaunch succeeds and stays running

**Step 4: Review final diff for protected areas**

Run:
```bash
git diff --stat upstream/main..HEAD
git status --short
```

Expected:
- only intended files remain changed

**Step 5: Stage only intended files and commit**

```bash
git status --short
git add <explicitly intended files from this task>
git commit -m "chore: complete staged upstream integration pass"
```

Expected:
- no unrelated files or generated artifacts are staged

### Task 11: Document the integration outcome and remaining backlog

**Files:**
- Modify: `docs/UPSTREAM_STRATEGY.md`
- Modify: `docs/FORK_ROADMAP.md`
- Modify: `CHANGELOG.md` if user-visible behavior changed

**Step 1: Record what was adopted, skipped, and deferred**

Document:
- accepted upstream commits or features
- rejected commits with reasons
- remaining high-risk backlog

**Step 2: Add explicit notes for unresolved Spark quota display work**

Document that:
- live backend exposes `additional_rate_limits`
- current menu model still needs a dedicated Spark display design

**Step 3: Run a doc-only sanity pass**

Run:
```bash
rg -n "Pro Lite|prolite|Spark|additional_rate_limits|upstream" docs/UPSTREAM_STRATEGY.md docs/FORK_ROADMAP.md CHANGELOG.md
```

Expected:
- docs reflect actual adopted behavior and remaining work

**Step 4: Commit**

```bash
git add docs/UPSTREAM_STRATEGY.md docs/FORK_ROADMAP.md CHANGELOG.md
git commit -m "docs: record upstream integration decisions"
```
