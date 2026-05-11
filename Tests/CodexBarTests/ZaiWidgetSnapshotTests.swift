import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct ZaiWidgetSnapshotTests {
    @Test
    func `widget snapshot includes zai token window detail`() async throws {
        let suite = "ZaiWidgetSnapshotTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        settings.refreshFrequency = .manual

        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        let now = Date()
        store._setSnapshotForTesting(
            ZaiUsageSnapshot(
                tokenLimit: ZaiLimitEntry(
                    type: .tokensLimit,
                    unit: .hours,
                    number: 5,
                    usage: nil,
                    currentValue: nil,
                    remaining: nil,
                    percentage: 1,
                    usageDetails: [],
                    nextResetTime: now.addingTimeInterval(3600)),
                timeLimit: nil,
                planName: nil,
                updatedAt: now).toUsageSnapshot(),
            provider: .zai)

        var widgetSnapshots: [WidgetSnapshot] = []
        store._test_widgetSnapshotSaveOverride = { widgetSnapshots.append($0) }
        defer { store._test_widgetSnapshotSaveOverride = nil }

        store.persistWidgetSnapshot(reason: "zai-token-window")
        await store.widgetSnapshotPersistTask?.value

        let zaiEntry = try #require(widgetSnapshots.last?.entries.first { $0.provider == .zai })
        #expect(zaiEntry.usageRows?.first?.title == "Tokens")
        #expect(zaiEntry.usageRows?.first?.detailText == "5 hours window")
    }

    @Test
    func `widget snapshot includes separate zai weekly and MCP rows`() async throws {
        let suite = "ZaiWidgetSnapshotTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        settings.refreshFrequency = .manual

        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        let now = Date()
        store._setSnapshotForTesting(
            ZaiUsageSnapshot(
                tokenLimit: ZaiLimitEntry(
                    type: .tokensLimit,
                    unit: .hours,
                    number: 5,
                    usage: nil,
                    currentValue: nil,
                    remaining: nil,
                    percentage: 21,
                    usageDetails: [],
                    nextResetTime: now.addingTimeInterval(5 * 3600)),
                secondaryTokenLimit: ZaiLimitEntry(
                    type: .tokensLimit,
                    unit: .weeks,
                    number: 1,
                    usage: nil,
                    currentValue: nil,
                    remaining: nil,
                    percentage: 30,
                    usageDetails: [],
                    nextResetTime: now.addingTimeInterval(7 * 24 * 3600)),
                timeLimit: ZaiLimitEntry(
                    type: .timeLimit,
                    unit: .minutes,
                    number: 1,
                    usage: 1000,
                    currentValue: 0,
                    remaining: 1000,
                    percentage: 0,
                    usageDetails: [ZaiUsageDetail(modelCode: "search-prime", usage: 0)],
                    nextResetTime: now.addingTimeInterval(9 * 24 * 3600)),
                planName: nil,
                updatedAt: now).toUsageSnapshot(),
            provider: .zai)

        var widgetSnapshots: [WidgetSnapshot] = []
        store._test_widgetSnapshotSaveOverride = { widgetSnapshots.append($0) }
        defer { store._test_widgetSnapshotSaveOverride = nil }

        store.persistWidgetSnapshot(reason: "zai-three-lanes")
        await store.widgetSnapshotPersistTask?.value

        let zaiEntry = try #require(widgetSnapshots.last?.entries.first { $0.provider == .zai })
        let rowTitles: [String]? = zaiEntry.usageRows?.map(\.title)
        #expect(rowTitles == ["Tokens", "Weekly", "MCP"])
        #expect(zaiEntry.usageRows?.first?.detailText == "5 hours window")
        #expect(zaiEntry.usageRows?.dropFirst().first?.detailText == "1 week window")
        #expect(zaiEntry.usageRows?.last?.detailText == "1 minute window")
    }
}
