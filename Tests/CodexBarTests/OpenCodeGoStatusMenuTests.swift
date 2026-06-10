import AppKit
import CodexBarCore
import Testing
@testable import CodexBar

@MainActor
struct OpenCodeGoStatusMenuTests {
    @Test
    func `dashboard action follows configured workspace`() throws {
        StatusItemController.menuCardRenderingEnabled = false
        StatusItemController.menuRefreshEnabled = false

        let suite = "OpenCodeGoStatusMenuTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.opencodegoWorkspaceID = "https://opencode.ai/workspace/wrk_abc123/go"

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: Self.makeStatusBarForTesting())

        #expect(
            controller.dashboardURL(for: .opencodego)?.absoluteString
                == "https://opencode.ai/workspace/wrk_abc123/go")
    }

    private static func makeStatusBarForTesting() -> NSStatusBar {
        let env = ProcessInfo.processInfo.environment
        if env["GITHUB_ACTIONS"] == "true" || env["CI"] == "true" {
            return .system
        }
        return NSStatusBar()
    }
}
