import AppKit
import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@Suite(.serialized)
struct StatusItemControllerMenuTests {
    private func makeStatusBarForTesting() -> NSStatusBar {
        let env = ProcessInfo.processInfo.environment
        if env["GITHUB_ACTIONS"] == "true" || env["CI"] == "true" {
            return .system
        }
        return NSStatusBar()
    }

    @MainActor
    private func makeController(suite: String = "StatusItemControllerMenuTests-\(UUID().uuidString)")
    -> StatusItemController {
        let settings = SettingsStore(
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual

        let fetcher = UsageFetcher()
        let store = UsageStore(
            fetcher: fetcher,
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)

        return StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
    }

    @MainActor
    private func waitForCodexRefreshCompletion(controller: StatusItemController) async {
        for _ in 0..<100 {
            if controller.codexDependentProcessesTask == nil {
                return
            }
            await Task.yield()
        }
    }

    @MainActor
    private func waitForCodexDataRefreshCompletion(controller: StatusItemController) async {
        for _ in 0..<200 {
            if controller.codexDependentDataRefreshTask == nil {
                return
            }
            await Task.yield()
        }
    }

    private func makeSnapshot(primary: RateWindow?, secondary: RateWindow?) -> UsageSnapshot {
        UsageSnapshot(primary: primary, secondary: secondary, updatedAt: Date())
    }

    @Test
    func cursorSwitcherFallsBackToSecondaryWhenPlanExhaustedAndShowingRemaining() {
        let primary = RateWindow(usedPercent: 100, windowMinutes: nil, resetsAt: nil, resetDescription: nil)
        let secondary = RateWindow(usedPercent: 36, windowMinutes: nil, resetsAt: nil, resetDescription: nil)
        let snapshot = self.makeSnapshot(primary: primary, secondary: secondary)

        let percent = StatusItemController.switcherWeeklyMetricPercent(
            for: .cursor,
            snapshot: snapshot,
            showUsed: false)

        #expect(percent == 64)
    }

    @Test
    func cursorSwitcherUsesPrimaryWhenShowingUsed() {
        let primary = RateWindow(usedPercent: 100, windowMinutes: nil, resetsAt: nil, resetDescription: nil)
        let secondary = RateWindow(usedPercent: 36, windowMinutes: nil, resetsAt: nil, resetDescription: nil)
        let snapshot = self.makeSnapshot(primary: primary, secondary: secondary)

        let percent = StatusItemController.switcherWeeklyMetricPercent(
            for: .cursor,
            snapshot: snapshot,
            showUsed: true)

        #expect(percent == 100)
    }

    @Test
    func cursorSwitcherKeepsPrimaryWhenRemainingIsPositive() {
        let primary = RateWindow(usedPercent: 20, windowMinutes: nil, resetsAt: nil, resetDescription: nil)
        let secondary = RateWindow(usedPercent: 40, windowMinutes: nil, resetsAt: nil, resetDescription: nil)
        let snapshot = self.makeSnapshot(primary: primary, secondary: secondary)

        let percent = StatusItemController.switcherWeeklyMetricPercent(
            for: .cursor,
            snapshot: snapshot,
            showUsed: false)

        #expect(percent == 80)
    }

    @Test
    func openRouterBrandFallbackEnabledWhenNoKeyLimitConfigured() {
        let snapshot = OpenRouterUsageSnapshot(
            totalCredits: 50,
            totalUsage: 45,
            balance: 5,
            usedPercent: 90,
            keyDataFetched: true,
            keyLimit: nil,
            keyUsage: nil,
            rateLimit: nil,
            updatedAt: Date()).toUsageSnapshot()

        #expect(StatusItemController.shouldUseOpenRouterBrandFallback(
            provider: .openrouter,
            snapshot: snapshot))
        #expect(MenuBarDisplayText.percentText(window: snapshot.primary, showUsed: false) == nil)
    }

    @Test
    func openRouterBrandFallbackDisabledWhenKeyQuotaFetchUnavailable() {
        let snapshot = OpenRouterUsageSnapshot(
            totalCredits: 50,
            totalUsage: 45,
            balance: 5,
            usedPercent: 90,
            keyDataFetched: false,
            keyLimit: nil,
            keyUsage: nil,
            rateLimit: nil,
            updatedAt: Date()).toUsageSnapshot()

        #expect(!StatusItemController.shouldUseOpenRouterBrandFallback(
            provider: .openrouter,
            snapshot: snapshot))
    }

    @Test
    func openRouterBrandFallbackDisabledWhenKeyQuotaAvailable() {
        let snapshot = OpenRouterUsageSnapshot(
            totalCredits: 50,
            totalUsage: 45,
            balance: 5,
            usedPercent: 90,
            keyLimit: 20,
            keyUsage: 2,
            rateLimit: nil,
            updatedAt: Date()).toUsageSnapshot()

        #expect(!StatusItemController.shouldUseOpenRouterBrandFallback(
            provider: .openrouter,
            snapshot: snapshot))
        #expect(snapshot.primary?.usedPercent == 10)
    }

    @Test
    func tokenAccountSelectedIndexPrefersPreviewSelectionWhenPresent() {
        let first = ProviderTokenAccount(
            id: UUID(),
            label: "first",
            token: "a",
            addedAt: 0,
            lastUsed: nil)
        let second = ProviderTokenAccount(
            id: UUID(),
            label: "second",
            token: "b",
            addedAt: 0,
            lastUsed: nil)

        let selected = StatusItemController.resolvedTokenAccountSelectedIndex(
            accounts: [first, second],
            activeIndex: 0,
            previewSelectionID: second.id)

        #expect(selected == 1)
    }

    @Test
    func tokenAccountSelectedIndexFallsBackToActiveWhenPreviewMissing() {
        let first = ProviderTokenAccount(
            id: UUID(),
            label: "first",
            token: "a",
            addedAt: 0,
            lastUsed: nil)
        let second = ProviderTokenAccount(
            id: UUID(),
            label: "second",
            token: "b",
            addedAt: 0,
            lastUsed: nil)

        let selected = StatusItemController.resolvedTokenAccountSelectedIndex(
            accounts: [first, second],
            activeIndex: 1,
            previewSelectionID: UUID())

        #expect(selected == 1)
    }

    @Test
    func tokenAccountSessionBadgeShownWhenWeeklyRemainingIsPositive() {
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 58, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 20, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            tertiary: nil,
            updatedAt: Date())

        let badge = StatusItemController.tokenAccountSessionBadgeText(for: .codex, snapshot: snapshot)
        #expect(badge == "42%")
    }

    @Test
    func tokenAccountSessionBadgeHiddenWhenWeeklyRemainingIsDepleted() {
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 10, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 100, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            tertiary: nil,
            updatedAt: Date())

        let badge = StatusItemController.tokenAccountSessionBadgeText(for: .codex, snapshot: snapshot)
        #expect(badge == "0%")
    }

    @Test
    func tokenAccountSessionBadgeHiddenWhenWeeklyWindowMissing() {
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 10, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            updatedAt: Date())

        let badge = StatusItemController.tokenAccountSessionBadgeText(for: .codex, snapshot: snapshot)
        #expect(badge == nil)
    }

    @Test
    func codexDependentRefreshStatusTextMatchesCombinedLoadingState() {
        #expect(
            StatusItemController.codexDependentRefreshStatusText(
                processesLoading: false,
                dataLoading: false) == nil)
        #expect(
            StatusItemController.codexDependentRefreshStatusText(
                processesLoading: true,
                dataLoading: false) == "Refreshing dependent processes…")
        #expect(
            StatusItemController.codexDependentRefreshStatusText(
                processesLoading: false,
                dataLoading: true) == "Refreshing usage data…")
        #expect(
            StatusItemController.codexDependentRefreshStatusText(
                processesLoading: true,
                dataLoading: true) == "Refreshing processes and usage data…")
    }

    @MainActor
    @Test
    func codexDependentProcessesPanelToggleFlipsExpandedState() {
        let controller = self.makeController()
        #expect(controller.codexDependentProcessesExpanded == false)

        controller.toggleCodexDependentProcessesExpanded()
        #expect(controller.codexDependentProcessesExpanded == true)

        controller.toggleCodexDependentProcessesExpanded()
        #expect(controller.codexDependentProcessesExpanded == false)
    }

    @MainActor
    @Test
    func codexSwitchSuccessTriggersDependentProcessRefresh() async {
        let controller = self.makeController()
        let expectedSnapshot = CodexDependentProcessSnapshot(
            capturedAt: Date(timeIntervalSince1970: 1_709_541_000),
            processes: [])

        let originalProvider = StatusItemController.codexDependentProcessSnapshotProvider
        StatusItemController.codexDependentProcessSnapshotProvider = { _ in
            expectedSnapshot
        }
        defer {
            StatusItemController.codexDependentProcessSnapshotProvider = originalProvider
        }

        controller.handleTokenAccountSwitchDidSucceed(provider: .codex, menu: nil)
        await self.waitForCodexRefreshCompletion(controller: controller)

        #expect(controller.codexDependentProcessesLoading == false)
        #expect(controller.codexDependentProcessesSnapshot == expectedSnapshot)
    }

    @MainActor
    @Test
    func codexManualPanelRefreshStartsDependentProcessAndDataRefresh() async {
        let controller = self.makeController()
        let expectedSnapshot = CodexDependentProcessSnapshot(
            capturedAt: Date(timeIntervalSince1970: 1_709_541_111),
            processes: [])

        let originalProvider = StatusItemController.codexDependentProcessSnapshotProvider
        StatusItemController.codexDependentProcessSnapshotProvider = { _ in
            expectedSnapshot
        }
        defer {
            StatusItemController.codexDependentProcessSnapshotProvider = originalProvider
        }

        controller.refreshCodexDependentProcessesAndUsage(menu: nil)

        #expect(controller.codexDependentProcessesLoading)
        #expect(controller.codexDependentDataRefreshInFlight)
        #expect(controller.codexDependentDataRefreshTask != nil)

        await self.waitForCodexRefreshCompletion(controller: controller)
        await self.waitForCodexDataRefreshCompletion(controller: controller)
        #expect(controller.codexDependentDataRefreshInFlight == false)
    }

    @MainActor
    @Test
    func codexMenuOpenRefreshUsesLastMenuProviderWhenProviderIsNil() async {
        let controller = self.makeController()
        let expectedSnapshot = CodexDependentProcessSnapshot(
            capturedAt: Date(timeIntervalSince1970: 1_709_542_000),
            processes: [])

        let originalProvider = StatusItemController.codexDependentProcessSnapshotProvider
        StatusItemController.codexDependentProcessSnapshotProvider = { _ in
            expectedSnapshot
        }
        defer {
            StatusItemController.codexDependentProcessSnapshotProvider = originalProvider
        }

        controller.codexDependentProcessesSnapshot = nil
        controller.lastMenuProvider = .codex
        controller.refreshCodexDependentProcessesOnMenuOpenIfNeeded(provider: nil)
        await self.waitForCodexRefreshCompletion(controller: controller)

        #expect(controller.codexDependentProcessesSnapshot == expectedSnapshot)
        #expect(controller.codexDependentProcessesLoading == false)
    }

    @Test
    func codexDependentProcessAuthRiskLabelUsesLastSwitchTime() {
        let process = CodexDependentProcessSnapshot.Process(
            process: "Codex",
            pid: 42,
            source: .codexApp,
            startedAt: Date(timeIntervalSince1970: 1_709_541_000),
            command: "/Applications/Codex.app/Codex")
        let switchAfterStart = Date(timeIntervalSince1970: 1_709_541_600)
        let switchBeforeStart = Date(timeIntervalSince1970: 1_709_540_900)

        #expect(
            StatusItemController.codexDependentProcessAuthRiskLabel(
                for: process,
                lastSwitchAt: switchAfterStart) == "May hold old token")
        #expect(
            StatusItemController.codexDependentProcessAuthRiskLabel(
                for: process,
                lastSwitchAt: switchBeforeStart) == "Current token likely in use")
    }

    @Test
    func codexSwitchWarningShownOnlyForInactiveSelectionWithStaleProcess() {
        let staleProcess = CodexDependentProcessSnapshot.Process(
            process: "codex",
            pid: 44,
            source: .terminalOther,
            startedAt: Date(timeIntervalSince1970: 1_709_541_000),
            command: "codex app-server")
        let freshProcess = CodexDependentProcessSnapshot.Process(
            process: "codex",
            pid: 45,
            source: .terminalOther,
            startedAt: Date(timeIntervalSince1970: 1_709_541_700),
            command: "codex app-server")
        let staleSnapshot = CodexDependentProcessSnapshot(
            capturedAt: Date(timeIntervalSince1970: 1_709_542_000),
            processes: [staleProcess])
        let freshSnapshot = CodexDependentProcessSnapshot(
            capturedAt: Date(timeIntervalSince1970: 1_709_542_000),
            processes: [freshProcess])
        let lastSwitchAt = Date(timeIntervalSince1970: 1_709_541_600)

        #expect(
            StatusItemController.shouldShowCodexSwitchWarning(
                selectedIndex: 1,
                activeIndex: 0,
                snapshot: staleSnapshot,
                lastSwitchAt: lastSwitchAt))
        #expect(
            !StatusItemController.shouldShowCodexSwitchWarning(
                selectedIndex: 0,
                activeIndex: 0,
                snapshot: staleSnapshot,
                lastSwitchAt: lastSwitchAt))
        #expect(
            !StatusItemController.shouldShowCodexSwitchWarning(
                selectedIndex: 1,
                activeIndex: 0,
                snapshot: freshSnapshot,
                lastSwitchAt: lastSwitchAt))
        #expect(
            !StatusItemController.shouldShowCodexSwitchWarning(
                selectedIndex: 1,
                activeIndex: 0,
                snapshot: nil,
                lastSwitchAt: lastSwitchAt))
    }

    @Test
    func codexDependentProcessStopGuardsRejectCodexBarProcess() {
        let codexBarProcess = CodexDependentProcessSnapshot.Process(
            process: "CodexBar",
            pid: 123,
            source: .terminalOther,
            startedAt: Date(),
            command: "/Applications/CodexBar.app/Contents/MacOS/CodexBar")
        let codexAppProcess = CodexDependentProcessSnapshot.Process(
            process: "codex",
            pid: 456,
            source: .codexApp,
            startedAt: Date(),
            command: "/Applications/Codex.app/Contents/Resources/codex app-server")

        #expect(!StatusItemController.canStopCodexDependentProcess(codexBarProcess))
        #expect(StatusItemController.canStopCodexDependentProcess(codexAppProcess))
    }

    @Test
    func previewingInactiveAccountSuppressesActiveSnapshotFallback() {
        let active = UUID()
        let preview = UUID()

        #expect(
            StatusItemController.shouldSuppressActiveSnapshotFallback(
                previewSelectionID: preview,
                activeAccountID: active))
        #expect(
            !StatusItemController.shouldSuppressActiveSnapshotFallback(
                previewSelectionID: active,
                activeAccountID: active))
        #expect(
            !StatusItemController.shouldSuppressActiveSnapshotFallback(
                previewSelectionID: nil,
                activeAccountID: active))
    }

    @MainActor
    @Test
    func codexPreviewOverrideForcesOAuthSourceMode() {
        let controller = self.makeController()
        controller.settings.updateProviderConfig(provider: .codex) { config in
            config.source = .cli
        }

        let override = TokenAccountOverride(
            provider: .codex,
            account: ProviderTokenAccount(
                id: UUID(),
                label: "preview",
                token: #"{"tokens":{"access_token":"a","refresh_token":"r"}}"#,
                addedAt: 1,
                lastUsed: nil))

        #expect(controller.store.sourceMode(for: .codex, override: override) == .oauth)
        #expect(controller.store.sourceMode(for: .codex, override: nil) == .cli)
    }
}
