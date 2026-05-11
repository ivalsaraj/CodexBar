import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct SettingsStoreCoverageTests {
    @Test
    func `provider ordering and caching`() throws {
        let suite = "SettingsStoreCoverageTests-ordering"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let config = CodexBarConfig(providers: [
            ProviderConfig(id: .zai),
            ProviderConfig(id: .codex),
            ProviderConfig(id: .claude),
        ])
        try configStore.save(config)
        let settings = Self.makeSettingsStore(userDefaults: defaults, configStore: configStore)
        let ordered = settings.orderedProviders()
        let cached = settings.orderedProviders()

        #expect(ordered == cached)
        #expect(ordered.first == .zai)
        #expect(ordered.contains(.minimax))

        settings.moveProvider(fromOffsets: IndexSet(integer: 0), toOffset: 2)
        #expect(settings.orderedProviders() != ordered)

        let metadata = ProviderRegistry.shared.metadata
        try settings.setProviderEnabled(provider: .codex, metadata: #require(metadata[.codex]), enabled: true)
        try settings.setProviderEnabled(provider: .claude, metadata: #require(metadata[.claude]), enabled: false)
        let enabled = settings.enabledProvidersOrdered(metadataByProvider: metadata)
        #expect(enabled.contains(.codex))
    }

    @Test
    func `menu bar metric preferences and display modes`() {
        let settings = Self.makeSettingsStore()

        settings.setMenuBarMetricPreference(.average, for: .codex)
        #expect(settings.menuBarMetricPreference(for: .codex) == .automatic)

        settings.setMenuBarMetricPreference(.average, for: .gemini)
        #expect(settings.menuBarMetricPreference(for: .gemini) == .average)
        #expect(settings.menuBarMetricSupportsAverage(for: .gemini))

        settings.setMenuBarMetricPreference(.secondary, for: .zai)
        #expect(settings.menuBarMetricPreference(for: .zai) == .primary)

        settings.menuBarDisplayMode = .pace
        #expect(settings.menuBarDisplayMode == .pace)
        #expect(settings.historicalTrackingEnabled == false)
        settings.historicalTrackingEnabled = true
        #expect(settings.historicalTrackingEnabled == true)

        settings.resetTimesShowAbsolute = true
        #expect(settings.resetTimeDisplayStyle == .absolute)
    }

    @Test
    func `token account mutations apply side effects`() {
        let settings = Self.makeSettingsStore()

        settings.addTokenAccount(provider: .claude, label: "Primary", token: "token")
        #expect(settings.tokenAccounts(for: .claude).count == 1)
        #expect(settings.claudeCookieSource == .manual)

        let account = settings.selectedTokenAccount(for: .claude)
        #expect(account != nil)

        settings.setActiveTokenAccountIndex(10, for: .claude)
        #expect(settings.selectedTokenAccount(for: .claude)?.id == account?.id)

        if let id = account?.id {
            settings.removeTokenAccount(provider: .claude, accountID: id)
        }
        #expect(settings.tokenAccounts(for: .claude).isEmpty)

        settings.reloadTokenAccounts()
    }

    @Test
    func `opencode go token accounts force manual cookie routing`() {
        let settings = Self.makeSettingsStore()
        settings.addTokenAccount(provider: .opencodego, label: "Go", token: "auth=go-cookie")

        let snapshot = settings.opencodegoSettingsSnapshot(tokenOverride: nil)

        #expect(settings.opencodegoCookieSource == .manual)
        #expect(snapshot.cookieSource == .manual)
        #expect(snapshot.manualCookieHeader == "auth=go-cookie")
    }

    @Test
    func `opencode go snapshot preserves nil workspace id when settings are unset`() {
        let settings = Self.makeSettingsStore()

        let snapshot = settings.opencodegoSettingsSnapshot(tokenOverride: nil)

        #expect(settings.opencodegoWorkspaceID.isEmpty)
        #expect(snapshot.workspaceID == nil)
    }

    @Test
    func `opencode selected workspace account overrides legacy workspace id in snapshot and dashboard routing`()
        throws
    {
        let suite = "SettingsStoreCoverageTests-opencode-workspace-account-\(UUID().uuidString)"
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
                            label: "Team",
                            workspaceID: "wrk_selected",
                            workspaceLabel: "Selected Workspace",
                            discoveredOwnerLabel: nil,
                            addedAt: 200,
                            lastValidatedAt: nil),
                    ])),
        ])
        try configStore.save(config)

        let settings = Self.makeSettingsStore(userDefaults: defaults, configStore: configStore)
        let snapshot = settings.opencodeSettingsSnapshot(tokenOverride: nil)

        #expect(settings.selectedOpenCodeWorkspaceAccount?.id == workspaceAccountID)
        #expect(snapshot.workspaceID == "wrk_selected")
        #expect(
            settings.opencodeDashboardURLOverride?.absoluteString
                == "https://opencode.ai/workspace/wrk_selected/go")
    }

    @Test
    func `removing opencode token account prunes dependent workspace account`() throws {
        let suite = "SettingsStoreCoverageTests-opencode-prune-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)

        let tokenAccountID = UUID()
        let workspaceAccountID = UUID()
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

        let settings = Self.makeSettingsStore(userDefaults: defaults, configStore: configStore)
        settings.removeTokenAccount(provider: .opencode, accountID: tokenAccountID)

        #expect(settings.tokenAccounts(for: .opencode).isEmpty)
        #expect(settings.openCodeWorkspaceAccounts.isEmpty)
        #expect(settings.selectedOpenCodeWorkspaceAccount == nil)
    }

    @Test
    func `opencode snapshot uses linked token account instead of generic active index`() throws {
        let suite = "SettingsStoreCoverageTests-opencode-linked-token-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)

        let firstTokenID = UUID()
        let secondTokenID = UUID()
        let workspaceAccountID = UUID()
        let config = CodexBarConfig(providers: [
            ProviderConfig(
                id: .opencode,
                tokenAccounts: ProviderTokenAccountData(
                    version: 1,
                    accounts: [
                        ProviderTokenAccount(
                            id: firstTokenID,
                            label: "First",
                            token: "auth=first-cookie",
                            addedAt: 100,
                            lastUsed: nil),
                        ProviderTokenAccount(
                            id: secondTokenID,
                            label: "Second",
                            token: "auth=second-cookie",
                            addedAt: 200,
                            lastUsed: nil),
                    ],
                    activeIndex: 0),
                openCodeWorkspaceAccounts: OpenCodeWorkspaceAccountData(
                    version: 1,
                    activeAccountID: workspaceAccountID,
                    accounts: [
                        OpenCodeWorkspaceAccount(
                            id: workspaceAccountID,
                            tokenAccountID: secondTokenID,
                            label: "Workspace",
                            workspaceID: "wrk_selected",
                            workspaceLabel: "Selected Workspace",
                            discoveredOwnerLabel: nil,
                            addedAt: 300,
                            lastValidatedAt: nil),
                    ])),
        ])
        try configStore.save(config)

        let settings = Self.makeSettingsStore(userDefaults: defaults, configStore: configStore)
        let snapshot = settings.opencodeSettingsSnapshot(tokenOverride: nil)

        #expect(snapshot.manualCookieHeader == "auth=second-cookie")
    }

    @Test
    func `opencode snapshot preview override uses preview workspace account instead of active workspace`() throws {
        let suite = "SettingsStoreCoverageTests-opencode-preview-workspace-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)

        let tokenAccountID = UUID()
        let activeWorkspaceAccountID = UUID()
        let previewWorkspaceAccountID = UUID()
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
                    activeAccountID: activeWorkspaceAccountID,
                    accounts: [
                        OpenCodeWorkspaceAccount(
                            id: activeWorkspaceAccountID,
                            tokenAccountID: tokenAccountID,
                            label: "Alpha",
                            workspaceID: "wrk_alpha",
                            workspaceLabel: "Alpha Workspace",
                            discoveredOwnerLabel: nil,
                            addedAt: 200,
                            lastValidatedAt: nil),
                        OpenCodeWorkspaceAccount(
                            id: previewWorkspaceAccountID,
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

        let settings = Self.makeSettingsStore(userDefaults: defaults, configStore: configStore)
        let override = TokenAccountOverride(
            provider: .opencode,
            account: ProviderTokenAccount(
                id: previewWorkspaceAccountID,
                label: "Beta",
                token: "auth=cookie",
                addedAt: 300,
                lastUsed: nil))

        let snapshot = settings.opencodeSettingsSnapshot(tokenOverride: override)

        #expect(snapshot.workspaceID == "wrk_beta")
        #expect(snapshot.manualCookieHeader == "auth=cookie")
    }

    @Test
    func `opencode reports unbound legacy token accounts without inventing workspace bindings`() throws {
        let suite = "SettingsStoreCoverageTests-opencode-unbound-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)

        let firstTokenID = UUID()
        let secondTokenID = UUID()
        let config = CodexBarConfig(providers: [
            ProviderConfig(
                id: .opencode,
                tokenAccounts: ProviderTokenAccountData(
                    version: 1,
                    accounts: [
                        ProviderTokenAccount(
                            id: firstTokenID,
                            label: "First",
                            token: "auth=first-cookie",
                            addedAt: 100,
                            lastUsed: nil),
                        ProviderTokenAccount(
                            id: secondTokenID,
                            label: "Second",
                            token: "auth=second-cookie",
                            addedAt: 200,
                            lastUsed: nil),
                    ],
                    activeIndex: 0)),
        ])
        try configStore.save(config)

        let settings = Self.makeSettingsStore(userDefaults: defaults, configStore: configStore)

        #expect(settings.openCodeWorkspaceAccounts.isEmpty)
        #expect(settings.selectedOpenCodeWorkspaceAccount == nil)
        #expect(settings.unboundOpenCodeTokenAccounts.map(\.id) == [firstTokenID, secondTokenID])
    }

    @Test
    func `opencode migrates one legacy token account plus workspace id into one saved workspace account`() throws {
        let suite = "SettingsStoreCoverageTests-opencode-migrate-single-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)

        let tokenAccountID = UUID()
        let config = CodexBarConfig(providers: [
            ProviderConfig(
                id: .opencode,
                workspaceID: "https://opencode.ai/workspace/wrk_LEGACY123/go",
                tokenAccounts: ProviderTokenAccountData(
                    version: 1,
                    accounts: [
                        ProviderTokenAccount(
                            id: tokenAccountID,
                            label: "Legacy Cookie",
                            token: "auth=legacy-cookie",
                            addedAt: 100,
                            lastUsed: nil),
                    ],
                    activeIndex: 0)),
        ])
        try configStore.save(config)

        let settings = Self.makeSettingsStore(userDefaults: defaults, configStore: configStore)
        settings.ensureOpenCodeWorkspaceAccountMigrationIfNeeded()

        let account = try #require(settings.selectedOpenCodeWorkspaceAccount)
        #expect(settings.openCodeWorkspaceAccounts.count == 1)
        #expect(account.tokenAccountID == tokenAccountID)
        #expect(account.workspaceID == "wrk_LEGACY123")
        #expect(account.label == "Legacy Cookie")
        #expect(account.workspaceLabel == "wrk_LEGACY123")
        #expect(settings.unboundOpenCodeTokenAccounts.isEmpty)
    }

    @Test
    func `opencode migration does not invent bindings for multiple legacy token accounts`() throws {
        let suite = "SettingsStoreCoverageTests-opencode-migrate-multi-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)

        let firstTokenID = UUID()
        let secondTokenID = UUID()
        let config = CodexBarConfig(providers: [
            ProviderConfig(
                id: .opencode,
                workspaceID: "wrk_LEGACY123",
                tokenAccounts: ProviderTokenAccountData(
                    version: 1,
                    accounts: [
                        ProviderTokenAccount(
                            id: firstTokenID,
                            label: "First",
                            token: "auth=first-cookie",
                            addedAt: 100,
                            lastUsed: nil),
                        ProviderTokenAccount(
                            id: secondTokenID,
                            label: "Second",
                            token: "auth=second-cookie",
                            addedAt: 200,
                            lastUsed: nil),
                    ],
                    activeIndex: 0)),
        ])
        try configStore.save(config)

        let settings = Self.makeSettingsStore(userDefaults: defaults, configStore: configStore)
        settings.ensureOpenCodeWorkspaceAccountMigrationIfNeeded()

        #expect(settings.openCodeWorkspaceAccounts.isEmpty)
        #expect(settings.selectedOpenCodeWorkspaceAccount == nil)
        #expect(settings.unboundOpenCodeTokenAccounts.map(\.id) == [firstTokenID, secondTokenID])
    }

    @Test
    func `opencode bulk save imports multiple workspaces for one credential and preserves active selection`() throws {
        let suite = "SettingsStoreCoverageTests-opencode-bulk-import-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)

        let tokenAccountID = UUID()
        let activeWorkspaceAccountID = UUID()
        let config = CodexBarConfig(providers: [
            ProviderConfig(
                id: .opencode,
                tokenAccounts: ProviderTokenAccountData(
                    version: 1,
                    accounts: [
                        ProviderTokenAccount(
                            id: tokenAccountID,
                            label: "Chrome",
                            token: "auth=cookie",
                            addedAt: 100,
                            lastUsed: nil),
                    ],
                    activeIndex: 0),
                openCodeWorkspaceAccounts: OpenCodeWorkspaceAccountData(
                    version: 1,
                    activeAccountID: activeWorkspaceAccountID,
                    accounts: [
                        OpenCodeWorkspaceAccount(
                            id: activeWorkspaceAccountID,
                            tokenAccountID: tokenAccountID,
                            label: "Alpha",
                            workspaceID: "wrk_alpha",
                            workspaceLabel: "Alpha Workspace",
                            discoveredOwnerLabel: nil,
                            addedAt: 200,
                            lastValidatedAt: nil),
                    ])),
        ])
        try configStore.save(config)

        let settings = Self.makeSettingsStore(userDefaults: defaults, configStore: configStore)
        let summary = try #require(settings.bulkSaveOpenCodeWorkspaceAccounts(
            tokenAccountID: tokenAccountID,
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

        #expect(summary.addedCount == 1)
        #expect(summary.updatedCount == 1)
        #expect(summary.accountIDs.count == 2)
        #expect(settings.openCodeWorkspaceAccounts.count == 2)
        #expect(settings.selectedOpenCodeWorkspaceAccount?.id == activeWorkspaceAccountID)
        #expect(
            settings.openCodeWorkspaceAccounts.first(where: { $0.workspaceID == "wrk_alpha" })?
                .discoveredOwnerLabel == "Team One")
        #expect(settings.openCodeWorkspaceAccounts.contains(where: { $0.workspaceID == "wrk_beta" }))
    }

    @Test
    func `opencode bulk save dedupes migration-created workspace accounts`() throws {
        let suite = "SettingsStoreCoverageTests-opencode-bulk-dedupe-migration-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)

        let tokenAccountID = UUID()
        let config = CodexBarConfig(providers: [
            ProviderConfig(
                id: .opencode,
                workspaceID: "wrk_legacy",
                tokenAccounts: ProviderTokenAccountData(
                    version: 1,
                    accounts: [
                        ProviderTokenAccount(
                            id: tokenAccountID,
                            label: "Legacy Cookie",
                            token: "auth=legacy-cookie",
                            addedAt: 100,
                            lastUsed: nil),
                    ],
                    activeIndex: 0)),
        ])
        try configStore.save(config)

        let settings = Self.makeSettingsStore(userDefaults: defaults, configStore: configStore)
        settings.ensureOpenCodeWorkspaceAccountMigrationIfNeeded()

        let summary = try #require(settings.bulkSaveOpenCodeWorkspaceAccounts(
            tokenAccountID: tokenAccountID,
            discoveredWorkspaces: [
                OpenCodeDiscoveredWorkspace(
                    workspaceID: "wrk_legacy",
                    workspaceLabel: "Legacy Workspace",
                    ownerLabel: "Recovered"),
            ]))

        #expect(summary.addedCount == 0)
        #expect(summary.updatedCount == 1)
        #expect(settings.openCodeWorkspaceAccounts.count == 1)
        #expect(settings.openCodeWorkspaceAccounts.first?.workspaceLabel == "Legacy Workspace")
        #expect(settings.openCodeWorkspaceAccounts.first?.discoveredOwnerLabel == "Recovered")
    }

    @Test
    func `opencode reusable credential prefers selected workspace token but falls back to any saved token`() throws {
        let suite = "SettingsStoreCoverageTests-opencode-reusable-credential-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)

        let firstTokenID = UUID()
        let secondTokenID = UUID()
        let secondWorkspaceAccountID = UUID()
        let config = CodexBarConfig(providers: [
            ProviderConfig(
                id: .opencode,
                tokenAccounts: ProviderTokenAccountData(
                    version: 1,
                    accounts: [
                        ProviderTokenAccount(
                            id: firstTokenID,
                            label: "First",
                            token: "auth=first-cookie",
                            addedAt: 100,
                            lastUsed: nil),
                        ProviderTokenAccount(
                            id: secondTokenID,
                            label: "Second",
                            token: "auth=second-cookie",
                            addedAt: 200,
                            lastUsed: nil),
                    ],
                    activeIndex: 0),
                openCodeWorkspaceAccounts: OpenCodeWorkspaceAccountData(
                    version: 1,
                    activeAccountID: secondWorkspaceAccountID,
                    accounts: [
                        OpenCodeWorkspaceAccount(
                            id: secondWorkspaceAccountID,
                            tokenAccountID: secondTokenID,
                            label: "Beta",
                            workspaceID: "wrk_beta",
                            workspaceLabel: "Beta Workspace",
                            discoveredOwnerLabel: nil,
                            addedAt: 300,
                            lastValidatedAt: nil),
                    ])),
        ])
        try configStore.save(config)

        let settings = Self.makeSettingsStore(userDefaults: defaults, configStore: configStore)

        #expect(settings.reusableOpenCodeCredential()?.id == secondTokenID)

        settings.removeOpenCodeWorkspaceAccount(id: secondWorkspaceAccountID)

        #expect(settings.reusableOpenCodeCredential()?.id == firstTokenID)
    }

    @Test
    func `claude snapshot uses OAuth routing for OAuth token accounts`() {
        let settings = Self.makeSettingsStore()
        settings.addTokenAccount(provider: .claude, label: "OAuth", token: "Bearer sk-ant-oat-account-token")

        let snapshot = settings.claudeSettingsSnapshot(tokenOverride: nil)

        #expect(snapshot.usageDataSource == .auto)
        #expect(snapshot.cookieSource == .off)
        #expect(snapshot.manualCookieHeader?.isEmpty == true)
    }

    @Test
    func `claude snapshot uses manual cookie routing for session key accounts`() {
        let settings = Self.makeSettingsStore()
        settings.addTokenAccount(provider: .claude, label: "Cookie", token: "sk-ant-session-token")

        let snapshot = settings.claudeSettingsSnapshot(tokenOverride: nil)

        #expect(snapshot.usageDataSource == .auto)
        #expect(snapshot.cookieSource == .manual)
        #expect(snapshot.manualCookieHeader == "sessionKey=sk-ant-session-token")
    }

    @Test
    func `claude snapshot normalizes config manual cookie input through shared route`() {
        let settings = Self.makeSettingsStore()
        settings.claudeCookieSource = .manual
        settings.claudeCookieHeader = "Cookie: sessionKey=sk-ant-session-token; foo=bar"

        let snapshot = settings.claudeSettingsSnapshot(tokenOverride: nil)

        #expect(snapshot.usageDataSource == .auto)
        #expect(snapshot.cookieSource == .manual)
        #expect(snapshot.manualCookieHeader == "sessionKey=sk-ant-session-token; foo=bar")
    }

    @Test
    func `claude snapshot does not fall back to config cookie for malformed selected token account`() {
        let settings = Self.makeSettingsStore()
        settings.claudeCookieSource = .manual
        settings.claudeCookieHeader = "Cookie: sessionKey=sk-ant-config-cookie"
        settings.addTokenAccount(provider: .claude, label: "Malformed", token: "Cookie:")

        let snapshot = settings.claudeSettingsSnapshot(tokenOverride: nil)

        #expect(snapshot.cookieSource == .manual)
        #expect(snapshot.manualCookieHeader?.isEmpty == true)
    }

    @Test
    func `token cost usage source detection`() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "token-cost-\(UUID().uuidString)",
            isDirectory: true)
        let codexRoot = root.appendingPathComponent("sessions", isDirectory: true)
        try fileManager.createDirectory(at: codexRoot, withIntermediateDirectories: true)
        let codexFile = codexRoot.appendingPathComponent("usage.jsonl")
        fileManager.createFile(atPath: codexFile.path, contents: Data("{}".utf8))

        #expect(SettingsStore.hasAnyTokenCostUsageSources(
            env: ["CODEX_HOME": root.path],
            fileManager: fileManager))

        let claudeRoot = fileManager.temporaryDirectory.appendingPathComponent(
            "claude-\(UUID().uuidString)",
            isDirectory: true)
        let claudeProjects = claudeRoot.appendingPathComponent("projects", isDirectory: true)
        try fileManager.createDirectory(at: claudeProjects, withIntermediateDirectories: true)
        let claudeFile = claudeProjects.appendingPathComponent("usage.jsonl")
        fileManager.createFile(atPath: claudeFile.path, contents: Data("{}".utf8))

        #expect(SettingsStore.hasAnyTokenCostUsageSources(
            env: ["CLAUDE_CONFIG_DIR": claudeRoot.path],
            fileManager: fileManager))
    }

    @Test
    func `ensure token loaders execute`() {
        let settings = Self.makeSettingsStore()

        settings.ensureZaiAPITokenLoaded()
        settings.ensureSyntheticAPITokenLoaded()
        settings.ensureCodexCookieLoaded()
        settings.ensureClaudeCookieLoaded()
        settings.ensureCursorCookieLoaded()
        settings.ensureOpenCodeCookieLoaded()
        settings.ensureFactoryCookieLoaded()
        settings.ensureMiniMaxCookieLoaded()
        settings.ensureMiniMaxAPITokenLoaded()
        settings.ensureKimiAuthTokenLoaded()
        settings.ensureKimiK2APITokenLoaded()
        settings.ensureAugmentCookieLoaded()
        settings.ensureAmpCookieLoaded()
        settings.ensureOllamaCookieLoaded()
        settings.ensureCopilotAPITokenLoaded()
        settings.ensureTokenAccountsLoaded()

        #expect(settings.zaiAPIToken.isEmpty)
        #expect(settings.syntheticAPIToken.isEmpty)
    }

    @Test
    func `keychain disable forces manual cookie sources`() throws {
        let suite = "SettingsStoreCoverageTests-keychain"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let settings = Self.makeSettingsStore(userDefaults: defaults, configStore: configStore)

        settings.codexCookieSource = .auto
        settings.claudeCookieSource = .auto
        settings.kimiCookieSource = .off
        settings.debugDisableKeychainAccess = true

        #expect(settings.codexCookieSource == .manual)
        #expect(settings.claudeCookieSource == .manual)
        #expect(settings.kimiCookieSource == .off)
    }

    @Test
    func `claude keychain prompt mode defaults to only on user action`() {
        let settings = Self.makeSettingsStore()
        #expect(settings.claudeOAuthKeychainPromptMode == .onlyOnUserAction)
    }

    @Test
    func `claude keychain prompt mode persists across store reload`() throws {
        let suite = "SettingsStoreCoverageTests-claude-keychain-prompt-mode"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)

        let first = Self.makeSettingsStore(userDefaults: defaults, configStore: configStore)
        first.claudeOAuthKeychainPromptMode = .never
        #expect(
            defaults.string(forKey: "claudeOAuthKeychainPromptMode")
                == ClaudeOAuthKeychainPromptMode.never.rawValue)

        let second = Self.makeSettingsStore(userDefaults: defaults, configStore: configStore)
        #expect(second.claudeOAuthKeychainPromptMode == .never)
    }

    @Test
    func `claude keychain prompt mode invalid raw falls back to only on user action`() throws {
        let suite = "SettingsStoreCoverageTests-claude-keychain-prompt-mode-invalid"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set("invalid-mode", forKey: "claudeOAuthKeychainPromptMode")
        let configStore = testConfigStore(suiteName: suite)

        let settings = Self.makeSettingsStore(userDefaults: defaults, configStore: configStore)
        #expect(settings.claudeOAuthKeychainPromptMode == .onlyOnUserAction)
    }

    @Test
    func `claude keychain read strategy defaults to security framework`() {
        let settings = Self.makeSettingsStore()
        #expect(settings.claudeOAuthKeychainReadStrategy == .securityFramework)
    }

    @Test
    func `claude keychain read strategy persists across store reload`() throws {
        let suite = "SettingsStoreCoverageTests-claude-keychain-read-strategy"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)

        let first = Self.makeSettingsStore(userDefaults: defaults, configStore: configStore)
        first.claudeOAuthKeychainReadStrategy = .securityCLIExperimental
        #expect(
            defaults.string(forKey: "claudeOAuthKeychainReadStrategy")
                == ClaudeOAuthKeychainReadStrategy.securityCLIExperimental.rawValue)

        let second = Self.makeSettingsStore(userDefaults: defaults, configStore: configStore)
        #expect(second.claudeOAuthKeychainReadStrategy == .securityCLIExperimental)
    }

    @Test
    func `claude keychain read strategy invalid raw falls back to security framework`() throws {
        let suite = "SettingsStoreCoverageTests-claude-keychain-read-strategy-invalid"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set("invalid-strategy", forKey: "claudeOAuthKeychainReadStrategy")
        let configStore = testConfigStore(suiteName: suite)

        let settings = Self.makeSettingsStore(userDefaults: defaults, configStore: configStore)
        #expect(settings.claudeOAuthKeychainReadStrategy == .securityFramework)
    }

    @Test
    func `claude prompt free credentials toggle maps to read strategy`() {
        let settings = Self.makeSettingsStore()
        #expect(settings.claudeOAuthPromptFreeCredentialsEnabled == false)

        settings.claudeOAuthPromptFreeCredentialsEnabled = true
        #expect(settings.claudeOAuthKeychainReadStrategy == .securityCLIExperimental)

        settings.claudeOAuthPromptFreeCredentialsEnabled = false
        #expect(settings.claudeOAuthKeychainReadStrategy == .securityFramework)
    }

    private static func makeSettingsStore(suiteName: String = "SettingsStoreCoverageTests") -> SettingsStore {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(false, forKey: "debugDisableKeychainAccess")
        let configStore = testConfigStore(suiteName: suiteName)
        return Self.makeSettingsStore(userDefaults: defaults, configStore: configStore)
    }

    private static func makeSettingsStore(
        userDefaults: UserDefaults,
        configStore: CodexBarConfigStore) -> SettingsStore
    {
        SettingsStore(
            userDefaults: userDefaults,
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
}
