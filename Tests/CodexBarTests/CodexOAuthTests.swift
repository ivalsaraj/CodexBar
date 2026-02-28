import Foundation
import Testing
@testable import CodexBarCore

@Suite
struct CodexOAuthTests {
    private func makeContext(env: [String: String]) -> ProviderFetchContext {
        let browserDetection = BrowserDetection(cacheTTL: 0)
        return ProviderFetchContext(
            runtime: .app,
            sourceMode: .oauth,
            includeCredits: false,
            webTimeout: 60,
            webDebugDumpHTML: false,
            verbose: false,
            env: env,
            settings: nil,
            fetcher: UsageFetcher(),
            claudeFetcher: ClaudeUsageFetcher(browserDetection: browserDetection),
            browserDetection: browserDetection)
    }

    @Test
    func parsesOAuthCredentials() throws {
        let json = """
        {
          "OPENAI_API_KEY": null,
          "tokens": {
            "access_token": "access-token",
            "refresh_token": "refresh-token",
            "id_token": "id-token",
            "account_id": "account-123"
          },
          "last_refresh": "2025-12-20T12:34:56Z"
        }
        """
        let creds = try CodexOAuthCredentialsStore.parse(data: Data(json.utf8))
        #expect(creds.accessToken == "access-token")
        #expect(creds.refreshToken == "refresh-token")
        #expect(creds.idToken == "id-token")
        #expect(creds.accountId == "account-123")
        #expect(creds.lastRefresh != nil)
    }

    @Test
    func parsesAPIKeyCredentials() throws {
        let json = """
        {
          "OPENAI_API_KEY": "sk-test"
        }
        """
        let creds = try CodexOAuthCredentialsStore.parse(data: Data(json.utf8))
        #expect(creds.accessToken == "sk-test")
        #expect(creds.refreshToken.isEmpty)
        #expect(creds.idToken == nil)
        #expect(creds.accountId == nil)
    }

    @Test
    func decodesCreditsBalanceString() throws {
        let json = """
        {
          "plan_type": "pro",
          "rate_limit": {
            "primary_window": {
              "used_percent": 12,
              "reset_at": 1766948068,
              "limit_window_seconds": 18000
            }
          },
          "credits": {
            "has_credits": false,
            "unlimited": false,
            "balance": "0"
          }
        }
        """
        let response = try CodexOAuthUsageFetcher._decodeUsageResponseForTesting(Data(json.utf8))
        #expect(response.planType?.rawValue == "pro")
        #expect(response.credits?.balance == 0)
        #expect(response.credits?.hasCredits == false)
        #expect(response.credits?.unlimited == false)
    }

    @Test
    func mapsUsageWindowsFromOAuth() throws {
        let json = """
        {
          "rate_limit": {
            "primary_window": {
              "used_percent": 22,
              "reset_at": 1766948068,
              "limit_window_seconds": 18000
            },
            "secondary_window": {
              "used_percent": 43,
              "reset_at": 1767407914,
              "limit_window_seconds": 604800
            }
          }
        }
        """
        let creds = CodexOAuthCredentials(
            accessToken: "access",
            refreshToken: "refresh",
            idToken: nil,
            accountId: nil,
            lastRefresh: Date())
        let snapshot = try CodexOAuthFetchStrategy._mapUsageForTesting(Data(json.utf8), credentials: creds)
        #expect(snapshot.primary?.usedPercent == 22)
        #expect(snapshot.primary?.windowMinutes == 300)
        #expect(snapshot.secondary?.usedPercent == 43)
        #expect(snapshot.secondary?.windowMinutes == 10080)
        #expect(snapshot.primary?.resetsAt != nil)
        #expect(snapshot.secondary?.resetsAt != nil)
    }

    @Test
    func resolvesChatGPTUsageURLFromConfig() {
        let config = "chatgpt_base_url = \"https://chatgpt.com/backend-api/\"\n"
        let url = CodexOAuthUsageFetcher._resolveUsageURLForTesting(configContents: config)
        #expect(url.absoluteString == "https://chatgpt.com/backend-api/wham/usage")
    }

    @Test
    func resolvesCodexUsageURLFromConfig() {
        let config = "chatgpt_base_url = \"https://api.openai.com\"\n"
        let url = CodexOAuthUsageFetcher._resolveUsageURLForTesting(configContents: config)
        #expect(url.absoluteString == "https://api.openai.com/api/codex/usage")
    }

    @Test
    func normalizesChatGPTBaseURLWithoutBackendAPI() {
        let config = "chatgpt_base_url = \"https://chat.openai.com\"\n"
        let url = CodexOAuthUsageFetcher._resolveUsageURLForTesting(configContents: config)
        #expect(url.absoluteString == "https://chat.openai.com/backend-api/wham/usage")
    }

    @Test
    func credentialsStoreLoadRespectsProvidedCodexHomeEnv() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-oauth-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let json = """
        {
          "tokens": {
            "access_token": "preview-access-token",
            "refresh_token": "preview-refresh-token"
          }
        }
        """
        try Data(json.utf8).write(to: tempRoot.appendingPathComponent("auth.json"), options: .atomic)

        let creds = try CodexOAuthCredentialsStore.load(env: ["CODEX_HOME": tempRoot.path])
        #expect(creds.accessToken == "preview-access-token")
        #expect(creds.refreshToken == "preview-refresh-token")
    }

    @Test
    func codexOAuthStrategyAvailabilityUsesContextEnv() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-oauth-strategy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let json = """
        {
          "tokens": {
            "access_token": "strategy-access-token",
            "refresh_token": "strategy-refresh-token"
          }
        }
        """
        try Data(json.utf8).write(to: tempRoot.appendingPathComponent("auth.json"), options: .atomic)

        let strategy = CodexOAuthFetchStrategy()
        let validEnvContext = self.makeContext(env: ["CODEX_HOME": tempRoot.path])
        let missingEnvContext = self.makeContext(env: ["CODEX_HOME": tempRoot.appendingPathComponent("missing").path])

        let validAvailable = await strategy.isAvailable(validEnvContext)
        let missingAvailable = await strategy.isAvailable(missingEnvContext)
        #expect(validAvailable)
        #expect(!missingAvailable)
    }
}
