import AppKit
import CodexBarCore
import Testing
@testable import CodexBar

@MainActor
struct OpenCodeStatusMenuTests {
    @Test
    func `dashboard action follows configured workspace go page`() throws {
        StatusItemController.menuCardRenderingEnabled = false
        StatusItemController.menuRefreshEnabled = false

        let suite = "OpenCodeStatusMenuTests-\(UUID().uuidString)"
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
        settings.opencodeWorkspaceID = "https://opencode.ai/workspace/wrk_abc123/go"

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
            controller.dashboardURL(for: .opencode)?.absoluteString
                == "https://opencode.ai/workspace/wrk_abc123/go")
    }

    @Test
    func `dashboard action uses provider dashboard when no workspace override exists`() throws {
        StatusItemController.menuCardRenderingEnabled = false
        StatusItemController.menuRefreshEnabled = false

        let suite = "OpenCodeStatusMenuTests-no-override-\(UUID().uuidString)"
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

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: Self.makeStatusBarForTesting())

        #expect(controller.dashboardURL(for: .opencode)?.absoluteString == "https://opencode.ai")
    }

    @Test
    func `dashboard action prefers selected workspace account over legacy workspace id`() throws {
        StatusItemController.menuCardRenderingEnabled = false
        StatusItemController.menuRefreshEnabled = false

        let suite = "OpenCodeStatusMenuTests-selected-account-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)

        let tokenAccountID = UUID()
        let workspaceAccountID = UUID()
        let config = CodexBarConfig(providers: [
            ProviderConfig(
                id: .opencode,
                workspaceID: "wrk_legacy",
                tokenAccounts: ProviderTokenAccountData(
                    version: 1,
                    accounts: [
                        ProviderTokenAccount(
                            id: tokenAccountID,
                            label: "Cookie",
                            token: "auth=cookie",
                            addedAt: 100,
                            lastUsed: nil),
                    ],
                    activeIndex: 0),
                openCodeWorkspaceAccounts: OpenCodeWorkspaceAccountData(
                    version: 1,
                    activeAccountID: workspaceAccountID,
                    accounts: [
                        OpenCodeWorkspaceAccount(
                            id: workspaceAccountID,
                            tokenAccountID: tokenAccountID,
                            label: "Workspace",
                            workspaceID: "wrk_selected",
                            workspaceLabel: "Selected Workspace",
                            discoveredOwnerLabel: nil,
                            addedAt: 200,
                            lastValidatedAt: nil),
                    ])),
        ])
        try configStore.save(config)

        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual

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
            controller.dashboardURL(for: .opencode)?.absoluteString
                == "https://opencode.ai/workspace/wrk_selected/go")
    }

    @Test
    func `status menu display uses saved workspace accounts instead of raw token accounts`() throws {
        StatusItemController.menuCardRenderingEnabled = false
        StatusItemController.menuRefreshEnabled = false

        let suite = "OpenCodeStatusMenuTests-workspace-display-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)

        let tokenAccountID = UUID()
        let firstWorkspaceAccountID = UUID()
        let secondWorkspaceAccountID = UUID()
        let config = CodexBarConfig(providers: [
            ProviderConfig(
                id: .opencode,
                tokenAccounts: ProviderTokenAccountData(
                    version: 1,
                    accounts: [
                        ProviderTokenAccount(
                            id: tokenAccountID,
                            label: "Cookie",
                            token: "auth=cookie",
                            addedAt: 100,
                            lastUsed: nil),
                    ],
                    activeIndex: 0),
                openCodeWorkspaceAccounts: OpenCodeWorkspaceAccountData(
                    version: 1,
                    activeAccountID: secondWorkspaceAccountID,
                    accounts: [
                        OpenCodeWorkspaceAccount(
                            id: firstWorkspaceAccountID,
                            tokenAccountID: tokenAccountID,
                            label: "Alpha",
                            workspaceID: "wrk_alpha",
                            workspaceLabel: "Alpha Workspace",
                            discoveredOwnerLabel: nil,
                            addedAt: 200,
                            lastValidatedAt: nil),
                        OpenCodeWorkspaceAccount(
                            id: secondWorkspaceAccountID,
                            tokenAccountID: tokenAccountID,
                            label: "Beta",
                            workspaceID: "wrk_beta",
                            workspaceLabel: "Beta Workspace",
                            discoveredOwnerLabel: nil,
                            addedAt: 300,
                            lastValidatedAt: nil),
                    ])),
        ])
        try configStore.save(config)

        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: Self.makeStatusBarForTesting())

        let display = try #require(controller.tokenAccountMenuDisplay(for: .opencode))

        #expect(display.accounts.map(\.id) == [firstWorkspaceAccountID, secondWorkspaceAccountID])
        #expect(display.activeIndex == 1)
        #expect(display.selectedIndex == 1)
        #expect(display.showSwitcher)
    }

    private static func makeStatusBarForTesting() -> NSStatusBar {
        let env = ProcessInfo.processInfo.environment
        if env["GITHUB_ACTIONS"] == "true" || env["CI"] == "true" {
            return .system
        }
        return NSStatusBar()
    }
}
