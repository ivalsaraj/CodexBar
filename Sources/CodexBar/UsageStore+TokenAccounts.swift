import CodexBarCore
import Foundation

struct TokenAccountUsageSnapshot: Identifiable, Sendable {
    let id: UUID
    let account: ProviderTokenAccount
    let snapshot: UsageSnapshot?
    let error: String?
    let sourceLabel: String?

    init(account: ProviderTokenAccount, snapshot: UsageSnapshot?, error: String?, sourceLabel: String?) {
        self.id = account.id
        self.account = account
        self.snapshot = snapshot
        self.error = error
        self.sourceLabel = sourceLabel
    }
}

extension UsageStore {
    func cachedTokenAccountSnapshot(for provider: UsageProvider, accountID: UUID) -> UsageSnapshot? {
        self.tokenAccountSnapshotCache[provider]?[accountID]
    }

    func fetchTokenAccountPreviewSnapshot(
        provider: UsageProvider,
        account: ProviderTokenAccount) async -> TokenAccountUsageSnapshot
    {
        let override = TokenAccountOverride(provider: provider, account: account)
        let outcome = await self.fetchOutcome(provider: provider, override: override)
        let resolved = self.resolveAccountOutcome(outcome, provider: provider, account: account)
        if let usage = resolved.usage {
            self.cacheTokenAccountSnapshot(usage, for: provider, accountID: account.id)
        }
        return resolved.snapshot
    }

    func tokenAccounts(for provider: UsageProvider) -> [ProviderTokenAccount] {
        guard TokenAccountSupportCatalog.support(for: provider) != nil else { return [] }
        return self.settings.tokenAccounts(for: provider)
    }

    func shouldFetchAllTokenAccounts(provider: UsageProvider, accounts: [ProviderTokenAccount]) -> Bool {
        guard TokenAccountSupportCatalog.support(for: provider) != nil else { return false }
        return self.settings.showAllTokenAccountsInMenu && accounts.count > 1
    }

    func refreshTokenAccounts(
        provider: UsageProvider,
        accounts: [ProviderTokenAccount],
        refreshGeneration: Int? = nil) async
    {
        let selectedAccount = self.settings.selectedTokenAccount(for: provider)
        let limitedAccounts = self.limitedTokenAccounts(accounts, selected: selectedAccount)
        let effectiveSelected = selectedAccount ?? limitedAccounts.first
        var snapshots: [TokenAccountUsageSnapshot] = []
        var selectedOutcome: ProviderFetchOutcome?
        var selectedSnapshot: UsageSnapshot?

        for account in limitedAccounts {
            guard self.shouldApplyRefreshGeneration(refreshGeneration, for: provider) else { return }
            let override = TokenAccountOverride(provider: provider, account: account)
            let outcome = await self.fetchOutcome(provider: provider, override: override)
            guard self.shouldApplyRefreshGeneration(refreshGeneration, for: provider) else { return }
            let resolved = self.resolveAccountOutcome(outcome, provider: provider, account: account)
            snapshots.append(resolved.snapshot)
            if let usage = resolved.usage {
                self.cacheTokenAccountSnapshot(usage, for: provider, accountID: account.id)
            }
            if account.id == effectiveSelected?.id {
                selectedOutcome = outcome
                selectedSnapshot = resolved.usage
            }
        }

        guard self.shouldApplyRefreshGeneration(refreshGeneration, for: provider) else { return }
        await MainActor.run {
            self.accountSnapshots[provider] = snapshots
        }

        await MainActor.run {
            CodexAccountEnvironment.flushTempHomes()
        }

        if let selectedOutcome {
            await self.applySelectedOutcome(
                selectedOutcome,
                provider: provider,
                account: effectiveSelected,
                fallbackSnapshot: selectedSnapshot,
                refreshGeneration: refreshGeneration)
        }
    }

    func limitedTokenAccounts(
        _ accounts: [ProviderTokenAccount],
        selected: ProviderTokenAccount?) -> [ProviderTokenAccount]
    {
        let limit = 6
        if accounts.count <= limit { return accounts }
        var limited = Array(accounts.prefix(limit))
        if let selected, !limited.contains(where: { $0.id == selected.id }) {
            limited.removeLast()
            limited.append(selected)
        }
        return limited
    }

    func fetchOutcome(
        provider: UsageProvider,
        override: TokenAccountOverride?) async -> ProviderFetchOutcome
    {
        let descriptor = ProviderDescriptorRegistry.descriptor(for: provider)
        let sourceMode = self.sourceMode(for: provider)
        let snapshot = ProviderRegistry.makeSettingsSnapshot(settings: self.settings, tokenOverride: override)
        let env = ProviderRegistry.makeEnvironment(
            base: ProcessInfo.processInfo.environment,
            provider: provider,
            settings: self.settings,
            tokenOverride: override)
        let verbose = self.settings.isVerboseLoggingEnabled
        let context = ProviderFetchContext(
            runtime: .app,
            sourceMode: sourceMode,
            includeCredits: false,
            webTimeout: 60,
            webDebugDumpHTML: false,
            verbose: verbose,
            env: env,
            settings: snapshot,
            fetcher: self.codexFetcher,
            claudeFetcher: self.claudeFetcher,
            browserDetection: self.browserDetection)
        return await descriptor.fetchOutcome(context: context)
    }

    func sourceMode(for provider: UsageProvider) -> ProviderSourceMode {
        ProviderCatalog.implementation(for: provider)?
            .sourceMode(context: ProviderSourceModeContext(provider: provider, settings: self.settings))
            ?? .auto
    }

    private struct ResolvedAccountOutcome {
        let snapshot: TokenAccountUsageSnapshot
        let usage: UsageSnapshot?
    }

    private func resolveAccountOutcome(
        _ outcome: ProviderFetchOutcome,
        provider: UsageProvider,
        account: ProviderTokenAccount) -> ResolvedAccountOutcome
    {
        switch outcome.result {
        case let .success(result):
            let scoped = result.usage.scoped(to: provider)
            let labeled = self.applyAccountLabel(scoped, provider: provider, account: account)
            let snapshot = TokenAccountUsageSnapshot(
                account: account,
                snapshot: labeled,
                error: nil,
                sourceLabel: result.sourceLabel)
            return ResolvedAccountOutcome(snapshot: snapshot, usage: labeled)
        case let .failure(error):
            let snapshot = TokenAccountUsageSnapshot(
                account: account,
                snapshot: nil,
                error: error.localizedDescription,
                sourceLabel: nil)
            return ResolvedAccountOutcome(snapshot: snapshot, usage: nil)
        }
    }

    func applySelectedOutcome(
        _ outcome: ProviderFetchOutcome,
        provider: UsageProvider,
        account: ProviderTokenAccount?,
        fallbackSnapshot: UsageSnapshot?,
        refreshGeneration: Int? = nil) async
    {
        guard self.shouldApplyRefreshGeneration(refreshGeneration, for: provider) else { return }
        await MainActor.run {
            self.lastFetchAttempts[provider] = outcome.attempts
        }
        switch outcome.result {
        case let .success(result):
            let scoped = result.usage.scoped(to: provider)
            let labeled: UsageSnapshot = if let account {
                self.applyAccountLabel(scoped, provider: provider, account: account)
            } else {
                scoped
            }
            guard self.shouldApplyRefreshGeneration(refreshGeneration, for: provider) else { return }
            await MainActor.run {
                self.handleSessionQuotaTransition(provider: provider, snapshot: labeled)
                self.snapshots[provider] = labeled
                self.lastSourceLabels[provider] = result.sourceLabel
                self.errors[provider] = nil
                self.failureGates[provider]?.recordSuccess()
                if let account {
                    self.cacheTokenAccountSnapshot(
                        labeled,
                        for: provider,
                        accountID: account.id)
                }
            }
        case let .failure(error):
            guard self.shouldApplyRefreshGeneration(refreshGeneration, for: provider) else { return }
            await MainActor.run {
                let hadPriorData = self.snapshots[provider] != nil || fallbackSnapshot != nil
                let shouldSurface = self.failureGates[provider]?
                    .shouldSurfaceError(onFailureWithPriorData: hadPriorData) ?? true
                if shouldSurface {
                    self.errors[provider] = error.localizedDescription
                    self.snapshots.removeValue(forKey: provider)
                } else {
                    self.errors[provider] = nil
                }
            }
        }
    }

    func shouldApplyRefreshGeneration(_ generation: Int?, for provider: UsageProvider) -> Bool {
        guard let generation else { return true }
        return self.isLatestProviderRefreshGeneration(generation, for: provider)
    }

    func cacheTokenAccountSnapshot(_ snapshot: UsageSnapshot, for provider: UsageProvider, accountID: UUID) {
        var providerCache = self.tokenAccountSnapshotCache[provider] ?? [:]
        providerCache[accountID] = snapshot
        self.tokenAccountSnapshotCache[provider] = providerCache
    }

    func applyAccountLabel(
        _ snapshot: UsageSnapshot,
        provider: UsageProvider,
        account: ProviderTokenAccount) -> UsageSnapshot
    {
        let label = account.label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return snapshot }
        let existing = snapshot.identity(for: provider)
        let email = existing?.accountEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedEmail = (email?.isEmpty ?? true) ? label : email
        let identity = ProviderIdentitySnapshot(
            providerID: provider,
            accountEmail: resolvedEmail,
            accountOrganization: existing?.accountOrganization,
            loginMethod: existing?.loginMethod)
        return snapshot.withIdentity(identity)
    }
}
