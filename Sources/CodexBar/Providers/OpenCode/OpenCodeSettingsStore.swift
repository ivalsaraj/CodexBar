import CodexBarCore
import Foundation

extension SettingsStore {
    private static let openCodeWorkspaceAccountVersion = 1

    var openCodeWorkspaceAccounts: [OpenCodeWorkspaceAccount] {
        self.configSnapshot.providerConfig(for: .opencode)?.openCodeWorkspaceAccounts?.accounts ?? []
    }

    var selectedOpenCodeWorkspaceAccount: OpenCodeWorkspaceAccount? {
        self.configSnapshot.providerConfig(for: .opencode)?.openCodeWorkspaceAccounts?.activeAccount
    }

    var unboundOpenCodeTokenAccounts: [ProviderTokenAccount] {
        let boundIDs = Set(self.openCodeWorkspaceAccounts.map(\.tokenAccountID))
        return self.tokenAccounts(for: .opencode).filter { !boundIDs.contains($0.id) }
    }

    var openCodeMenuTokenAccounts: [ProviderTokenAccount] {
        self.openCodeWorkspaceAccounts.compactMap { workspaceAccount in
            guard let tokenAccount = self.linkedOpenCodeTokenAccount(for: workspaceAccount) else { return nil }
            return ProviderTokenAccount(
                id: workspaceAccount.id,
                label: workspaceAccount.label,
                token: tokenAccount.token,
                addedAt: workspaceAccount.addedAt,
                lastUsed: tokenAccount.lastUsed)
        }
    }

    var selectedOpenCodeMenuTokenAccount: ProviderTokenAccount? {
        guard let selected = self.selectedOpenCodeWorkspaceAccount else { return nil }
        return self.openCodeMenuTokenAccount(for: selected)
    }

    var opencodeWorkspaceID: String {
        get { self.configSnapshot.providerConfig(for: .opencode)?.workspaceID ?? "" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = trimmed.isEmpty ? nil : trimmed
            self.updateProviderConfig(provider: .opencode) { entry in
                entry.workspaceID = value
            }
        }
    }

    var opencodeCookieHeader: String {
        get { self.configSnapshot.providerConfig(for: .opencode)?.sanitizedCookieHeader ?? "" }
        set {
            self.updateProviderConfig(provider: .opencode) { entry in
                entry.cookieHeader = self.normalizedConfigValue(newValue)
            }
            self.logSecretUpdate(provider: .opencode, field: "cookieHeader", value: newValue)
        }
    }

    var opencodeCookieSource: ProviderCookieSource {
        get { self.resolvedCookieSource(provider: .opencode, fallback: .auto) }
        set {
            self.updateProviderConfig(provider: .opencode) { entry in
                entry.cookieSource = newValue
            }
            self.logProviderModeChange(provider: .opencode, field: "cookieSource", value: newValue.rawValue)
        }
    }

    var opencodeDashboardURLOverride: URL? {
        let override = ProcessInfo.processInfo.environment["CODEXBAR_OPENCODE_WORKSPACE_ID"]
        let selectedWorkspace = self.selectedOpenCodeWorkspaceAccount?.workspaceID ?? self.opencodeWorkspaceID
        let workspace = (override ?? selectedWorkspace).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let workspaceID = Self.normalizeOpenCodeWorkspaceID(workspace),
              let url = URL(string: "https://opencode.ai/workspace/\(workspaceID)/go")
        else {
            return nil
        }
        return url
    }

    func ensureOpenCodeCookieLoaded() {}
}

extension SettingsStore {
    private static func normalizeOpenCodeWorkspaceID(_ raw: String?) -> String? {
        OpenCodeWorkspaceDiscovery.normalizeWorkspaceID(raw)
    }
}

extension SettingsStore {
    func opencodeSettingsSnapshot(tokenOverride: TokenAccountOverride?) -> ProviderSettingsSnapshot
    .OpenCodeProviderSettings {
        let selectedWorkspaceAccount = self.previewOpenCodeWorkspaceAccount(for: tokenOverride)
            ?? self.selectedOpenCodeWorkspaceAccount
        return ProviderSettingsSnapshot.OpenCodeProviderSettings(
            cookieSource: self.opencodeSnapshotCookieSource(tokenOverride: tokenOverride),
            manualCookieHeader: self.opencodeSnapshotCookieHeader(tokenOverride: tokenOverride),
            workspaceID: selectedWorkspaceAccount?.workspaceID ?? self.opencodeWorkspaceID)
    }

    private func opencodeSnapshotCookieHeader(tokenOverride: TokenAccountOverride?) -> String {
        let fallback = self.opencodeCookieHeader
        guard let support = TokenAccountSupportCatalog.support(for: .opencode),
              case .cookieHeader = support.injection
        else {
            return fallback
        }
        guard let account = self.selectedOpenCodeTokenAccount(tokenOverride: tokenOverride)
        else {
            return fallback
        }
        return TokenAccountSupportCatalog.normalizedCookieHeader(account.token, support: support)
    }

    private func opencodeSnapshotCookieSource(tokenOverride: TokenAccountOverride?) -> ProviderCookieSource {
        let fallback = self.opencodeCookieSource
        guard let support = TokenAccountSupportCatalog.support(for: .opencode),
              support.requiresManualCookieSource
        else {
            return fallback
        }
        if self.tokenAccounts(for: .opencode).isEmpty { return fallback }
        return .manual
    }

    private func selectedOpenCodeTokenAccount(tokenOverride: TokenAccountOverride?) -> ProviderTokenAccount? {
        if let previewWorkspaceAccount = self.previewOpenCodeWorkspaceAccount(for: tokenOverride),
           let linked = self.linkedOpenCodeTokenAccount(for: previewWorkspaceAccount)
        {
            return linked
        }
        if let tokenOverride, tokenOverride.provider == .opencode {
            return tokenOverride.account
        }
        if let linked = self.linkedOpenCodeTokenAccount(for: self.selectedOpenCodeWorkspaceAccount) {
            return linked
        }
        return self.selectedTokenAccount(for: .opencode)
    }

    func openCodeWorkspaceAccount(menuAccountID: UUID) -> OpenCodeWorkspaceAccount? {
        self.openCodeWorkspaceAccounts.first(where: { $0.id == menuAccountID })
    }

    private func openCodeMenuTokenAccount(for account: OpenCodeWorkspaceAccount) -> ProviderTokenAccount? {
        guard let tokenAccount = self.linkedOpenCodeTokenAccount(for: account) else { return nil }
        return ProviderTokenAccount(
            id: account.id,
            label: account.label,
            token: tokenAccount.token,
            addedAt: account.addedAt,
            lastUsed: tokenAccount.lastUsed)
    }

    private func previewOpenCodeWorkspaceAccount(
        for tokenOverride: TokenAccountOverride?) -> OpenCodeWorkspaceAccount?
    {
        guard let tokenOverride, tokenOverride.provider == .opencode else { return nil }
        return self.openCodeWorkspaceAccount(menuAccountID: tokenOverride.account.id)
    }

    private func linkedOpenCodeTokenAccount(for account: OpenCodeWorkspaceAccount?) -> ProviderTokenAccount? {
        guard let tokenAccountID = account?.tokenAccountID else { return nil }
        return self.tokenAccounts(for: .opencode).first(where: { $0.id == tokenAccountID })
    }

    func ensureOpenCodeWorkspaceAccountMigrationIfNeeded() {
        guard self.openCodeWorkspaceAccounts.isEmpty else { return }
        guard let workspaceID = Self.normalizeOpenCodeWorkspaceID(self.opencodeWorkspaceID) else { return }
        let tokenAccounts = self.tokenAccounts(for: .opencode)
        guard tokenAccounts.count == 1, let tokenAccount = tokenAccounts.first else { return }

        _ = self.saveOpenCodeWorkspaceAccount(
            existingAccountID: nil,
            tokenAccountID: tokenAccount.id,
            label: tokenAccount.label,
            workspaceID: workspaceID,
            workspaceLabel: workspaceID,
            discoveredOwnerLabel: nil)
    }

    @discardableResult
    func saveOpenCodeWorkspaceAccount(
        existingAccountID: UUID? = nil,
        tokenAccountID: UUID,
        label: String,
        workspaceID rawWorkspaceID: String,
        workspaceLabel rawWorkspaceLabel: String?,
        discoveredOwnerLabel rawOwnerLabel: String?) -> UUID?
    {
        guard self.tokenAccounts(for: .opencode).contains(where: { $0.id == tokenAccountID }) else { return nil }
        guard let workspaceID = Self.normalizeOpenCodeWorkspaceID(rawWorkspaceID) else { return nil }

        let normalizedLabel = Self.normalizeOpenCodeWorkspaceLabel(label) ?? workspaceID
        let normalizedWorkspaceLabel = Self.normalizeOpenCodeWorkspaceLabel(rawWorkspaceLabel) ?? workspaceID
        let normalizedOwnerLabel = Self.normalizeOpenCodeWorkspaceLabel(rawOwnerLabel)
        let existing = self.configSnapshot.providerConfig(for: .opencode)?.openCodeWorkspaceAccounts
        let accountID = existingAccountID ?? UUID()
        let now = Date().timeIntervalSince1970

        var accounts = existing?.accounts ?? []
        if let index = accounts.firstIndex(where: { $0.id == accountID }) {
            let prior = accounts[index]
            accounts[index] = OpenCodeWorkspaceAccount(
                id: prior.id,
                tokenAccountID: tokenAccountID,
                label: normalizedLabel,
                workspaceID: workspaceID,
                workspaceLabel: normalizedWorkspaceLabel,
                discoveredOwnerLabel: normalizedOwnerLabel,
                addedAt: prior.addedAt,
                lastValidatedAt: now)
        } else {
            accounts.append(OpenCodeWorkspaceAccount(
                id: accountID,
                tokenAccountID: tokenAccountID,
                label: normalizedLabel,
                workspaceID: workspaceID,
                workspaceLabel: normalizedWorkspaceLabel,
                discoveredOwnerLabel: normalizedOwnerLabel,
                addedAt: now,
                lastValidatedAt: now))
        }

        let activeAccountID = existing?.activeAccountID ?? accountID
        self.updateProviderConfig(provider: .opencode) { entry in
            entry.openCodeWorkspaceAccounts = OpenCodeWorkspaceAccountData(
                version: existing?.version ?? Self.openCodeWorkspaceAccountVersion,
                activeAccountID: activeAccountID,
                accounts: accounts)
        }
        return accountID
    }

    @discardableResult
    func setActiveOpenCodeWorkspaceAccount(id: UUID) -> Bool {
        guard let data = self.configSnapshot.providerConfig(for: .opencode)?.openCodeWorkspaceAccounts,
              data.accounts.contains(where: { $0.id == id })
        else {
            return false
        }
        guard data.activeAccountID != id else { return true }
        self.updateProviderConfig(provider: .opencode) { entry in
            entry.openCodeWorkspaceAccounts = OpenCodeWorkspaceAccountData(
                version: data.version,
                activeAccountID: id,
                accounts: data.accounts)
        }
        return true
    }

    func removeOpenCodeWorkspaceAccount(id: UUID) {
        guard let data = self.configSnapshot.providerConfig(for: .opencode)?.openCodeWorkspaceAccounts else { return }
        let filtered = data.accounts.filter { $0.id != id }
        self.updateProviderConfig(provider: .opencode) { entry in
            if filtered.isEmpty {
                entry.openCodeWorkspaceAccounts = nil
            } else {
                let nextActiveAccountID = filtered.contains(where: { $0.id == data.activeAccountID }) ?
                    data.activeAccountID : filtered.first?.id
                entry.openCodeWorkspaceAccounts = OpenCodeWorkspaceAccountData(
                    version: data.version,
                    activeAccountID: nextActiveAccountID,
                    accounts: filtered)
            }
        }
    }

    func pruneOpenCodeWorkspaceAccountsIfNeeded() {
        guard let data = self.configSnapshot.providerConfig(for: .opencode)?.openCodeWorkspaceAccounts else { return }
        let validTokenAccountIDs = Set(self.tokenAccounts(for: .opencode).map(\.id))
        let pruned = data.pruned(validTokenAccountIDs: validTokenAccountIDs)
        guard pruned != data else { return }
        self.updateProviderConfig(provider: .opencode) { entry in
            entry.openCodeWorkspaceAccounts = pruned.accounts.isEmpty ? nil : pruned
        }
    }

    private static func normalizeOpenCodeWorkspaceLabel(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
