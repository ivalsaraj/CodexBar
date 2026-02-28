import Foundation

/// Manages ephemeral per-account CODEX_HOME directories used during
/// parallel usage fetching for inactive Codex accounts.
public enum CodexOAuthTempHome {
    /// Creates a temp directory under `base`, writes `auth.json` into it,
    /// and returns the directory URL (to be passed as CODEX_HOME).
    /// Throws if `jsonString` is invalid or the write fails.
    public static func make(jsonString: String, under base: URL) throws -> URL {
        let dir = base.appendingPathComponent(UUID().uuidString)
        try CodexOAuthAccountWriter.write(jsonString: jsonString, toCodexHome: dir)

        // Restrict temp dir to owner-only access - auth tokens must not be world-readable.
        do {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: dir.path)
        } catch {
            try? FileManager.default.removeItem(at: dir)
            throw CodexOAuthAccountWriterError.writeFailed(
                "Cannot set 0700 permissions on temp CODEX_HOME: \(error.localizedDescription)")
        }
        return dir
    }

    /// Removes a single temp CODEX_HOME directory created by `make(jsonString:under:)`.
    public static func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    /// Removes the entire `base` directory tree (all temp CODEX_HOMEs at once).
    /// Safe to call even if `base` does not exist.
    public static func cleanupAll(under base: URL) {
        try? FileManager.default.removeItem(at: base)
    }
}
