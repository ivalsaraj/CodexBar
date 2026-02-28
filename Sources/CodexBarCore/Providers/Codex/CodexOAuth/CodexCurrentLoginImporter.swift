import Foundation

public enum CodexCurrentLoginImporterError: LocalizedError {
    case notFound
    case invalidContent(String)

    public var errorDescription: String? {
        switch self {
        case .notFound:
            """
            No auth.json found. Set `cli_auth_credentials_store = "file"` in ~/.codex/config.toml, \
            run `codex login`, then import.
            """
        case let .invalidContent(detail):
            "auth.json is invalid: \(detail)"
        }
    }
}

public enum CodexCurrentLoginImporter {
    /// Reads `auth.json` from `codexHome`, validates it, and returns its raw string content.
    public static func read(fromCodexHome codexHome: URL) throws -> String {
        let authFile = codexHome.appendingPathComponent("auth.json")
        guard FileManager.default.fileExists(atPath: authFile.path) else {
            throw CodexCurrentLoginImporterError.notFound
        }
        let data = try Data(contentsOf: authFile)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw CodexCurrentLoginImporterError.invalidContent("File is not valid UTF-8")
        }
        do {
            try CodexOAuthAccountWriter.validate(jsonString: jsonString)
        } catch let writerError as CodexOAuthAccountWriterError {
            throw CodexCurrentLoginImporterError.invalidContent(
                writerError.errorDescription ?? writerError.localizedDescription)
        }
        return jsonString
    }

    /// Reads the default `~/.codex/auth.json`.
    public static func readDefault() throws -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let codexHome = home.appendingPathComponent(".codex")
        return try self.read(fromCodexHome: codexHome)
    }
}
