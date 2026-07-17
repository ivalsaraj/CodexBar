import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct CursorWidgetSnapshotCostSummaryTests {
    private func makeSettings() -> SettingsStore {
        let suite = "CursorWidgetSnapshotCostSummaryTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        settings.refreshFrequency = .manual
        return settings
    }

    @Test
    func `widget snapshot replaces stale two sided cursor cycle summary with gpt lower bound`() async throws {
        let settings = self.makeSettings()
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let staleCycleCostSummary = CursorRequestCostSummary(
            exactUSD: nil,
            lowerBoundUSD: 10,
            upperBoundUSD: 627,
            containsApproximation: true)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(usedPercent: 14, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
                secondary: nil,
                tertiary: nil,
                cursorRequests: CursorRequestUsage(used: 182, limit: 500),
                cursorTokenUsage: CursorTokenUsage(
                    billingCycleTokensUsed: 20_912_049,
                    requestCostSummary: staleCycleCostSummary),
                cursorRecentRequests: [
                    CursorRecentRequest(
                        timestamp: now,
                        model: "gpt-5.5-extra-high",
                        tokens: 20_912_049,
                        requests: 1,
                        requestCost: 2,
                        tokenBreakdown: CursorRecentRequestTokenBreakdown(
                            inputTokens: nil,
                            outputTokens: nil,
                            cacheReadTokens: 20_912_049,
                            cacheWriteTokens: nil,
                            totalTokens: 20_912_049,
                            confidence: .partialBreakdown)),
                ],
                updatedAt: now),
            provider: .cursor)

        var widgetSnapshots: [WidgetSnapshot] = []
        store._test_widgetSnapshotSaveOverride = { widgetSnapshots.append($0) }
        defer { store._test_widgetSnapshotSaveOverride = nil }

        store.persistWidgetSnapshot(reason: "cursor-stale-gpt-cycle-cost-summary")
        await store.widgetSnapshotPersistTask?.value

        let cursorEntry = try #require(widgetSnapshots.last?.entries.first { $0.provider == .cursor })
        let detail = try #require(cursorEntry.cursorRequestDetails?.first)
        #expect(detail.requests == 1)
        #expect(detail.estimateText == "Approx. $10.46+")
        #expect(cursorEntry.tokenUsage?.sessionCostUSD == nil)
        #expect(cursorEntry.tokenUsage?.sessionCostText == "Approx. $10.46+")
    }
}
