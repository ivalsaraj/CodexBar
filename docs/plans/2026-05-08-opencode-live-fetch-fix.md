# OpenCode Live Fetch Fix Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Update the OpenCode provider to fetch usage from the current live OpenCode workspace flow so OpenCode usage appears again without affecting fork-specific custom behavior.

**Architecture:** Keep the upstream auth and cookie handling already backported, but replace the stale OpenCode subscription fetch path with a page-driven workspace usage fetch modeled on the current OpenCode site contract. Constrain the implementation to the OpenCode provider surface plus focused registration/tests so unrelated fork customizations and non-OpenCode providers remain unchanged.

**Tech Stack:** Swift 6, SwiftPM, XCTest/Testing, `URLSession`, existing `OpenCodeWebCookieSupport`, existing `CookieHeaderCache`, CodexBar provider descriptor pipeline

---

### Task 1: Capture the Current Contract as Tests

**Files:**
- Modify: `Tests/CodexBarTests/OpenCodeUsageFetcherErrorTests.swift`
- Reference: `Sources/CodexBarCore/Providers/OpenCode/OpenCodeUsageFetcher.swift`
- Reference: `Sources/CodexBarCore/Providers/OpenCodeGo/OpenCodeGoUsageFetcher.swift`

**Step 1: Capture the real live workspace-page payload before writing parser fixtures**

Before changing OpenCode parser tests, capture the current OpenCode workspace usage page from this machine using the already-working cookie/workspace inputs, then redact it into a stable fixture shape for tests.

Requirements:
- use the actual live OpenCode workspace page payload as the source of truth
- remove secrets/cookies and any unstable personal identifiers from the saved fixture
- record enough of the embedded payload to prove the real key names, nesting, and escaping strategy

This step is complete only when the test fixture is derived from the live page contract, not an inferred OpenCode Go-like shape.

**Step 2: Replace the stale `/_server` subscription-path tests with page-based expectations**

Update `Tests/CodexBarTests/OpenCodeUsageFetcherErrorTests.swift` so it no longer asserts the old OpenCode subscription transport contract as the intended behavior.

Retire or rewrite existing assertions that depend on:
- `/_server` as the OpenCode usage fetch path
- billing-page referers
- GET/POST subscription fallback as the primary success path

The rewritten tests should assert the new workspace-page fetch behavior instead of preserving the stale contract beside it.

**Step 3: Add failing parser and transport tests for the current live shape**

Add focused tests that encode the expected behavior before implementation:
- a workspace usage page fixture that contains the current nested usage payload shape
- a page fixture where `billing` no longer contains usable quota data
- a fallback fixture where a workspace page exists but expected usage fields are missing
- a workspace override normalization case using full workspace URLs

Add assertions for:
- successful parsing from the workspace page HTML/embedded payload
- no dependence on the old billing `/_server` subscription payload
- correct error when usage fields are absent

**Step 4: Run the new OpenCode tests and confirm they fail for the right reason**

Run:

```bash
swift test --filter OpenCodeUsageFetcherErrorTests
```

Expected:
- at least one new OpenCode test fails because the current fetcher still expects the old subscription contract

**Step 5: Commit nothing yet**

This task is complete only when the failures prove the plan is testing the stale contract, not unrelated repo issues.

### Task 2: Refactor OpenCode Fetching to Use the Live Workspace Page

**Files:**
- Modify: `Sources/CodexBarCore/Providers/OpenCode/OpenCodeUsageFetcher.swift`
- Modify: `docs/opencode.md`
- Reference: `Sources/CodexBarCore/Providers/OpenCodeGo/OpenCodeGoUsageFetcher.swift`

**Step 1: Keep workspace discovery, replace subscription retrieval**

Preserve:
- cookie normalization via `OpenCodeWebCookieSupport`
- workspace ID normalization
- workspace discovery fallback logic if no explicit workspace override is provided

Replace:
- `fetchSubscriptionInfo(...)`
- billing-page referer assumptions
- the hard dependency on the old subscription `serverID`

with:
- a `fetchUsagePage(...)` or equivalently named method
- page fetch from the current workspace route
- page parsing that accepts the current embedded usage payload shape

**Step 2: Minimize blast radius**

Do not change:
- non-OpenCode providers
- shared settings behavior unrelated to OpenCode
- fork-specific menu, account, or widget behavior outside already-added OpenCode/OpenCode Go support

Do not introduce:
- new dependencies
- broad provider registry refactors
- unrelated cleanup

**Step 3: Re-run the focused OpenCode tests**

Run:

```bash
swift test --filter OpenCodeUsageFetcherErrorTests
```

Expected:
- the new OpenCode tests now pass

**Step 4: Update the OpenCode operator docs to match the new contract**

Update `docs/opencode.md` so it no longer describes the old billing `/_server` subscription path as the primary usage source. Document the current workspace-page usage flow, any remaining workspace lookup behavior, and the current troubleshooting expectations for cookie/import failures.

### Task 3: Align the Descriptor/Error Flow With the New Fetch Path

**Files:**
- Modify: `Sources/CodexBarCore/Providers/OpenCode/OpenCodeProviderDescriptor.swift`
- Modify: `Sources/CodexBarCore/Providers/OpenCode/OpenCodeUsageFetcher.swift`
- Reference: `Sources/CodexBarCore/Providers/OpenCode/OpenCodeWebCookieSupport.swift`

**Step 1: Preserve current retry semantics**

Keep the existing behavior where:
- invalid credentials trigger cached-cookie clearing only for non-manual cookie sources
- manual cookies do not silently fall back to browser imports

Confirm the new fetch path still maps:
- signed-out/invalid session responses to `invalidCredentials`
- missing usage payloads to parse/API errors with actionable messages

**Step 2: Remove obsolete assumptions only if no longer used**

If the old OpenCode subscription `serverID` and related helpers are no longer referenced after the page-based refactor, remove them from `OpenCodeUsageFetcher.swift`.

If any old parsing branches are retained for backward compatibility, keep them isolated and clearly secondary to the new page-based parser.

**Step 3: Re-run focused tests again**

Run:

```bash
swift test --filter OpenCodeUsageFetcherErrorTests
swift test --filter OpenCodeWebCookieSupportTests
```

Expected:
- both OpenCode fetcher and cookie-support tests pass

### Task 4: Verify Live CLI Behavior End-to-End

**Files:**
- Modify only if needed: `Sources/CodexBarCore/Providers/OpenCode/OpenCodeUsageFetcher.swift`
- Verify: `Sources/CodexBarCLI/CLIUsageCommand.swift`

**Step 1: Run a live CLI probe with the real provider**

Run:

```bash
swift run CodexBarCLI usage --provider opencode --format json --pretty --log-level debug -v
```

Expected:
- no `HTTP 500: HTTPError` from the stale subscription path
- either a valid usage payload or a newer, more specific error that points to a different live-site mismatch

**Step 2: If live output exposes a second contract mismatch, patch only that mismatch**

Allowed:
- one additional OpenCode fetcher/parser adjustment that is directly supported by live output

Not allowed:
- speculative refactors
- expanding scope into unrelated providers or shared infrastructure

**Step 3: Re-run the same live CLI probe**

Run the same command until:
- it returns valid OpenCode usage output, or
- it reaches a clearly different blocker that needs a new plan

### Task 5: Full Repo Verification and App Validation

**Files:**
- No new product files expected
- Optional test additions only if they directly cover the final OpenCode parser shape

**Step 1: Run repo checks**

Run:

```bash
swiftformat Sources Tests
swiftlint --strict
pnpm check
swift build
```

Expected:
- Swift format/lint pass
- package-manager check pass
- build succeeds

**Step 2: Run the project-required app cycle**

Run:

```bash
./Scripts/compile_and_run.sh
```

Expected:
- build, package, relaunch succeed
- app reports `OK: CodexBar is running.`

**Step 3: Validate the actual app path after relaunch**

After `./Scripts/compile_and_run.sh` finishes, validate the user-visible app path and not just the shared fetcher path:
- confirm the running app can still load the OpenCode provider without regressing the store/descriptor integration
- capture evidence from the rebuilt app path or an equivalent app-facing probe so the fix is proven beyond `CodexBarCLI`

Expected:
- the rebuilt app reflects the new OpenCode usage result instead of the stale subscription failure

**Step 4: Run `swift test` and document any unrelated pre-existing failures**

Run:

```bash
swift test
```

Expected:
- if unrelated pre-existing test failures remain, document them explicitly and confirm OpenCode-specific tests passed

### Task 6: Final Review and Handoff

**Files:**
- Verify: `docs/opencode.md`
- Summarize changes in final handoff, not via broad code churn

**Step 1: Diff review**

Verify the final diff is mostly confined to:
- `Sources/CodexBarCore/Providers/OpenCode/*`
- targeted OpenCode tests
- `docs/opencode.md`
- only minimal registration/wiring touched if required

**Step 2: Confirm custom fork protections**

Before handoff, explicitly verify:
- no unrelated custom files were reverted
- no non-OpenCode behavior was intentionally changed
- widget and settings customizations still match the branch baseline outside the approved OpenCode support additions

**Step 3: Final handoff summary**

Report:
- what changed
- what evidence confirms the fix
- whether live OpenCode now works
- any remaining upstream-vs-local divergence

**Step 4: Commit**

Only after verification is green:

```bash
git add Sources/CodexBarCore/Providers/OpenCode \
        Tests/CodexBarTests/OpenCodeUsageFetcherErrorTests.swift \
        Tests/CodexBarTests/OpenCodeWebCookieSupportTests.swift \
        docs/opencode.md
git commit -m "Fix OpenCode live usage fetch flow"
```

Use a more complete scoped commit if additional minimal wiring files are changed.
