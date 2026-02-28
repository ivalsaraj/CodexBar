import AppKit
import CodexBarCore
import Foundation

extension StatusItemController {
    struct TokenAccountMenuDisplay {
        let provider: UsageProvider
        let accounts: [ProviderTokenAccount]
        let snapshots: [TokenAccountUsageSnapshot]
        let activeIndex: Int
        let selectedIndex: Int
        let sessionBadgeTexts: [String?]
        let showAll: Bool
        let showSwitcher: Bool
    }

    private final class TokenAccountSwitchActionPayload: NSObject {
        let provider: UsageProvider
        let accountIndex: Int

        init(provider: UsageProvider, accountIndex: Int) {
            self.provider = provider
            self.accountIndex = accountIndex
        }
    }

    func addTokenAccountSwitcherIfNeeded(to menu: NSMenu, display: TokenAccountMenuDisplay?) {
        guard let display, display.showSwitcher else { return }
        let switcherItem = self.makeTokenAccountSwitcherItem(display: display, menu: menu)
        menu.addItem(switcherItem)
        if let switchItem = self.makeTokenAccountSwitchActionItem(display: display) {
            menu.addItem(switchItem)
        }
        menu.addItem(.separator())
    }

    private func makeTokenAccountSwitcherItem(
        display: TokenAccountMenuDisplay,
        menu: NSMenu) -> NSMenuItem
    {
        let view = TokenAccountSwitcherView(
            accounts: display.accounts,
            sessionBadgeTexts: display.sessionBadgeTexts,
            activeIndex: display.activeIndex,
            selectedIndex: display.selectedIndex,
            width: self.menuCardWidth(for: self.store.enabledProviders(), menu: menu),
            onSelect: { [weak self, weak menu] index in
                guard let self, let menu else { return }
                self.selectTokenAccountPreview(display: display, index: index, menu: menu)
            })
        let item = NSMenuItem()
        item.view = view
        item.isEnabled = false
        return item
    }

    private func makeTokenAccountSwitchActionItem(display: TokenAccountMenuDisplay) -> NSMenuItem? {
        guard display.selectedIndex != display.activeIndex else { return nil }
        let selected = display.accounts[display.selectedIndex]
        let item = NSMenuItem(
            title: "Switch to \(selected.displayName)",
            action: #selector(self.switchPreviewedTokenAccount(_:)),
            keyEquivalent: "")
        item.target = self
        item.representedObject = TokenAccountSwitchActionPayload(
            provider: display.provider,
            accountIndex: display.selectedIndex)
        item.isEnabled = !self.tokenAccountSwitchInFlight.contains(display.provider)
        return item
    }

    private func selectTokenAccountPreview(
        display: TokenAccountMenuDisplay,
        index: Int,
        menu: NSMenu)
    {
        let clamped = max(0, min(index, max(0, display.accounts.count - 1)))
        let selectedAccount = display.accounts[clamped]
        self.tokenAccountPreviewSelection[display.provider] = selectedAccount.id
        self.tokenAccountSwitchErrors.removeValue(forKey: display.provider)
        self.tokenAccountPreviewTasks[display.provider]?.cancel()
        self.tokenAccountPreviewTasks[display.provider] = nil
        self.tokenAccountPreviewInFlight.remove(display.provider)

        if clamped == display.activeIndex {
            self.tokenAccountSwitchSnapshotOverrides.removeValue(forKey: display.provider)
            self.populateMenu(menu, provider: display.provider)
            self.markMenuFresh(menu)
            self.applyIcon(phase: nil)
            return
        }

        if let cached = self.store.cachedTokenAccountSnapshot(
            for: display.provider,
            accountID: selectedAccount.id)
        {
            self.tokenAccountSwitchSnapshotOverrides[display.provider] = cached
            self.populateMenu(menu, provider: display.provider)
            self.markMenuFresh(menu)
            self.applyIcon(phase: nil)
            return
        }

        self.tokenAccountSwitchSnapshotOverrides.removeValue(forKey: display.provider)
        let generation = (self.tokenAccountPreviewGenerations[display.provider] ?? 0) + 1
        self.tokenAccountPreviewGenerations[display.provider] = generation
        self.tokenAccountPreviewInFlight.insert(display.provider)
        self.populateMenu(menu, provider: display.provider)
        self.markMenuFresh(menu)
        self.applyIcon(phase: nil)

        self.tokenAccountPreviewTasks[display.provider] = Task { @MainActor [weak self, weak menu] in
            guard let self else { return }
            let preview = await ProviderInteractionContext.$current.withValue(.userInitiated) {
                await self.store.fetchTokenAccountPreviewSnapshot(
                    provider: display.provider,
                    account: selectedAccount)
            }
            guard !Task.isCancelled else { return }
            guard self.tokenAccountPreviewGenerations[display.provider] == generation else { return }
            guard self.tokenAccountPreviewSelection[display.provider] == selectedAccount.id else { return }

            self.tokenAccountPreviewInFlight.remove(display.provider)
            self.tokenAccountPreviewTasks[display.provider] = nil

            if let snapshot = preview.snapshot {
                self.tokenAccountSwitchSnapshotOverrides[display.provider] = snapshot
                self.tokenAccountSwitchErrors.removeValue(forKey: display.provider)
            } else {
                self.tokenAccountSwitchSnapshotOverrides.removeValue(forKey: display.provider)
                self.tokenAccountSwitchErrors[display.provider] =
                    preview.error ?? "Unable to load account usage."
            }

            if let menu {
                self.populateMenu(menu, provider: display.provider)
                self.markMenuFresh(menu)
            }
            self.applyIcon(phase: nil)
        }
    }

    private func switchTokenAccount(provider: UsageProvider, index: Int, menu: NSMenu) {
        let accounts = self.settings.tokenAccounts(for: provider)
        guard !accounts.isEmpty else { return }
        let clamped = max(0, min(index, max(0, accounts.count - 1)))
        let selectedAccount = accounts[clamped]
        self.tokenAccountPreviewSelection[provider] = selectedAccount.id
        self.tokenAccountSwitchErrors.removeValue(forKey: provider)
        self.tokenAccountPreviewTasks[provider]?.cancel()
        self.tokenAccountPreviewTasks[provider] = nil
        self.tokenAccountPreviewInFlight.remove(provider)

        if provider == .codex,
           case .codexOAuth = TokenAccountSupportCatalog.support(for: .codex)?.injection
        {
            do {
                try CodexAccountSwitcher.switchToAccount(index: clamped, settings: self.settings)
            } catch {
                self.tokenAccountSwitchErrors[provider] = error.localizedDescription
                self.tokenAccountSwitchInFlight.remove(provider)
                self.tokenAccountSwitchSnapshotOverrides.removeValue(forKey: provider)
                self.loginLogger.error(
                    "Token account switch failed",
                    metadata: [
                        "provider": provider.rawValue,
                        "error": error.localizedDescription,
                    ])
                self.populateMenu(menu, provider: provider)
                self.markMenuFresh(menu)
                self.applyIcon(phase: nil)
                return
            }
        } else {
            self.settings.setActiveTokenAccountIndex(clamped, for: provider)
        }

        if let cached = self.store.cachedTokenAccountSnapshot(
            for: provider,
            accountID: selectedAccount.id)
        {
            self.tokenAccountSwitchSnapshotOverrides[provider] = cached
        } else {
            self.tokenAccountSwitchSnapshotOverrides.removeValue(forKey: provider)
        }

        let generation = (self.tokenAccountSwitchGenerations[provider] ?? 0) + 1
        self.tokenAccountSwitchGenerations[provider] = generation
        self.tokenAccountSwitchInFlight.insert(provider)
        self.tokenAccountSwitchTasks[provider]?.cancel()

        self.populateMenu(menu, provider: provider)
        self.markMenuFresh(menu)
        self.applyIcon(phase: nil)

        self.tokenAccountSwitchTasks[provider] = Task { @MainActor [weak self, weak menu] in
            guard let self else { return }
            await ProviderInteractionContext.$current.withValue(.userInitiated) {
                await self.store.refreshProvider(provider, allowDisabled: true)
            }
            guard !Task.isCancelled else { return }
            guard self.tokenAccountSwitchGenerations[provider] == generation else { return }

            self.tokenAccountSwitchInFlight.remove(provider)
            self.tokenAccountSwitchSnapshotOverrides.removeValue(forKey: provider)
            self.tokenAccountSwitchErrors.removeValue(forKey: provider)
            self.tokenAccountSwitchTasks[provider] = nil

            if let menu {
                self.populateMenu(menu, provider: provider)
                self.markMenuFresh(menu)
            }
            self.applyIcon(phase: nil)
        }
    }

    @objc private func switchPreviewedTokenAccount(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? TokenAccountSwitchActionPayload,
              let menu = sender.menu
        else { return }
        self.switchTokenAccount(provider: payload.provider, index: payload.accountIndex, menu: menu)
    }

    func tokenAccountMenuDisplay(for provider: UsageProvider) -> TokenAccountMenuDisplay? {
        guard TokenAccountSupportCatalog.support(for: provider) != nil else { return nil }
        let accounts = self.settings.tokenAccounts(for: provider)
        guard accounts.count > 1 else { return nil }
        let configuredIndex = self.settings.tokenAccountsData(for: provider)?.clampedActiveIndex() ?? 0
        let activeIndex = min(max(configuredIndex, 0), accounts.count - 1)
        let selectedIndex = Self.resolvedTokenAccountSelectedIndex(
            accounts: accounts,
            activeIndex: activeIndex,
            previewSelectionID: self.tokenAccountPreviewSelection[provider])
        let activeAccountID = accounts[activeIndex].id
        let sessionBadgeTexts = accounts.map { account in
            let snapshot = self.tokenAccountSnapshotForDisplay(
                provider: provider,
                accountID: account.id,
                activeAccountID: activeAccountID)
            return Self.tokenAccountSessionBadgeText(for: provider, snapshot: snapshot)
        }
        let showAll = self.settings.showAllTokenAccountsInMenu
        let snapshots = showAll ? (self.store.accountSnapshots[provider] ?? []) : []
        return TokenAccountMenuDisplay(
            provider: provider,
            accounts: accounts,
            snapshots: snapshots,
            activeIndex: activeIndex,
            selectedIndex: selectedIndex,
            sessionBadgeTexts: sessionBadgeTexts,
            showAll: showAll,
            showSwitcher: !showAll)
    }

    private func tokenAccountSnapshotForDisplay(
        provider: UsageProvider,
        accountID: UUID,
        activeAccountID: UUID) -> UsageSnapshot?
    {
        if self.tokenAccountPreviewSelection[provider] == accountID,
           let override = self.tokenAccountSwitchSnapshotOverrides[provider]
        {
            return override
        }
        if let cached = self.store.cachedTokenAccountSnapshot(for: provider, accountID: accountID) {
            return cached
        }
        if accountID == activeAccountID {
            return self.store.snapshot(for: provider)
        }
        return nil
    }
}
