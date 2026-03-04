import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
@Suite("Codex active account token sync", .serialized)
struct CodexActiveAccountTokenSyncTests {
    @Test("sync updates only active codex account token when changed")
    func syncUpdatesOnlyActiveCodexAccountTokenWhenChanged() async throws {
        let settings = Self.makeSettingsStore(suite: "CodexActiveAccountTokenSyncTests-changed")
        let activeID = UUID()
        let otherCodexID = UUID()
        let claudeID = UUID()
        let oldActiveToken = #"{"tokens":{"access_token":"old-active","refresh_token":"old-active-ref"}}"#
        let otherCodexToken = #"{"tokens":{"access_token":"other","refresh_token":"other-ref"}}"#
        let claudeToken = "claude-token"
        let updatedDiskToken = #"{"tokens":{"access_token":"new-active","refresh_token":"new-active-ref"}}"#

        settings.tokenAccountsByProvider = [
            .codex: ProviderTokenAccountData(
                version: 1,
                accounts: [
                    ProviderTokenAccount(
                        id: activeID,
                        label: "Active",
                        token: oldActiveToken,
                        addedAt: 0,
                        lastUsed: nil),
                    ProviderTokenAccount(
                        id: otherCodexID,
                        label: "Other",
                        token: otherCodexToken,
                        addedAt: 0,
                        lastUsed: nil),
                ],
                activeIndex: 0),
            .claude: ProviderTokenAccountData(
                version: 1,
                accounts: [
                    ProviderTokenAccount(
                        id: claudeID,
                        label: "Claude",
                        token: claudeToken,
                        addedAt: 0,
                        lastUsed: nil),
                ],
                activeIndex: 0),
        ]

        let codexHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-active-sync-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: codexHome) }
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try Data(updatedDiskToken.utf8).write(to: codexHome.appendingPathComponent("auth.json"), options: .atomic)

        let store = Self.makeUsageStore(settings: settings)
        await store.syncActiveCodexAccountTokenFromDiskIfNeeded(env: ["CODEX_HOME": codexHome.path])

        let codexAccounts = settings.tokenAccounts(for: .codex)
        let claudeAccounts = settings.tokenAccounts(for: .claude)
        #expect(codexAccounts.count == 2)
        #expect(codexAccounts[0].id == activeID)
        #expect(codexAccounts[0].token == updatedDiskToken)
        #expect(codexAccounts[1].id == otherCodexID)
        #expect(codexAccounts[1].token == otherCodexToken)
        #expect(claudeAccounts.count == 1)
        #expect(claudeAccounts[0].id == claudeID)
        #expect(claudeAccounts[0].token == claudeToken)
    }

    @Test("sync no-ops when active codex token already matches disk")
    func syncNoOpWhenTokenUnchanged() async throws {
        let settings = Self.makeSettingsStore(suite: "CodexActiveAccountTokenSyncTests-unchanged")
        let unchangedToken = #"{"tokens":{"access_token":"same","refresh_token":"same-ref"}}"#
        settings.tokenAccountsByProvider = [
            .codex: ProviderTokenAccountData(
                version: 1,
                accounts: [
                    ProviderTokenAccount(
                        id: UUID(),
                        label: "Active",
                        token: unchangedToken,
                        addedAt: 0,
                        lastUsed: nil),
                ],
                activeIndex: 0),
        ]

        let codexHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-active-sync-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: codexHome) }
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try Data(unchangedToken.utf8).write(to: codexHome.appendingPathComponent("auth.json"), options: .atomic)

        let store = Self.makeUsageStore(settings: settings)
        let revisionBefore = settings.configRevision
        await store.syncActiveCodexAccountTokenFromDiskIfNeeded(env: ["CODEX_HOME": codexHome.path])

        #expect(settings.tokenAccounts(for: .codex).first?.token == unchangedToken)
        #expect(settings.configRevision == revisionBefore)
    }

    @Test("sync no-ops when there is no active codex account")
    func syncNoOpWithoutActiveCodexAccount() async throws {
        let settings = Self.makeSettingsStore(suite: "CodexActiveAccountTokenSyncTests-no-active")
        settings.tokenAccountsByProvider = [
            .claude: ProviderTokenAccountData(
                version: 1,
                accounts: [
                    ProviderTokenAccount(
                        id: UUID(),
                        label: "Claude",
                        token: "claude-token",
                        addedAt: 0,
                        lastUsed: nil),
                ],
                activeIndex: 0),
        ]

        let codexHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-active-sync-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: codexHome) }
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try Data(#"{"tokens":{"access_token":"unused","refresh_token":"unused-ref"}}"#.utf8)
            .write(to: codexHome.appendingPathComponent("auth.json"), options: .atomic)

        let store = Self.makeUsageStore(settings: settings)
        let revisionBefore = settings.configRevision
        await store.syncActiveCodexAccountTokenFromDiskIfNeeded(env: ["CODEX_HOME": codexHome.path])

        #expect(settings.configRevision == revisionBefore)
        #expect(settings.tokenAccounts(for: .claude).first?.token == "claude-token")
        #expect(settings.tokenAccounts(for: .codex).isEmpty)
    }

    @Test("sync specific codex account updates only targeted account token")
    func syncSpecificCodexAccountUpdatesOnlyTargetedAccountToken() async throws {
        let settings = Self.makeSettingsStore(suite: "CodexActiveAccountTokenSyncTests-specific")
        let firstID = UUID()
        let secondID = UUID()
        let firstToken = #"{"tokens":{"access_token":"first","refresh_token":"first-ref"}}"#
        let secondToken = #"{"tokens":{"access_token":"second","refresh_token":"second-ref"}}"#
        let updatedSecondToken = #"{"tokens":{"access_token":"second-new","refresh_token":"second-new-ref"}}"#

        settings.tokenAccountsByProvider = [
            .codex: ProviderTokenAccountData(
                version: 1,
                accounts: [
                    ProviderTokenAccount(
                        id: firstID,
                        label: "First",
                        token: firstToken,
                        addedAt: 0,
                        lastUsed: nil),
                    ProviderTokenAccount(
                        id: secondID,
                        label: "Second",
                        token: secondToken,
                        addedAt: 0,
                        lastUsed: nil),
                ],
                activeIndex: 0),
        ]

        let codexHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-active-sync-specific-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: codexHome) }
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try Data(updatedSecondToken.utf8).write(to: codexHome.appendingPathComponent("auth.json"), options: .atomic)

        let store = Self.makeUsageStore(settings: settings)
        await store.syncCodexAccountTokenFromDiskIfNeeded(accountID: secondID, env: ["CODEX_HOME": codexHome.path])

        let codexAccounts = settings.tokenAccounts(for: .codex)
        #expect(codexAccounts.count == 2)
        #expect(codexAccounts[0].id == firstID)
        #expect(codexAccounts[0].token == firstToken)
        #expect(codexAccounts[1].id == secondID)
        #expect(codexAccounts[1].token == updatedSecondToken)
    }

    @Test("sync specific codex account no-ops when account does not exist")
    func syncSpecificCodexAccountNoOpWhenAccountMissing() async throws {
        let settings = Self.makeSettingsStore(suite: "CodexActiveAccountTokenSyncTests-specific-missing")
        let onlyID = UUID()
        let unchangedToken = #"{"tokens":{"access_token":"only","refresh_token":"only-ref"}}"#
        settings.tokenAccountsByProvider = [
            .codex: ProviderTokenAccountData(
                version: 1,
                accounts: [
                    ProviderTokenAccount(
                        id: onlyID,
                        label: "Only",
                        token: unchangedToken,
                        addedAt: 0,
                        lastUsed: nil),
                ],
                activeIndex: 0),
        ]

        let codexHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-active-sync-specific-missing-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: codexHome) }
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try Data(#"{"tokens":{"access_token":"new","refresh_token":"new-ref"}}"#.utf8)
            .write(to: codexHome.appendingPathComponent("auth.json"), options: .atomic)

        let store = Self.makeUsageStore(settings: settings)
        let revisionBefore = settings.configRevision
        await store.syncCodexAccountTokenFromDiskIfNeeded(accountID: UUID(), env: ["CODEX_HOME": codexHome.path])

        #expect(settings.configRevision == revisionBefore)
        #expect(settings.tokenAccounts(for: .codex).first?.id == onlyID)
        #expect(settings.tokenAccounts(for: .codex).first?.token == unchangedToken)
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
}
