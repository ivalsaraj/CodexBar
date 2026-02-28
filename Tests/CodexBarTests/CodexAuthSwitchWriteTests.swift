import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@Suite("Codex auth.json switch-write integration")
struct CodexAuthSwitchWriteTests {
    let validJSON = """
    {"tokens":{"access_token":"acct2_tok","refresh_token":"acct2_ref"}}
    """

    @Test("writing valid JSON to a custom codexHome creates auth.json")
    func writeValidJSON() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }

        try CodexOAuthAccountWriter.write(jsonString: self.validJSON, toCodexHome: dir)

        let auth = dir.appendingPathComponent("auth.json")
        let data = try Data(contentsOf: auth)
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let tokens = parsed?["tokens"] as? [String: Any]
        #expect(tokens?["access_token"] as? String == "acct2_tok")
    }

    @Test("write failure does not change existing auth.json content")
    func writeFailureDoesNotCorrupt() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let original = """
        {"tokens":{"access_token":"original_tok","refresh_token":"original_ref"}}
        """
        let auth = dir.appendingPathComponent("auth.json")
        try Data(original.utf8).write(to: auth)

        do {
            try CodexOAuthAccountWriter.write(jsonString: "bad json", toCodexHome: dir)
            Issue.record("Expected write to throw")
        } catch {
            // expected
        }

        let data = try Data(contentsOf: auth)
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let tokens = parsed?["tokens"] as? [String: Any]
        #expect(tokens?["access_token"] as? String == "original_tok")
    }

    @Test("switchToAccount - write fails -> advance closure NOT called")
    @MainActor
    func switchToAccountWriteFailsAdvanceNotCalled() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-switch-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        var advanceCalled = false

        do {
            try CodexAccountSwitcher.switchToAccount(
                token: "not-valid-json",
                codexHome: dir,
                advance: { advanceCalled = true })
        } catch {
            // Expected - write validation failed.
        }

        #expect(!advanceCalled, "advance must never be called when write throws")
    }

    @Test("temp-home cleanup is idempotent - double-cleanup does not throw")
    func tempHomeCleanupIsIdempotent() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-idempotent-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }

        let tempHome = try CodexOAuthTempHome.make(
            jsonString: self.validJSON,
            under: base)

        CodexOAuthTempHome.cleanup(tempHome)
        #expect(!FileManager.default.fileExists(atPath: tempHome.path))

        CodexOAuthTempHome.cleanup(tempHome)
    }
}
