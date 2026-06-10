import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct CursorProviderImplementationTests {
    private func makeSettings() -> SettingsStore {
        let suite = "CursorProviderImplementationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        return SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
    }

    @Test
    func `cursor usage entries include legacy token quota summary`() {
        let settings = self.makeSettings()
        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        guard let metadata = ProviderRegistry.shared.metadata[.cursor] else {
            Issue.record("Missing Cursor provider metadata")
            return
        }
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 12.3456, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            cursorRequests: CursorRequestUsage(used: 123_456, limit: 1_000_000, metric: .tokens),
            updatedAt: Date())
        let context = ProviderMenuUsageContext(
            provider: .cursor,
            store: store,
            settings: settings,
            metadata: metadata,
            snapshot: snapshot)

        var entries: [ProviderMenuEntry] = []
        CursorProviderImplementation().appendUsageMenuEntries(context: context, entries: &entries)

        let hasTokenSummary = entries.contains { entry in
            guard case let .text(text, _) = entry else { return false }
            return text == "Tokens: 123K / 1M"
        }
        #expect(hasTokenSummary)
    }
}
