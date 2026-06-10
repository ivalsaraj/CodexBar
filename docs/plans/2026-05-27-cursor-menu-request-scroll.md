# Cursor Menu Request Scroll Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the Cursor request detail rows in the macOS status menu scroll inside a fixed-height region while keeping the range, cycle tokens, and request count visible.

**Architecture:** This is a status-menu fix, not a WidgetKit fix. Keep the widget behavior bounded, but change the menu card's Cursor token/request section to render recent request rows in a local scroll region. Because the menu card is hosted inside an `NSMenuItem`, also adjust the view-backed menu item behavior so hovering over the scrollable card does not paint the entire card as the selected blue row and so wheel events reach the nested scroll view.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit `NSMenuItem`/`NSHostingView`, Swift Testing, SwiftPM.

---

## Current State

- Cursor request rows are currently flattened into `UsageMenuCardView.Model.TokenUsageSection.detailLines`.
- This flattening is too early for the scroll fix: the menu needs to know which rows are fixed range metadata and which rows are recent request rows without parsing display strings.
- `UsageMenuCardView.Model.cursorRecentRequestLines(...)` caps menu request detail lines to 8, so extra rows never reach the menu UI.
- `UsageMenuCardView` renders the normal single full-card menu item path. This is the path shown in the user's screenshot for Cursor.
- `UsageMenuCardCostSectionView` renders the split cost-section path used when OpenAI web menu items split a card into separate sections. Cursor does not normally use this path.
- Both menu surfaces render `detailLines` as a plain `ForEach` inside a `VStack`.
- `StatusItemController.makeMenuCardItem(...)` wraps each card section in `MenuCardSectionContainerView`.
- `menu(_:willHighlight:)` sets `menuItemHighlighted` for the whole view-backed menu item on hover.
- `MenuCardSectionContainerView` paints a blue selected background when highlighted, matching the screenshot where the whole Cursor card section turns blue.

## Ranked Hypotheses

1. If `detailLines` are rendered as a plain `VStack`, there is no scrollable view to receive wheel events, so scrolling cannot work no matter where the user hovers.
2. If the `NSMenuItem` hover highlight is active for the cost section, AppKit treats the whole card as selected and the user sees a blue row state instead of an embedded scroll interaction.
3. If SwiftUI `ScrollView` is added but `NSMenuItem`/`NSHostingView` still handles the wheel event first, the embedded scroll view may still not move.

## Task 1: Add Structured Menu Model Tests For Cursor Request Rows

**Files:**
- Modify: `Tests/CodexBarTests/MenuCardCursorRequestDetailsTests.swift`

**Step 1: Extend the existing Cursor menu-card test**

Create more than 8 `CursorRecentRequest` values and build `UsageMenuCardView.Model`.

Expected assertions:
- `model.tokenUsage?.cursorRequestRange` or equivalent structured range field is populated.
- `model.tokenUsage?.cursorRequestDetails` or equivalent structured request rows preserve all menu-scroll rows, up to the existing stored cap of 30.
- the structured request rows remain newest-first.

**Step 2: Add a Type exclusion assertion**

Construct at least one request row from a model name and request count, then format it through the same menu presentation helper that the UI uses.

Expected assertions:
- the formatted line contains the model
- the formatted line contains the timestamp
- the formatted line contains token spend
- the formatted line contains `Req 1`
- no formatted line contains dashboard `Type`, `Included`, or `kind`

This guards the explicit requirement that the dashboard type column is not surfaced.

**Step 3: Run the focused test**

```bash
swift test --filter MenuCardCursorRequestDetailsTests
```

Expected: fail while the menu model still caps detail lines to 8.

## Task 2: Preserve More Structured Cursor Rows For The Menu

**Files:**
- Modify: `Sources/CodexBar/MenuCardView.swift`

**Step 1: Add structured Cursor request fields**

Extend `UsageMenuCardView.Model.TokenUsageSection` with Cursor-specific structured data, for example:

```swift
let cursorRequestRange: CursorRecentRequestRange?
let cursorRequestDetails: [CursorRecentRequest]
```

Keep existing `detailLines` available for non-Cursor providers and backward-compatible rendering.

**Step 2: Change menu row cap**

Update the Cursor menu model builder so it preserves up to 30 structured request rows, matching the stored recent request cap.

**Step 3: Keep range outside the row cap**

Keep the range as structured metadata, not part of the 30-row request cap.

**Step 4: Run the focused test**

```bash
swift test --filter MenuCardCursorRequestDetailsTests
```

Expected: pass.

## Task 3: Add A Testable Structured Menu Request Detail Presentation

**Files:**
- Modify: `Sources/CodexBar/MenuCardView.swift`
- Modify: `Tests/CodexBarTests/MenuCardCursorRequestDetailsTests.swift`

**Step 1: Add a small presentation type**

Add an internal presentation helper near the menu-card view code, for example:

```swift
struct CursorMenuRequestDetailPresentation: Equatable {
    static let maxVisibleRequestRows = 7
    let fixedRows: [String]
    let scrollRows: [String]
    let shouldScroll: Bool
}
```

The helper should accept structured Cursor data, not already-formatted strings:

```swift
init(range: CursorRecentRequestRange?, requests: [CursorRecentRequest], now: Date)
```

It should format the range line from `range` and request rows from `requests` using `UsageFormatter`, so the UI never has to parse `Range:` or infer request rows from display strings.

**Step 2: Add tests for the helper**

Expected assertions:
- with more than `maxVisibleRequestRows`, `shouldScroll == true`
- `fixedRows` contains the range line
- `scrollRows` contains all request rows up to the stored 30-row cap
- request row formatting includes model, time, token spend, and numeric request count

Non-Cursor coverage belongs to the token detail view or policy resolver, not this Cursor-only helper.

**Step 3: Run the focused test**

```bash
swift test --filter MenuCardCursorRequestDetailsTests
```

Expected: fail until the helper exists.

## Task 4: Render Cursor Request Lines In A Fixed-Height Scroll Region

**Files:**
- Modify: `Sources/CodexBar/MenuCardView.swift`

**Step 1: Define a concrete fixed-height rule**

Use one named constant for the scroll region, for example:

```swift
private static let cursorRequestScrollVisibleRows = 7
private static let cursorRequestRowHeight: CGFloat = 18
private static let cursorRequestScrollHeight: CGFloat = 126
```

The implementation can use equivalent names, but the visible-row count must be concrete and testable.

**Step 2: Split range/non-row detail lines**

Add a small helper view for token detail lines that renders:
- structured Cursor range details such as `Range: ...` as normal fixed text
- structured Cursor request rows in a `ScrollView(.vertical, showsIndicators: true)` when there are enough rows to overflow
- existing `detailLines` normally for non-Cursor providers

**Step 3: Apply the fixed height**

Use the named fixed height from Step 1. Keep the rest of the menu card fixed so actions below the card remain reachable.

**Step 4: Use the helper in the required Cursor menu surface**

Replace the `ForEach(tokenUsage.detailLines...)` block in `UsageMenuCardView`, which is the single full-card Cursor `menuCard` path shown in the screenshot.

Only touch `UsageMenuCardCostSectionView` if sharing the helper removes duplication without changing behavior; Cursor does not need that split path for this fix.

Expected behavior:
- Cursor request rows scroll inside the token section.
- non-Cursor token detail lines continue rendering normally.

## Task 5: Add A Testable Menu Card Interaction Policy

**Files:**
- Modify: `Sources/CodexBar/StatusItemController+Menu.swift`
- Inspect: `Sources/CodexBar/StatusItemController+MenuPresentation.swift`
- Modify: `Tests/CodexBarTests/StatusMenuTests.swift`

**Step 1: Add an interaction policy**

Add a small internal policy that can be unit/integration tested, for example:

```swift
struct MenuCardInteractionPolicy: Equatable {
    let allowsHighlight: Bool
    let forwardsScrollToEmbeddedScrollView: Bool
}
```

Resolve it from the menu card model/provider:
- Cursor cards with structured overflow request rows disable full-card highlight and enable scroll forwarding.
- normal menu cards keep existing highlight behavior.
- menu cards with submenus keep existing highlight behavior unless they are the Cursor request overflow card.

**Step 2: Add pure policy coverage**

Add a pure unit test for the policy resolver instead of inspecting an `NSHostingView`.

Build representative `UsageMenuCardView.Model` values and assert:
- a Cursor model with more than the visible structured request-row count resolves to `allowsHighlight == false` and `forwardsScrollToEmbeddedScrollView == true`
- a non-overflow Cursor model resolves to `allowsHighlight == true` and `forwardsScrollToEmbeddedScrollView == false`
- a non-Cursor model resolves to `allowsHighlight == true` and `forwardsScrollToEmbeddedScrollView == false`

If needed after the pure seam is covered, add one narrow rendered smoke test only to confirm the `menuCard` creation path calls the resolver.

Expected: fail until the policy exists and is wired.

## Task 6: Prevent Full-Card Hover Selection For Scrollable Menu Sections

**Files:**
- Modify: `Sources/CodexBar/StatusItemController+Menu.swift`
- Inspect and keep aligned if still compiled/used: `Sources/CodexBar/StatusItemController+MenuPresentation.swift`

**Authoritative seam:** The active runtime path for `makeMenuCardItem(...)` and the screenshot's Cursor `menuCard` lives in the private nested types inside `StatusItemController+Menu.swift`. `StatusItemController+MenuPresentation.swift` also defines similarly named top-level hosting/container types; before editing, confirm whether those top-level types are referenced. If they are compiled but unused, leave a note in the implementation summary. If they are referenced by another menu path, apply the same interaction policy behavior there too so the two implementations do not drift.

**Step 1: Add a highlight policy to menu card items**

Extend `makeMenuCardItem(...)` and `MenuCardItemHostingView`/`MenuCardSectionContainerView` so callers can disable the blue selected background for a view-backed card section.

**Step 2: Wire the policy for the required Cursor menu path**

Apply the policy when adding:
- the single full-card Cursor `menuCard` path in `addMenuCards(...)`
- token-account card variants in `addMenuCards(...)` because they also render full `UsageMenuCardView` cards

Do not change the split `menuCardCost` path unless a shared helper makes it unavoidable; Cursor does not normally route through that path.

Expected behavior:
- hovering over the Cursor request list no longer turns the whole card blue.
- other menu card rows with submenus can still highlight normally.

## Task 7: Forward Wheel Events To The Nested Scroll View

**Files:**
- Modify: `Sources/CodexBar/StatusItemController+Menu.swift`

**Step 1: Add targeted scroll forwarding**

In `MenuCardItemHostingView.scrollWheel(with:)`, find the deepest `NSScrollView` under the event location and forward the event to it.

**Step 2: Fall back to default handling**

If there is no nested scroll view under the pointer, call `super.scrollWheel(with:)`.

Expected behavior:
- trackpad/mouse wheel events over the request list scroll the request rows.
- wheel events over non-scrollable card sections keep existing menu behavior.

## Task 8: Verification

**Files:**
- No production edits unless failures identify a scoped issue.

**Step 1: Run focused tests**

```bash
swift test --filter MenuCardCursorRequestDetailsTests
swift test --filter MenuCardModelTests
swift test --filter StatusMenuTests
```

**Step 2: Run lint**

```bash
pnpm check
```

**Step 3: Rebuild and relaunch the app**

```bash
./Scripts/compile_and_run.sh
```

**Step 4: Manual verification**

Open the CodexBar menu, choose Cursor, and hover over the request rows.

Expected:
- the token section shows `Cycle`, `Requests`, and `Range`.
- request rows are in a fixed-height scroll area.
- scrolling over the rows reveals older request entries.
- the whole Cursor card does not turn blue while hovering over the scrollable rows.
