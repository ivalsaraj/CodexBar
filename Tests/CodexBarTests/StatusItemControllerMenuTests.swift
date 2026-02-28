import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@Suite
struct StatusItemControllerMenuTests {
    private func makeSnapshot(primary: RateWindow?, secondary: RateWindow?) -> UsageSnapshot {
        UsageSnapshot(primary: primary, secondary: secondary, updatedAt: Date())
    }

    @Test
    func cursorSwitcherFallsBackToSecondaryWhenPlanExhaustedAndShowingRemaining() {
        let primary = RateWindow(usedPercent: 100, windowMinutes: nil, resetsAt: nil, resetDescription: nil)
        let secondary = RateWindow(usedPercent: 36, windowMinutes: nil, resetsAt: nil, resetDescription: nil)
        let snapshot = self.makeSnapshot(primary: primary, secondary: secondary)

        let percent = StatusItemController.switcherWeeklyMetricPercent(
            for: .cursor,
            snapshot: snapshot,
            showUsed: false)

        #expect(percent == 64)
    }

    @Test
    func cursorSwitcherUsesPrimaryWhenShowingUsed() {
        let primary = RateWindow(usedPercent: 100, windowMinutes: nil, resetsAt: nil, resetDescription: nil)
        let secondary = RateWindow(usedPercent: 36, windowMinutes: nil, resetsAt: nil, resetDescription: nil)
        let snapshot = self.makeSnapshot(primary: primary, secondary: secondary)

        let percent = StatusItemController.switcherWeeklyMetricPercent(
            for: .cursor,
            snapshot: snapshot,
            showUsed: true)

        #expect(percent == 100)
    }

    @Test
    func cursorSwitcherKeepsPrimaryWhenRemainingIsPositive() {
        let primary = RateWindow(usedPercent: 20, windowMinutes: nil, resetsAt: nil, resetDescription: nil)
        let secondary = RateWindow(usedPercent: 40, windowMinutes: nil, resetsAt: nil, resetDescription: nil)
        let snapshot = self.makeSnapshot(primary: primary, secondary: secondary)

        let percent = StatusItemController.switcherWeeklyMetricPercent(
            for: .cursor,
            snapshot: snapshot,
            showUsed: false)

        #expect(percent == 80)
    }

    @Test
    func openRouterBrandFallbackEnabledWhenNoKeyLimitConfigured() {
        let snapshot = OpenRouterUsageSnapshot(
            totalCredits: 50,
            totalUsage: 45,
            balance: 5,
            usedPercent: 90,
            keyDataFetched: true,
            keyLimit: nil,
            keyUsage: nil,
            rateLimit: nil,
            updatedAt: Date()).toUsageSnapshot()

        #expect(StatusItemController.shouldUseOpenRouterBrandFallback(
            provider: .openrouter,
            snapshot: snapshot))
        #expect(MenuBarDisplayText.percentText(window: snapshot.primary, showUsed: false) == nil)
    }

    @Test
    func openRouterBrandFallbackDisabledWhenKeyQuotaFetchUnavailable() {
        let snapshot = OpenRouterUsageSnapshot(
            totalCredits: 50,
            totalUsage: 45,
            balance: 5,
            usedPercent: 90,
            keyDataFetched: false,
            keyLimit: nil,
            keyUsage: nil,
            rateLimit: nil,
            updatedAt: Date()).toUsageSnapshot()

        #expect(!StatusItemController.shouldUseOpenRouterBrandFallback(
            provider: .openrouter,
            snapshot: snapshot))
    }

    @Test
    func openRouterBrandFallbackDisabledWhenKeyQuotaAvailable() {
        let snapshot = OpenRouterUsageSnapshot(
            totalCredits: 50,
            totalUsage: 45,
            balance: 5,
            usedPercent: 90,
            keyLimit: 20,
            keyUsage: 2,
            rateLimit: nil,
            updatedAt: Date()).toUsageSnapshot()

        #expect(!StatusItemController.shouldUseOpenRouterBrandFallback(
            provider: .openrouter,
            snapshot: snapshot))
        #expect(snapshot.primary?.usedPercent == 10)
    }

    @Test
    func tokenAccountSelectedIndexPrefersPreviewSelectionWhenPresent() {
        let first = ProviderTokenAccount(
            id: UUID(),
            label: "first",
            token: "a",
            addedAt: 0,
            lastUsed: nil)
        let second = ProviderTokenAccount(
            id: UUID(),
            label: "second",
            token: "b",
            addedAt: 0,
            lastUsed: nil)

        let selected = StatusItemController.resolvedTokenAccountSelectedIndex(
            accounts: [first, second],
            activeIndex: 0,
            previewSelectionID: second.id)

        #expect(selected == 1)
    }

    @Test
    func tokenAccountSelectedIndexFallsBackToActiveWhenPreviewMissing() {
        let first = ProviderTokenAccount(
            id: UUID(),
            label: "first",
            token: "a",
            addedAt: 0,
            lastUsed: nil)
        let second = ProviderTokenAccount(
            id: UUID(),
            label: "second",
            token: "b",
            addedAt: 0,
            lastUsed: nil)

        let selected = StatusItemController.resolvedTokenAccountSelectedIndex(
            accounts: [first, second],
            activeIndex: 1,
            previewSelectionID: UUID())

        #expect(selected == 1)
    }

    @Test
    func tokenAccountSessionBadgeShownWhenWeeklyRemainingIsPositive() {
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 58, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 20, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            tertiary: nil,
            updatedAt: Date())

        let badge = StatusItemController.tokenAccountSessionBadgeText(for: .codex, snapshot: snapshot)
        #expect(badge == "42%")
    }

    @Test
    func tokenAccountSessionBadgeHiddenWhenWeeklyRemainingIsDepleted() {
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 10, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 100, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            tertiary: nil,
            updatedAt: Date())

        let badge = StatusItemController.tokenAccountSessionBadgeText(for: .codex, snapshot: snapshot)
        #expect(badge == "0%")
    }

    @Test
    func tokenAccountSessionBadgeHiddenWhenWeeklyWindowMissing() {
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 10, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            updatedAt: Date())

        let badge = StatusItemController.tokenAccountSessionBadgeText(for: .codex, snapshot: snapshot)
        #expect(badge == nil)
    }
}
