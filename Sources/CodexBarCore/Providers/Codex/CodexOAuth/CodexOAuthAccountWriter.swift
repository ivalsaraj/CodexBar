import Foundation

public enum CodexOAuthAccountWriterError: LocalizedError, Equatable {
    case emptyInput
    case invalidJSON(String)
    case missingCredentials
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .emptyInput:
            "No auth.json content provided."
        case let .invalidJSON(detail):
            "Invalid JSON: \(detail)"
        case .missingCredentials:
            "auth.json must contain tokens.access_token + tokens.refresh_token, or OPENAI_API_KEY."
        case let .writeFailed(detail):
            "Failed to write auth.json: \(detail)"
        }
    }
}

public enum CodexOAuthAccountWriter {
    /// Validates that `jsonString` is well-formed Codex auth JSON.
    /// Throws `CodexOAuthAccountWriterError` on any violation.
    public static func validate(jsonString: String) throws {
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CodexOAuthAccountWriterError.emptyInput }

        let data = Data(trimmed.utf8)
        let parsed: [String: Any]
        do {
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CodexOAuthAccountWriterError.invalidJSON("Root is not an object")
            }
            parsed = dict
        } catch let error as CodexOAuthAccountWriterError {
            throw error
        } catch {
            throw CodexOAuthAccountWriterError.invalidJSON(error.localizedDescription)
        }

        // Legacy API-key mode
        if let apiKey = parsed["OPENAI_API_KEY"] as? String,
           !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return
        }

        // OAuth token mode
        guard let tokens = parsed["tokens"] as? [String: Any] else {
            throw CodexOAuthAccountWriterError.missingCredentials
        }
        let accessToken = tokens["access_token"] as? String ?? ""
        let refreshToken = tokens["refresh_token"] as? String ?? ""
        guard !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !refreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw CodexOAuthAccountWriterError.missingCredentials
        }
    }

    /// Validates then atomically writes `jsonString` as `auth.json` inside `codexHomeDir`.
    /// Creates `codexHomeDir` if it does not exist.
    /// Throws `CodexOAuthAccountWriterError` on validation failure or write error.
    public static func write(jsonString: String, toCodexHome codexHomeDir: URL) throws {
        try self.validate(jsonString: jsonString)

        do {
            try FileManager.default.createDirectory(
                at: codexHomeDir,
                withIntermediateDirectories: true)
        } catch {
            throw CodexOAuthAccountWriterError.writeFailed(
                "Cannot create directory \(codexHomeDir.path): \(error.localizedDescription)")
        }

        let destination = codexHomeDir.appendingPathComponent("auth.json")
        let data = Data(jsonString.trimmingCharacters(in: .whitespacesAndNewlines).utf8)

        // Atomic write: Data.write(options:.atomic) handles create-or-overwrite on first write,
        // avoiding replaceItemAt which requires destination to already exist.
        do {
            try data.write(to: destination, options: .atomic)
        } catch {
            throw CodexOAuthAccountWriterError.writeFailed(error.localizedDescription)
        }

        // Enforce 0600 permissions - auth tokens must not be world-readable.
        do {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: destination.path)
        } catch {
            throw CodexOAuthAccountWriterError.writeFailed(
                "Cannot set 0600 permissions on auth.json: \(error.localizedDescription)")
        }
    }
}
