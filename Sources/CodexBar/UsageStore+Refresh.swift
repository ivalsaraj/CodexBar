import CodexBarCore
import Foundation

extension UsageStore {
    /// Force refresh Augment session (called from UI button)
    func forceRefreshAugmentSession() async {
        await self.performRuntimeAction(.forceSessionRefresh, for: .augment)
    }

    func refreshProvider(_ provider: UsageProvider, allowDisabled: Bool = false) async {
        guard let spec = self.providerSpecs[provider] else { return }
        let refreshGeneration = self.beginProviderRefreshGeneration(for: provider)

        if !spec.isEnabled(), !allowDisabled {
            self.refreshingProviders.remove(provider)
            await MainActor.run {
                self.snapshots.removeValue(forKey: provider)
                self.errors[provider] = nil
                self.lastSourceLabels.removeValue(forKey: provider)
                self.lastFetchAttempts.removeValue(forKey: provider)
                self.accountSnapshots.removeValue(forKey: provider)
                self.tokenSnapshots.removeValue(forKey: provider)
                self.tokenErrors[provider] = nil
                self.failureGates[provider]?.reset()
                self.tokenFailureGates[provider]?.reset()
                self.statuses.removeValue(forKey: provider)
                self.lastKnownSessionRemaining.removeValue(forKey: provider)
                self.lastKnownSessionWindowSource.removeValue(forKey: provider)
                self.lastTokenFetchAt.removeValue(forKey: provider)
                self.tokenAccountSnapshotCache.removeValue(forKey: provider)
            }
            return
        }

        self.refreshingProviders.insert(provider)
        defer { self.refreshingProviders.remove(provider) }

        let tokenAccounts = self.tokenAccounts(for: provider)
        if self.shouldFetchAllTokenAccounts(provider: provider, accounts: tokenAccounts) {
            await self.refreshTokenAccounts(
                provider: provider,
                accounts: tokenAccounts,
                refreshGeneration: refreshGeneration)
            return
        } else {
            _ = await MainActor.run {
                self.accountSnapshots.removeValue(forKey: provider)
            }
        }

        let fetchContext = spec.makeFetchContext()
        let descriptor = spec.descriptor
        // Keep provider fetch work off MainActor so slow keychain/process reads don't stall menu/UI responsiveness.
        let outcome = await withTaskGroup(
            of: ProviderFetchOutcome.self,
            returning: ProviderFetchOutcome.self)
        { group in
            group.addTask {
                await descriptor.fetchOutcome(context: fetchContext)
            }
            return await group.next()!
        }
        guard self.isLatestProviderRefreshGeneration(refreshGeneration, for: provider) else { return }

        if provider == .claude,
           ClaudeOAuthCredentialsStore.invalidateCacheIfCredentialsFileChanged()
        {
            await MainActor.run {
                self.snapshots.removeValue(forKey: .claude)
                self.errors[.claude] = nil
                self.lastSourceLabels.removeValue(forKey: .claude)
                self.lastFetchAttempts.removeValue(forKey: .claude)
                self.accountSnapshots.removeValue(forKey: .claude)
                self.tokenSnapshots.removeValue(forKey: .claude)
                self.tokenErrors[.claude] = nil
                self.failureGates[.claude]?.reset()
                self.tokenFailureGates[.claude]?.reset()
                self.lastTokenFetchAt.removeValue(forKey: .claude)
            }
        }
        guard self.isLatestProviderRefreshGeneration(refreshGeneration, for: provider) else { return }

        await MainActor.run {
            self.lastFetchAttempts[provider] = outcome.attempts
        }

        switch outcome.result {
        case let .success(result):
            let scoped = result.usage.scoped(to: provider)
            let selectedAccount = self.settings.selectedTokenAccount(for: provider)
            let displaySnapshot: UsageSnapshot = if let selectedAccount {
                self.applyAccountLabel(scoped, provider: provider, account: selectedAccount)
            } else {
                scoped
            }
            await MainActor.run {
                self.handleSessionQuotaTransition(provider: provider, snapshot: displaySnapshot)
                self.snapshots[provider] = displaySnapshot
                self.lastSourceLabels[provider] = result.sourceLabel
                self.errors[provider] = nil
                self.failureGates[provider]?.recordSuccess()
                if let selectedAccount {
                    self.cacheTokenAccountSnapshot(
                        displaySnapshot,
                        for: provider,
                        accountID: selectedAccount.id)
                }
            }
            if provider == .codex, result.sourceLabel == "oauth" {
                await self.syncActiveCodexAccountTokenFromDiskIfNeeded()
            }
            if let runtime = self.providerRuntimes[provider] {
                let context = ProviderRuntimeContext(
                    provider: provider, settings: self.settings, store: self)
                runtime.providerDidRefresh(context: context, provider: provider)
            }
        case let .failure(error):
            await MainActor.run {
                let hadPriorData = self.snapshots[provider] != nil
                let shouldSurface =
                    self.failureGates[provider]?
                        .shouldSurfaceError(onFailureWithPriorData: hadPriorData) ?? true
                if shouldSurface {
                    self.errors[provider] = error.localizedDescription
                    self.snapshots.removeValue(forKey: provider)
                } else {
                    self.errors[provider] = nil
                }
            }
            if let runtime = self.providerRuntimes[provider] {
                let context = ProviderRuntimeContext(
                    provider: provider, settings: self.settings, store: self)
                runtime.providerDidFail(context: context, provider: provider, error: error)
            }
        }
    }

    func beginProviderRefreshGeneration(for provider: UsageProvider) -> Int {
        let next = (self.providerRefreshGenerations[provider] ?? 0) + 1
        self.providerRefreshGenerations[provider] = next
        return next
    }

    func isLatestProviderRefreshGeneration(_ generation: Int, for provider: UsageProvider) -> Bool {
        self.providerRefreshGenerations[provider] == generation
    }
}
