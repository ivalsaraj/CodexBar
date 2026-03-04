import AppKit
import CodexBarCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import Foundation

extension StatusItemController {
    enum CodexDependentProcessesRefreshReason: String {
        case menuOpen
        case postSwitch
        case manual
    }

    private static let codexDependentProcessSnapshotMaxAge: TimeInterval = 20

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
        if let warningItem = self.makeTokenAccountSwitchWarningItem(display: display, menu: menu) {
            menu.addItem(warningItem)
        }
        if let switchItem = self.makeTokenAccountSwitchActionItem(display: display) {
            menu.addItem(switchItem)
        }
        if display.provider == .codex {
            let panelItem = self.makeCodexDependentProcessesPanelItem(menu: menu)
            menu.addItem(panelItem)
        }
        menu.addItem(.separator())
    }

    private func makeCodexDependentProcessesPanelItem(menu: NSMenu) -> NSMenuItem {
        let width = self.menuCardWidth(for: self.store.enabledProviders(), menu: menu)
        let panel = CodexDependentProcessesPanelView(
            snapshot: self.codexDependentProcessesSnapshot,
            expanded: self.codexDependentProcessesExpanded,
            loading: self.codexDependentProcessesLoading,
            lastSwitchAt: self.codexLastAccountSwitchAt,
            stoppingPIDs: self.codexDependentProcessStoppingPIDs,
            width: width,
            onToggle: { [weak self] in
                guard let self else { return }
                self.toggleCodexDependentProcessesExpanded()
            },
            onRefresh: { [weak self] in
                guard let self else { return }
                self.refreshCodexDependentProcesses(reason: .manual)
            },
            onStop: { [weak self] process in
                guard let self else { return }
                self.stopCodexDependentProcess(process)
            })
        let item = NSMenuItem()
        item.view = panel
        item.isEnabled = false
        item.representedObject = "codexDependentProcessesPanel"
        return item
    }

    private func makeTokenAccountSwitchWarningItem(
        display: TokenAccountMenuDisplay,
        menu: NSMenu) -> NSMenuItem?
    {
        guard display.provider == .codex else { return nil }
        guard Self.shouldShowCodexSwitchWarning(
            selectedIndex: display.selectedIndex,
            activeIndex: display.activeIndex,
            snapshot: self.codexDependentProcessesSnapshot,
            lastSwitchAt: self.codexLastAccountSwitchAt)
        else {
            return nil
        }

        let label = NSTextField(wrappingLabelWithString: Self.codexSwitchWarningText)
        label.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        label.textColor = NSColor.systemOrange
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
        ])

        let width = max(180, self.menuCardWidth(for: self.store.enabledProviders(), menu: menu) - 16)
        container.frame = NSRect(x: 0, y: 0, width: width, height: 1)
        container.layoutSubtreeIfNeeded()
        let measuredHeight = max(24, label.fittingSize.height + 8)
        container.frame = NSRect(x: 0, y: 0, width: width, height: measuredHeight)

        let item = NSMenuItem()
        item.view = container
        item.isEnabled = false
        return item
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
        let previousCodexLastSwitchAt = self.codexLastAccountSwitchAt
        if provider == .codex {
            self.codexLastAccountSwitchAt = Date()
        }
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
                if provider == .codex {
                    self.codexLastAccountSwitchAt = previousCodexLastSwitchAt
                }
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

            self.handleTokenAccountSwitchDidSucceed(provider: provider, menu: menu)
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

    private func stopCodexDependentProcess(_ process: CodexDependentProcessSnapshot.Process) {
        guard Self.canStopCodexDependentProcess(process) else { return }
        let pid = process.pid
        guard !self.codexDependentProcessStoppingPIDs.contains(pid) else { return }

        self.codexDependentProcessStopTasks[pid]?.cancel()
        self.codexDependentProcessStoppingPIDs.insert(pid)
        self.menuContentVersion &+= 1
        self.refreshOpenMenusIfNeeded()

        self.codexDependentProcessStopTasks[pid] = Task { [weak self] in
            let didStop = await Task.detached(priority: .utility) {
                Self.terminateCodexDependentProcess(pid: pid_t(pid))
            }.value
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.codexDependentProcessStoppingPIDs.remove(pid)
                self.codexDependentProcessStopTasks[pid] = nil
                if didStop {
                    self.refreshCodexDependentProcesses(reason: .manual)
                } else {
                    self.loginLogger.error(
                        "Failed to stop dependent process",
                        metadata: [
                            "provider": UsageProvider.codex.rawValue,
                            "pid": "\(pid)",
                        ])
                    self.menuContentVersion &+= 1
                    self.refreshOpenMenusIfNeeded()
                }
            }
        }
    }

    func refreshCodexDependentProcesses(reason: CodexDependentProcessesRefreshReason) {
        self.codexDependentProcessesTask?.cancel()
        self.codexDependentProcessesTask = nil
        self.codexDependentProcessesLoading = true
        self.menuContentVersion &+= 1
        self.refreshOpenMenusIfNeeded()

        self.codexDependentProcessesTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await Self.codexDependentProcessSnapshotProvider(Date())
                guard !Task.isCancelled else { return }
                self.codexDependentProcessesSnapshot = snapshot
                let activePIDs = Set(snapshot.processes.map(\.pid))
                self.codexDependentProcessStoppingPIDs.formIntersection(activePIDs)
                let staleTaskPIDs = self.codexDependentProcessStopTasks.keys.filter { !activePIDs.contains($0) }
                for pid in staleTaskPIDs {
                    self.codexDependentProcessStopTasks[pid]?.cancel()
                    self.codexDependentProcessStopTasks.removeValue(forKey: pid)
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.loginLogger.error(
                    "Dependent process refresh failed",
                    metadata: [
                        "provider": UsageProvider.codex.rawValue,
                        "reason": reason.rawValue,
                        "error": error.localizedDescription,
                    ])
            }
            guard !Task.isCancelled else { return }
            self.codexDependentProcessesLoading = false
            self.codexDependentProcessesTask = nil
            self.menuContentVersion &+= 1
            self.refreshOpenMenusIfNeeded()
        }
    }

    func toggleCodexDependentProcessesExpanded() {
        self.codexDependentProcessesExpanded.toggle()
        self.menuContentVersion &+= 1
        self.refreshOpenMenusIfNeeded()
    }

    func refreshCodexDependentProcessesOnMenuOpenIfNeeded(provider: UsageProvider?) {
        let resolvedProvider = provider ?? self.lastMenuProvider
        guard resolvedProvider == .codex else { return }
        guard !self.codexDependentProcessesLoading else { return }
        guard let snapshot = self.codexDependentProcessesSnapshot else {
            self.refreshCodexDependentProcesses(reason: .menuOpen)
            return
        }
        if let lastSwitchAt = self.codexLastAccountSwitchAt, snapshot.capturedAt < lastSwitchAt {
            self.refreshCodexDependentProcesses(reason: .menuOpen)
            return
        }
        if Date().timeIntervalSince(snapshot.capturedAt) >= Self.codexDependentProcessSnapshotMaxAge {
            self.refreshCodexDependentProcesses(reason: .menuOpen)
        }
    }

    func handleTokenAccountSwitchDidSucceed(provider: UsageProvider, menu: NSMenu?) {
        if provider == .codex {
            self.codexLastAccountSwitchAt = Date()
            self.refreshCodexDependentProcesses(reason: .postSwitch)
        }
        if let menu {
            self.populateMenu(menu, provider: provider)
            self.markMenuFresh(menu)
        }
        self.applyIcon(phase: nil)
    }

    nonisolated static func codexDependentProcessAuthRiskLabel(
        for process: CodexDependentProcessSnapshot.Process,
        lastSwitchAt: Date?) -> String
    {
        if process.isStaleRisk(relativeTo: lastSwitchAt) {
            return "May hold old token"
        }
        return "Current token likely in use"
    }

    nonisolated static func codexDependentProcessRestartHint(
        for source: CodexDependentProcessSnapshot.Process.Source) -> String
    {
        switch source {
        case .browserForce:
            "Restart BrowserForce MCP session"
        case .codexApp:
            "Restart Codex.app session"
        case .cursor:
            "Restart Cursor Codex session"
        case .terminalOther:
            "Restart this terminal Codex session"
        }
    }

    nonisolated static func shouldShowCodexSwitchWarning(
        selectedIndex: Int,
        activeIndex: Int,
        snapshot: CodexDependentProcessSnapshot?,
        lastSwitchAt: Date?) -> Bool
    {
        guard selectedIndex != activeIndex else { return false }
        guard let snapshot else { return false }
        return snapshot.processes.contains { $0.isStaleRisk(relativeTo: lastSwitchAt) }
    }

    nonisolated static func canStopCodexDependentProcess(_ process: CodexDependentProcessSnapshot.Process) -> Bool {
        guard process.pid > 1 else { return false }
        let lowerProcess = process.process.lowercased()
        let lowerCommand = process.command.lowercased()
        if lowerProcess.contains("codexbar") || lowerCommand.contains("codexbar") {
            return false
        }
        return true
    }

    nonisolated static var codexSwitchWarningText: String {
        "Heads up: Some Codex processes may still use old login. Stop them for a clean switch."
    }

    private nonisolated static func terminateCodexDependentProcess(pid: pid_t) -> Bool {
        guard pid > 1 else { return false }
        if !self.sendSignal(SIGTERM, to: pid) { return false }
        if self.waitForProcessExit(pid: pid, timeout: 2.0) { return true }
        if !self.sendSignal(SIGKILL, to: pid) { return false }
        return self.waitForProcessExit(pid: pid, timeout: 1.0)
    }

    private nonisolated static func sendSignal(_ signal: Int32, to pid: pid_t) -> Bool {
        if kill(pid, signal) == 0 { return true }
        return errno == ESRCH
    }

    private nonisolated static func waitForProcessExit(pid: pid_t, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !self.processExists(pid: pid) { return true }
            usleep(100_000)
        }
        return !self.processExists(pid: pid)
    }

    private nonisolated static func processExists(pid: pid_t) -> Bool {
        if kill(pid, 0) == 0 { return true }
        return errno != ESRCH
    }

    nonisolated static func shouldSuppressActiveSnapshotFallback(
        previewSelectionID: UUID?,
        activeAccountID: UUID?) -> Bool
    {
        guard let previewSelectionID, let activeAccountID else { return false }
        return previewSelectionID != activeAccountID
    }
}
