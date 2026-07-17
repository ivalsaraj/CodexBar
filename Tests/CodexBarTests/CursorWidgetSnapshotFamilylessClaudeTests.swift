import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct CursorWidgetSnapshotFamilylessClaudeTests {
    private func makeSettings() -> SettingsStore {
        let suite = "CursorWidgetSnapshotFamilylessClaudeTests-\(UUID().uuidString)"
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
    func `widget snapshot populates version first anthropic opus estimate`() async throws {
        let settings = self.makeSettings()
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)

        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let recent = [
            CursorRecentRequest(
                timestamp: baseDate,
                model: "claude-4.6-opus-max-thinking",
                tokens: 252_000,
                requests: 1,
                tokenBreakdown: CursorRecentRequestTokenBreakdown(
                    inputTokens: nil,
                    outputTokens: nil,
                    cacheReadTokens: nil,
                    cacheWriteTokens: nil,
                    totalTokens: 252_000,
                    confidence: .totalOnly)),
        ]

        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(usedPercent: 14, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
                secondary: nil,
                tertiary: nil,
                cursorRequests: CursorRequestUsage(used: 70, limit: 500),
                cursorTokenUsage: CursorTokenUsage(billingCycleTokensUsed: 252_000),
                cursorRecentRequests: recent,
                updatedAt: Date()),
            provider: .cursor)

        var widgetSnapshots: [WidgetSnapshot] = []
        store._test_widgetSnapshotSaveOverride = { widgetSnapshots.append($0) }
        defer { store._test_widgetSnapshotSaveOverride = nil }

        store.persistWidgetSnapshot(reason: "cursor-familyless-opus-approx")
        await store.widgetSnapshotPersistTask?.value

        let entry = try #require(widgetSnapshots.last?.entries.first { $0.provider == .cursor })
        let detail = try #require(entry.cursorRequestDetails?.first)
        #expect(detail.compactModel == "Opus 4.6 · max")
        #expect(detail.estimateText?.hasPrefix("Approx.") == true)
        #expect(entry.tokenUsage?.sessionCostUSD == nil)
        #expect(entry.tokenUsage?.sessionCostText == "Approx. $0.13-$6.30")
    }
}
