import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct CursorWidgetSnapshotTests {
    private func makeSettings() -> SettingsStore {
        let suite = "CursorWidgetSnapshotTests-\(UUID().uuidString)"
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
    func `widget snapshot includes cursor billing cycle token usage`() async throws {
        let settings = self.makeSettings()
        let fetcher = UsageFetcher()
        let browserDetection = BrowserDetection(cacheTTL: 0)
        let store = UsageStore(
            fetcher: fetcher,
            browserDetection: browserDetection,
            settings: settings)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(usedPercent: 14, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
                secondary: RateWindow(usedPercent: 100, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
                tertiary: RateWindow(
                    usedPercent: 93.77777777777777,
                    windowMinutes: nil,
                    resetsAt: nil,
                    resetDescription: nil),
                cursorRequests: CursorRequestUsage(used: 70, limit: 500),
                cursorTokenUsage: CursorTokenUsage(billingCycleTokensUsed: 86_684_822),
                updatedAt: Date()),
            provider: .cursor)

        var widgetSnapshots: [WidgetSnapshot] = []
        store._test_widgetSnapshotSaveOverride = { widgetSnapshots.append($0) }
        defer { store._test_widgetSnapshotSaveOverride = nil }

        store.persistWidgetSnapshot(reason: "cursor-token-usage")
        await store.widgetSnapshotPersistTask?.value

        let cursorEntry = try #require(widgetSnapshots.last?.entries.first { $0.provider == .cursor })
        #expect(cursorEntry.tokenUsage?.sessionTokens == 86_684_822)
        #expect(cursorEntry.tokenUsage?.sessionLabel == "Cycle")
        #expect(cursorEntry.tokenUsage?.last30DaysLabel == nil)
    }

    @Test
    func `widget snapshot caps cursor recent request details at thirty newest rows`() async throws {
        let settings = self.makeSettings()
        let fetcher = UsageFetcher()
        let browserDetection = BrowserDetection(cacheTTL: 0)
        let store = UsageStore(
            fetcher: fetcher,
            browserDetection: browserDetection,
            settings: settings)

        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        var recent: [CursorRecentRequest] = []
        for index in 0..<35 {
            let offset = Double(35 - index) * 60
            recent.append(CursorRecentRequest(
                timestamp: baseDate.addingTimeInterval(offset),
                model: "model-\(index)",
                tokens: 100 + index,
                requests: 1))
        }
        recent.append(CursorRecentRequest(
            timestamp: baseDate.addingTimeInterval(-120),
            model: "",
            tokens: 10,
            requests: 1))
        recent.append(CursorRecentRequest(
            timestamp: baseDate.addingTimeInterval(-180),
            model: "missing-tokens",
            tokens: 0,
            requests: 1))

        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(usedPercent: 14, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
                secondary: nil,
                tertiary: nil,
                cursorRequests: CursorRequestUsage(used: 70, limit: 500),
                cursorTokenUsage: CursorTokenUsage(billingCycleTokensUsed: 86_684_822),
                cursorRecentRequests: recent,
                cursorRecentRequestRange: CursorRecentRequestRange(
                    start: baseDate,
                    end: baseDate.addingTimeInterval(35 * 60)),
                updatedAt: Date()),
            provider: .cursor)

        var widgetSnapshots: [WidgetSnapshot] = []
        store._test_widgetSnapshotSaveOverride = { widgetSnapshots.append($0) }
        defer { store._test_widgetSnapshotSaveOverride = nil }

        store.persistWidgetSnapshot(reason: "cursor-request-details")
        await store.widgetSnapshotPersistTask?.value

        let details = try #require(widgetSnapshots.last?.entries.first { $0.provider == .cursor }?
            .cursorRequestDetails)
        #expect(details.count == 30)
        #expect(details.first?.model == "model-0")
        #expect(details.last?.model == "model-29")
        #expect(!details.contains { $0.model.isEmpty })
        #expect(!details.contains { $0.model == "missing-tokens" })
        let range = try #require(widgetSnapshots.last?.entries.first { $0.provider == .cursor }?
            .cursorRequestRange)
        #expect(range.start == baseDate)
        #expect(range.end == baseDate.addingTimeInterval(35 * 60))
    }

    @Test
    func `widget snapshot keeps zero token request rows and drops empty request rows`() async throws {
        let settings = self.makeSettings()
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)

        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let recent: [CursorRecentRequest] = [
            CursorRecentRequest(
                timestamp: baseDate.addingTimeInterval(300),
                model: "claude-opus-4-8-thinking-xhigh",
                tokens: 0,
                requests: 1),
            CursorRecentRequest(
                timestamp: baseDate.addingTimeInterval(200),
                model: "composer-2.5",
                tokens: 2_500_000,
                requests: 1),
            CursorRecentRequest(
                timestamp: baseDate.addingTimeInterval(100),
                model: "ghost",
                tokens: 0,
                requests: 0),
        ]

        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(usedPercent: 14, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
                secondary: nil,
                tertiary: nil,
                cursorRequests: CursorRequestUsage(used: 70, limit: 500),
                cursorRecentRequests: recent,
                updatedAt: Date()),
            provider: .cursor)

        var widgetSnapshots: [WidgetSnapshot] = []
        store._test_widgetSnapshotSaveOverride = { widgetSnapshots.append($0) }
        defer { store._test_widgetSnapshotSaveOverride = nil }

        store.persistWidgetSnapshot(reason: "cursor-zero-token-rows")
        await store.widgetSnapshotPersistTask?.value

        let details = try #require(widgetSnapshots.last?.entries.first { $0.provider == .cursor }?
            .cursorRequestDetails)
        #expect(details.count == 2)
        #expect(!details.contains { $0.model == "ghost" })
        let zeroTokenRow = try #require(details.first { $0.model == "claude-opus-4-8-thinking-xhigh" })
        #expect(zeroTokenRow.tokens == 0)
        #expect(zeroTokenRow.requests == 1)
        #expect(zeroTokenRow.compactModel == "Opus 4.8 · xhigh")
    }

    @Test
    func `widget snapshot populates compact model and estimate for priced cursor row`() async throws {
        let settings = self.makeSettings()
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)

        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let recent = [
            CursorRecentRequest(
                timestamp: baseDate,
                model: "claude-opus-4-8-thinking-xhigh",
                tokens: 2_000_000,
                requests: 1,
                tokenBreakdown: CursorRecentRequestTokenBreakdown(
                    inputTokens: 1_000_000,
                    outputTokens: 1_000_000,
                    cacheReadTokens: 0,
                    cacheWriteTokens: 0,
                    totalTokens: 2_000_000,
                    confidence: .exactBreakdown)),
        ]

        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(usedPercent: 14, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
                secondary: nil,
                tertiary: nil,
                cursorRequests: CursorRequestUsage(used: 70, limit: 500),
                cursorRecentRequests: recent,
                updatedAt: Date()),
            provider: .cursor)

        var widgetSnapshots: [WidgetSnapshot] = []
        store._test_widgetSnapshotSaveOverride = { widgetSnapshots.append($0) }
        defer { store._test_widgetSnapshotSaveOverride = nil }

        store.persistWidgetSnapshot(reason: "cursor-priced-row")
        await store.widgetSnapshotPersistTask?.value

        let detail = try #require(widgetSnapshots.last?.entries.first { $0.provider == .cursor }?
            .cursorRequestDetails?.first)
        #expect(detail.compactModel == "Opus 4.8 · xhigh")
        #expect(detail.estimateText?.hasPrefix("Est. ") == true)
    }
}
