import Foundation
import Testing
@testable import CodexBarCore

@Suite("Codex - import current login")
struct CodexImportCurrentLoginTests {
    @Test("reads valid auth.json from a given path")
    func readsValidAuthJSON() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let json = """
        {"auth_mode":"chatgpt","tokens":{"access_token":"import_tok","refresh_token":"import_ref"}}
        """
        try Data(json.utf8).write(to: dir.appendingPathComponent("auth.json"))

        let result = try CodexCurrentLoginImporter.read(fromCodexHome: dir)
        #expect(result.contains("import_tok"))
    }

    @Test("returns error when auth.json is absent")
    func returnsErrorWhenAbsent() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent-\(UUID().uuidString)")
        #expect(throws: CodexCurrentLoginImporterError.self) {
            _ = try CodexCurrentLoginImporter.read(fromCodexHome: dir)
        }
    }

    @Test("returns error when auth.json has no tokens")
    func returnsErrorWhenNoTokens() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{\"auth_mode\":\"chatgpt\"}".utf8)
            .write(to: dir.appendingPathComponent("auth.json"))

        #expect(throws: CodexCurrentLoginImporterError.self) {
            _ = try CodexCurrentLoginImporter.read(fromCodexHome: dir)
        }
    }

    @Test("absent auth.json error message guides user to file-mode")
    func absentAuthJSONMessageMentionsFileMode() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent-\(UUID().uuidString)")
        do {
            _ = try CodexCurrentLoginImporter.read(fromCodexHome: dir)
            Issue.record("Expected throw")
        } catch let error as CodexCurrentLoginImporterError {
            let msg = error.errorDescription ?? ""
            #expect(msg.contains("codex login") || msg.contains("auth.json"))
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }
}
