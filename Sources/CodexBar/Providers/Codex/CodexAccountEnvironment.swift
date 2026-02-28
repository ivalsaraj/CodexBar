import CodexBarCore
import Foundation

/// Thread-safe registry for temp CODEX_HOME directories created during
/// parallel usage fetches. Cleaned up after each fetch cycle.
@MainActor
enum CodexAccountEnvironment {
    static let tempBase: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex-bar-tmp")

    private static var pendingTempHomes: [URL] = []

    static func registerTempHome(_ url: URL) {
        self.pendingTempHomes.append(url)
    }

    /// Call after a fetch cycle completes. Removes all temp dirs created during it.
    static func flushTempHomes() {
        for dir in self.pendingTempHomes {
            CodexOAuthTempHome.cleanup(dir)
        }
        self.pendingTempHomes.removeAll()
    }

    /// Called on app launch - removes any stale temp dirs from a previous crash.
    static func cleanupOnLaunch() {
        CodexOAuthTempHome.cleanupAll(under: self.tempBase)
    }
}
