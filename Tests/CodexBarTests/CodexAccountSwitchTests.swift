import Foundation
import Testing
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
}
