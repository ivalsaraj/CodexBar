import Foundation
import Testing
@testable import CodexBarCore

@Suite("CodexOAuthAccountWriter")
struct CodexOAuthAccountWriterTests {
    // MARK: - validate()

    @Test("valid OAuth JSON passes validation")
    func validateValidOAuth() {
        let json = """
        {"auth_mode":"chatgpt","tokens":{"access_token":"tok_abc","refresh_token":"ref_xyz","id_token":"id_123",
        "account_id":"acc_456"},"last_refresh":"2026-02-26T10:00:00Z"}
        """
        #expect(throws: Never.self) {
            try CodexOAuthAccountWriter.validate(jsonString: json)
        }
    }

    @Test("legacy API key JSON passes validation")
    func validateLegacyAPIKey() {
        let json = """
        {"OPENAI_API_KEY":"sk-abc123"}
        """
        #expect(throws: Never.self) {
            try CodexOAuthAccountWriter.validate(jsonString: json)
        }
    }

    @Test("empty string fails validation")
    func validateEmptyString() {
        #expect(throws: CodexOAuthAccountWriterError.self) {
            try CodexOAuthAccountWriter.validate(jsonString: "")
        }
    }

    @Test("invalid JSON fails validation")
    func validateInvalidJSON() {
        #expect(throws: CodexOAuthAccountWriterError.self) {
            try CodexOAuthAccountWriter.validate(jsonString: "not json")
        }
    }

    @Test("missing tokens and API key fails validation")
    func validateMissingTokens() {
        let json = """
        {"auth_mode":"chatgpt"}
        """
        #expect(throws: CodexOAuthAccountWriterError.self) {
            try CodexOAuthAccountWriter.validate(jsonString: json)
        }
    }

    @Test("empty access_token fails validation")
    func validateEmptyAccessToken() {
        let json = """
        {"tokens":{"access_token":"","refresh_token":"ref_xyz"}}
        """
        #expect(throws: CodexOAuthAccountWriterError.self) {
            try CodexOAuthAccountWriter.validate(jsonString: json)
        }
    }

    @Test("missing refresh_token fails validation for OAuth mode")
    func validateMissingRefreshToken() {
        let json = """
        {"tokens":{"access_token":"tok_abc"}}
        """
        #expect(throws: CodexOAuthAccountWriterError.self) {
            try CodexOAuthAccountWriter.validate(jsonString: json)
        }
    }

    // MARK: - write(to:)

    @Test("write creates auth.json atomically")
    func writeCreatesFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let json = """
        {"tokens":{"access_token":"tok_abc","refresh_token":"ref_xyz"}}
        """
        try CodexOAuthAccountWriter.write(jsonString: json, toCodexHome: tempDir)

        let authFile = tempDir.appendingPathComponent("auth.json")
        #expect(FileManager.default.fileExists(atPath: authFile.path))

        let data = try Data(contentsOf: authFile)
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let tokens = parsed?["tokens"] as? [String: Any]
        #expect(tokens?["access_token"] as? String == "tok_abc")
    }

    @Test("write creates intermediate directories")
    func writeCreatesDirectories() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("nested")
        defer { try? FileManager.default.removeItem(at: tempDir.deletingLastPathComponent()) }

        let json = """
        {"tokens":{"access_token":"tok_abc","refresh_token":"ref_xyz"}}
        """
        try CodexOAuthAccountWriter.write(jsonString: json, toCodexHome: tempDir)
        let authFile = tempDir.appendingPathComponent("auth.json")
        #expect(FileManager.default.fileExists(atPath: authFile.path))
    }

    @Test("write to nonexistent path succeeds - first import scenario")
    func writeToNonExistentPath() throws {
        // Destination dir does NOT exist - simulates first-time account import.
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let json = """
        {"tokens":{"access_token":"first_tok","refresh_token":"first_ref"}}
        """
        // Must not throw - Data.write(options:.atomic) handles create-or-overwrite.
        try CodexOAuthAccountWriter.write(jsonString: json, toCodexHome: tempDir)

        let authFile = tempDir.appendingPathComponent("auth.json")
        #expect(FileManager.default.fileExists(atPath: authFile.path))
    }

    @Test("written auth.json has 0600 permissions")
    func writeEnforces0600Permissions() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let json = """
        {"tokens":{"access_token":"tok_abc","refresh_token":"ref_xyz"}}
        """
        try CodexOAuthAccountWriter.write(jsonString: json, toCodexHome: tempDir)

        let authFile = tempDir.appendingPathComponent("auth.json")
        let attrs = try FileManager.default.attributesOfItem(atPath: authFile.path)
        let perms = attrs[.posixPermissions] as? Int ?? 0
        #expect(perms == 0o600, "Expected 0600, got \(String(format: "%o", perms))")
    }

    @Test("write with invalid JSON throws before touching disk")
    func writeInvalidJSONThrows() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        #expect(throws: CodexOAuthAccountWriterError.self) {
            try CodexOAuthAccountWriter.write(jsonString: "bad json", toCodexHome: tempDir)
        }
        // Directory should NOT have been created
        #expect(!FileManager.default.fileExists(atPath: tempDir.path))
    }

    @Test("write overwrites existing auth.json atomically")
    func writeOverwritesExisting() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let authFile = tempDir.appendingPathComponent("auth.json")
        try Data("{\"tokens\":{\"access_token\":\"old\",\"refresh_token\":\"old\"}}".utf8)
            .write(to: authFile)

        let newJSON = """
        {"tokens":{"access_token":"new_tok","refresh_token":"new_ref"}}
        """
        try CodexOAuthAccountWriter.write(jsonString: newJSON, toCodexHome: tempDir)

        let data = try Data(contentsOf: authFile)
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let tokens = parsed?["tokens"] as? [String: Any]
        #expect(tokens?["access_token"] as? String == "new_tok")
    }
}
