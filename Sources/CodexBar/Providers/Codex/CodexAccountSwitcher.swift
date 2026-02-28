import CodexBarCore
import Foundation

/// Encapsulates all logic for switching the active Codex account.
/// Centralized here so any future switch trigger uses the same path.
@MainActor
enum CodexAccountSwitcher {
    /// Switches to the Codex account at `index` in `settings`.
    ///
    /// Ordering guarantee: auth.json is written before `activeIndex` advances.
    /// If the write fails, this method throws and the active index is not changed.
    static func switchToAccount(
        index: Int,
        settings: SettingsStore,
        codexHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")) throws
    {
        let accounts = settings.tokenAccounts(for: .codex)
        guard !accounts.isEmpty else { return }
        let clamped = max(0, min(index, accounts.count - 1))
        let token = accounts[clamped].token

        try Self.switchToAccount(
            token: token,
            codexHome: codexHome,
            advance: { settings.setActiveTokenAccountIndex(clamped, for: .codex) })
    }

    /// Internal testable overload to verify write-before-advance behavior.
    static func switchToAccount(
        token: String,
        codexHome: URL,
        advance: () -> Void) throws
    {
        try CodexOAuthAccountWriter.write(jsonString: token, toCodexHome: codexHome)
        advance()
    }
}
