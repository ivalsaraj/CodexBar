import Foundation
import Testing
@testable import CodexBarCore

@Suite("TokenAccountSupportCatalog - Codex")
struct TokenAccountSupportCatalogCodexTests {
    @Test("codex is registered in the catalog")
    func codexIsRegistered() {
        let support = TokenAccountSupportCatalog.support(for: .codex)
        #expect(support != nil)
    }

    @Test("codex injection type is codexOAuth")
    func codexInjectionType() {
        let support = TokenAccountSupportCatalog.support(for: .codex)
        guard case .codexOAuth = support?.injection else {
            Issue.record("Expected .codexOAuth injection, got \(String(describing: support?.injection))")
            return
        }
    }

    @Test("envOverride for codex returns nil (file write handled separately)")
    func codexEnvOverrideReturnsNil() {
        let result = TokenAccountSupportCatalog.envOverride(
            for: .codex,
            token: "{\"tokens\":{\"access_token\":\"tok\",\"refresh_token\":\"ref\"}}")
        // codexOAuth writes the file at switch time, not via envOverride
        #expect(result == nil)
    }

    @Test("codex placeholder guides user to auth.json")
    func codexPlaceholder() {
        let support = TokenAccountSupportCatalog.support(for: .codex)
        let placeholder = support?.placeholder ?? ""
        #expect(placeholder.contains("auth.json") || placeholder.contains("import"))
    }

    @Test("codex requiresManualCookieSource is false")
    func codexRequiresManualCookieSource() {
        let support = TokenAccountSupportCatalog.support(for: .codex)
        #expect(support?.requiresManualCookieSource == false)
    }
}
