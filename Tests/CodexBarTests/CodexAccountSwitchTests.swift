import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@Suite("Codex account switch - CODEX_HOME env injection")
struct CodexAccountSwitchTests {
    let validAuthJSON = """
    {"tokens":{"access_token":"tok_abc","refresh_token":"ref_xyz"}}
    """

    @Test("writeAndMakeTempCodexHome writes auth.json and returns valid dir URL")
    func writeAndMakeTempCodexHome() throws {
        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempBase) }

        let result = try CodexOAuthTempHome.make(
            jsonString: self.validAuthJSON,
            under: tempBase)

        #expect(FileManager.default.fileExists(atPath: result.path))
        let authFile = result.appendingPathComponent("auth.json")
        #expect(FileManager.default.fileExists(atPath: authFile.path))
    }

    @Test("make with invalid JSON throws")
    func makeWithInvalidJSON() throws {
        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempBase) }

        #expect(throws: CodexOAuthAccountWriterError.self) {
            _ = try CodexOAuthTempHome.make(jsonString: "bad json", under: tempBase)
        }
    }

    @Test("cleanup removes temp dir")
    func cleanupRemovesTempDir() throws {
        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempBase) }

        let tempHome = try CodexOAuthTempHome.make(
            jsonString: self.validAuthJSON,
            under: tempBase)

        CodexOAuthTempHome.cleanup(tempHome)
        #expect(!FileManager.default.fileExists(atPath: tempHome.path))
    }

    @Test("cleanupAll removes entire base dir")
    func cleanupAllRemovesBaseDir() throws {
        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-test-all-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempBase) }

        _ = try CodexOAuthTempHome.make(jsonString: self.validAuthJSON, under: tempBase)
        _ = try CodexOAuthTempHome.make(jsonString: self.validAuthJSON, under: tempBase)

        CodexOAuthTempHome.cleanupAll(under: tempBase)
        #expect(!FileManager.default.fileExists(atPath: tempBase.path))
    }

    @Test("switchToAccount normalizes payload before writing auth.json")
    @MainActor
    func switchToAccountUsesNormalizedPayload() throws {
        let codexHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-switch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: codexHome) }

        let rawToken = """
        {"tokens":{"access_token":"tok_abc","refresh_token":"ref_xyz"},"last_refresh":"2020-01-01T00:00:00Z"}
        """
        var advanced = false

        try CodexAccountSwitcher.switchToAccount(
            token: rawToken,
            codexHome: codexHome,
            advance: { advanced = true })

        let authData = try Data(contentsOf: codexHome.appendingPathComponent("auth.json"))
        let parsed = try #require(JSONSerialization.jsonObject(with: authData) as? [String: Any])
        let tokens = try #require(parsed["tokens"] as? [String: Any])
        let lastRefresh = try #require(parsed["last_refresh"] as? String)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        #expect(advanced)
        #expect(tokens["access_token"] as? String == "tok_abc")
        #expect(tokens["refresh_token"] as? String == "ref_xyz")
        #expect(lastRefresh != "2020-01-01T00:00:00Z")
        #expect(lastRefresh.hasSuffix("Z"))
        #expect(formatter.date(from: lastRefresh) != nil)
    }
}
