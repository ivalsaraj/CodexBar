import CodexBarCore
import Foundation
import SwiftUI
import Testing
@testable import CodexBar

@MainActor
struct ProvidersPaneCoverageTests {
    @Test
    func `exercises providers pane views`() {
        let settings = Self.makeSettingsStore(suite: "ProvidersPaneCoverageTests")
        let store = Self.makeUsageStore(settings: settings)

        ProvidersPaneTestHarness.exercise(settings: settings, store: store)
    }

    @Test
    func `open router menu bar metric picker shows only automatic and primary`() {
        let settings = Self.makeSettingsStore(suite: "ProvidersPaneCoverageTests-openrouter-picker")
        let store = Self.makeUsageStore(settings: settings)
        let pane = ProvidersPane(settings: settings, store: store)

        let picker = pane._test_menuBarMetricPicker(for: .openrouter)
        #expect(picker?.options.map(\.id) == [
            MenuBarMetricPreference.automatic.rawValue,
            MenuBarMetricPreference.primary.rawValue,
        ])
        #expect(picker?.options.map(\.title) == [
            "Automatic",
            "Primary (API key limit)",
        ])
    }

    @Test
    func `cursor menu bar metric picker omits tertiary api lane when snapshot has no api metric`() {
        let settings = Self.makeSettingsStore(suite: "ProvidersPaneCoverageTests-cursor-no-tertiary-picker")
        let store = Self.makeUsageStore(settings: settings)
        let pane = ProvidersPane(settings: settings, store: store)

        let picker = pane._test_menuBarMetricPicker(for: .cursor)
        let ids = picker?.options.map(\.id) ?? []
        #expect(!ids.contains(MenuBarMetricPreference.tertiary.rawValue))
    }

    @Test
    func `cursor menu bar metric picker includes tertiary api lane when snapshot has api metric`() {
        let settings = Self.makeSettingsStore(suite: "ProvidersPaneCoverageTests-cursor-tertiary-picker")
        let store = Self.makeUsageStore(settings: settings)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(usedPercent: 12, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
                secondary: RateWindow(usedPercent: 34, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
                tertiary: RateWindow(usedPercent: 56, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
                updatedAt: Date()),
            provider: .cursor)
        let pane = ProvidersPane(settings: settings, store: store)

        let picker = pane._test_menuBarMetricPicker(for: .cursor)
        let ids = picker?.options.map(\.id) ?? []
        #expect(ids.contains(MenuBarMetricPreference.tertiary.rawValue))
        let tertiaryOption = picker?.options.first { $0.id == MenuBarMetricPreference.tertiary.rawValue }
        #expect(tertiaryOption?.title == "Tertiary (API)")
    }

    @Test
    func `gemini menu bar metric picker omits tertiary lane`() {
        let settings = Self.makeSettingsStore(suite: "ProvidersPaneCoverageTests-gemini-no-tertiary-picker")
        let store = Self.makeUsageStore(settings: settings)
        let pane = ProvidersPane(settings: settings, store: store)

        let picker = pane._test_menuBarMetricPicker(for: .gemini)
        let ids = picker?.options.map(\.id) ?? []
        #expect(!ids.contains(MenuBarMetricPreference.tertiary.rawValue))
    }

    @Test
    func `provider detail plan row formats open router as balance`() {
        let row = ProviderDetailView<EmptyView>.planRow(provider: .openrouter, planText: "Balance: $4.61")

        #expect(row?.label == "Balance")
        #expect(row?.value == "$4.61")
    }

    @Test
    func `provider detail plan row keeps plan label for non open router`() {
        let row = ProviderDetailView<EmptyView>.planRow(provider: .codex, planText: "Pro")

        #expect(row?.label == "Plan")
        #expect(row?.value == "Pro")
    }

    @Test
    func `opencode manual cookie source hides cached browser trailing text`() {
        let settings = Self.makeSettingsStore(suite: "ProvidersPaneCoverageTests-opencode-manual")
        let store = Self.makeUsageStore(settings: settings)
        settings.opencodeCookieSource = .manual
        CookieHeaderCache.store(provider: .opencode, cookieHeader: "auth=cache", sourceLabel: "Chrome")
        defer { CookieHeaderCache.clear(provider: .opencode) }

        let pane = ProvidersPane(settings: settings, store: store)
        let picker = pane._test_settingsPickers(for: .opencode).first { $0.id == "opencode-cookie-source" }

        #expect(picker?.dynamicSubtitle?() == "Paste a Cookie header captured from the billing page.")
        #expect(picker?.trailingText?() == nil)
    }

    @Test
    func `opencode go manual cookie source hides cached browser trailing text`() {
        let settings = Self.makeSettingsStore(suite: "ProvidersPaneCoverageTests-opencodego-manual")
        let store = Self.makeUsageStore(settings: settings)
        settings.opencodegoCookieSource = .manual
        CookieHeaderCache.store(provider: .opencodego, cookieHeader: "auth=cache", sourceLabel: "Chrome")
        defer { CookieHeaderCache.clear(provider: .opencodego) }

        let pane = ProvidersPane(settings: settings, store: store)
        let picker = pane._test_settingsPickers(for: .opencodego).first { $0.id == "opencodego-cookie-source" }

        #expect(picker?.dynamicSubtitle?() == "Paste a Cookie header captured from the billing page.")
        #expect(picker?.trailingText?() == nil)
    }

    @Test
    func `opencode providers pane exposes workspace accounts section and hides generic token row`() {
        let settings = Self.makeSettingsStore(suite: "ProvidersPaneCoverageTests-opencode-accounts-section")
        let store = Self.makeUsageStore(settings: settings)
        settings.addTokenAccount(provider: .opencode, label: "Legacy Cookie", token: "auth=legacy-cookie")

        let pane = ProvidersPane(settings: settings, store: store)
        let tokenAccounts = pane._test_tokenAccountDescriptor(for: .opencode)
        let accountsState = pane._test_openCodeAccountsSectionState()

        #expect(tokenAccounts?.isVisible?() == false)
        #expect(accountsState?.hasReusableCredential == true)
        #expect(accountsState?.accounts.isEmpty == true)
    }

    @Test
    func `opencode import current login saves every discovered workspace`() async throws {
        let settings = Self.makeSettingsStore(suite: "ProvidersPaneCoverageTests-opencode-import-login")
        let store = Self.makeUsageStore(settings: settings)
        let cookie = try #require(Self.makeCookie(name: "auth", value: "import-cookie"))
        let pane = ProvidersPane(
            settings: settings,
            store: store,
            openCodeWorkspaceFlow: FakeOpenCodeWorkspaceFlow(
                sessionInfo: OpenCodeCookieImporter.SessionInfo(
                    cookies: [cookie],
                    sourceLabel: "Chrome"),
                discoveredWorkspaces: [
                    OpenCodeDiscoveredWorkspace(
                        workspaceID: "wrk_alpha",
                        workspaceLabel: "Alpha Workspace",
                        ownerLabel: "Team One"),
                    OpenCodeDiscoveredWorkspace(
                        workspaceID: "wrk_beta",
                        workspaceLabel: "Beta Workspace",
                        ownerLabel: "Team Two"),
                ]))

        let result = await pane._test_importOpenCodeCurrentLogin()

        #expect(result == .success("2 workspaces imported."))
        #expect(settings.openCodeWorkspaceAccounts.map(\.workspaceID) == ["wrk_alpha", "wrk_beta"])
        #expect(settings.selectedOpenCodeWorkspaceAccount?.workspaceID == "wrk_alpha")
        #expect(pane._test_openCodeAccountsSectionState()?.notice == "2 workspaces imported.")
    }

    @Test
    func `opencode import current login switches active workspace to imported login`() async throws {
        let settings = Self.makeSettingsStore(suite: "ProvidersPaneCoverageTests-opencode-import-switches-login")
        let store = Self.makeUsageStore(settings: settings)
        let oldToken = try #require(settings.saveOrReuseOpenCodeCredential(
            label: "OpenCode (Old)",
            token: "auth=old-cookie"))
        let oldAccountID = try #require(settings.saveOpenCodeWorkspaceAccount(
            tokenAccountID: oldToken.id,
            label: "Old Workspace",
            workspaceID: "wrk_old",
            workspaceLabel: "Old Workspace",
            discoveredOwnerLabel: nil))
        _ = settings.setActiveOpenCodeWorkspaceAccount(id: oldAccountID)

        let cookie = try #require(Self.makeCookie(name: "auth", value: "new-cookie"))
        let pane = ProvidersPane(
            settings: settings,
            store: store,
            openCodeWorkspaceFlow: FakeOpenCodeWorkspaceFlow(
                sessionInfo: OpenCodeCookieImporter.SessionInfo(
                    cookies: [cookie],
                    sourceLabel: "Chrome"),
                discoveredWorkspaces: [
                    OpenCodeDiscoveredWorkspace(
                        workspaceID: "wrk_new",
                        workspaceLabel: "New Workspace",
                        ownerLabel: nil),
                ]))

        let result = await pane._test_importOpenCodeCurrentLogin()

        #expect(result == .success("1 workspace imported."))
        #expect(settings.selectedOpenCodeWorkspaceAccount?.workspaceID == "wrk_new")
        #expect(settings.reusableOpenCodeCredential()?.token == "auth=new-cookie")
    }

    @Test
    func `opencode manual add reuses saved credential and only needs workspace id`() async {
        let settings = Self.makeSettingsStore(suite: "ProvidersPaneCoverageTests-opencode-manual-add")
        let store = Self.makeUsageStore(settings: settings)
        _ = settings.saveOrReuseOpenCodeCredential(label: "OpenCode (Chrome)", token: "auth=saved-cookie")
        let pane = ProvidersPane(settings: settings, store: store)

        let result = await pane._test_saveOpenCodeAccount(OpenCodeAccountDraft(
            workspaceID: "https://opencode.ai/workspace/wrk_manual/go",
            workspaceLabel: "Manual Workspace"))

        #expect(result == .success("Manual Workspace added."))
        #expect(settings.openCodeWorkspaceAccounts.count == 1)
        #expect(settings.openCodeWorkspaceAccounts.first?.workspaceID == "wrk_manual")
        #expect(settings.openCodeWorkspaceAccounts.first?.workspaceLabel == "Manual Workspace")
    }

    @Test
    func `opencode manual add without reusable credential returns visible failure`() async {
        let settings = Self.makeSettingsStore(suite: "ProvidersPaneCoverageTests-opencode-no-credential")
        let store = Self.makeUsageStore(settings: settings)
        let pane = ProvidersPane(settings: settings, store: store)

        let result = await pane._test_saveOpenCodeAccount(OpenCodeAccountDraft(
            workspaceID: "wrk_manual",
            workspaceLabel: "Manual Workspace"))

        #expect(result == .failure("Import your current OpenCode login first."))
        #expect(result.shouldResetForm == false)
        #expect(settings.openCodeWorkspaceAccounts.isEmpty)
        #expect(pane._test_openCodeAccountsSectionState()?.notice == "Import your current OpenCode login first.")
    }

    @Test
    func `codex providers pane uses managed account fallback instead of ambient account`() throws {
        let settings = Self.makeSettingsStore(suite: "ProvidersPaneCoverageTests-codex-managed-fallback")
        let ambientHome = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true)
        let managedHome = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: ambientHome)
            try? FileManager.default.removeItem(at: managedHome)
        }

        try Self.writeCodexAuthFile(homeURL: ambientHome, email: "ambient@example.com", plan: "plus")
        try Self.writeCodexAuthFile(homeURL: managedHome, email: "managed@example.com", plan: "enterprise")
        let managedAccountID = UUID()
        settings.codexActiveSource = .managedAccount(id: managedAccountID)
        settings._test_activeManagedCodexAccount = ManagedCodexAccount(
            id: managedAccountID,
            email: "managed@example.com",
            managedHomePath: managedHome.path,
            createdAt: 1,
            updatedAt: 2,
            lastAuthenticatedAt: 2)

        let store = UsageStore(
            fetcher: UsageFetcher(environment: ["CODEX_HOME": ambientHome.path]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(usedPercent: 12, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
                secondary: RateWindow(usedPercent: 34, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
                updatedAt: Date(),
                identity: nil),
            provider: .codex)

        let pane = ProvidersPane(settings: settings, store: store)
        let model = pane._test_menuCardModel(for: .codex)

        #expect(model.email == "managed@example.com")
        #expect(model.planText == "Enterprise")
    }

    private static func makeSettingsStore(suite: String) -> SettingsStore {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)

        return SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore(),
            codexCookieStore: InMemoryCookieHeaderStore(),
            claudeCookieStore: InMemoryCookieHeaderStore(),
            cursorCookieStore: InMemoryCookieHeaderStore(),
            opencodeCookieStore: InMemoryCookieHeaderStore(),
            factoryCookieStore: InMemoryCookieHeaderStore(),
            minimaxCookieStore: InMemoryMiniMaxCookieStore(),
            minimaxAPITokenStore: InMemoryMiniMaxAPITokenStore(),
            kimiTokenStore: InMemoryKimiTokenStore(),
            kimiK2TokenStore: InMemoryKimiK2TokenStore(),
            augmentCookieStore: InMemoryCookieHeaderStore(),
            ampCookieStore: InMemoryCookieHeaderStore(),
            copilotTokenStore: InMemoryCopilotTokenStore(),
            tokenAccountStore: InMemoryTokenAccountStore())
    }

    private static func makeUsageStore(settings: SettingsStore) -> UsageStore {
        UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
    }

    private static func writeCodexAuthFile(homeURL: URL, email: String, plan: String) throws {
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
        let auth = [
            "tokens": [
                "accessToken": "access-token",
                "refreshToken": "refresh-token",
                "idToken": Self.fakeJWT(email: email, plan: plan),
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: auth)
        try data.write(to: homeURL.appendingPathComponent("auth.json"))
    }

    private static func fakeJWT(email: String, plan: String) -> String {
        let header = (try? JSONSerialization.data(withJSONObject: ["alg": "none"])) ?? Data()
        let payload = (try? JSONSerialization.data(withJSONObject: [
            "email": email,
            "chatgpt_plan_type": plan,
        ])) ?? Data()

        func base64URL(_ data: Data) -> String {
            data.base64EncodedString()
                .replacingOccurrences(of: "=", with: "")
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
        }

        return "\(base64URL(header)).\(base64URL(payload))."
    }

    private static func makeCookie(name: String, value: String) -> HTTPCookie? {
        HTTPCookie(properties: [
            .domain: "opencode.ai",
            .path: "/",
            .name: name,
            .value: value,
            .secure: "TRUE",
        ])
    }
}

private struct FakeOpenCodeWorkspaceFlow: OpenCodeWorkspaceFlowing {
    let sessionInfo: OpenCodeCookieImporter.SessionInfo
    let discoveredWorkspaces: [OpenCodeDiscoveredWorkspace]

    func importSession(browserDetection _: BrowserDetection) async throws -> OpenCodeCookieImporter.SessionInfo {
        self.sessionInfo
    }

    func discoverWorkspaces(cookieHeader _: String) async throws -> [OpenCodeDiscoveredWorkspace] {
        self.discoveredWorkspaces
    }
}
