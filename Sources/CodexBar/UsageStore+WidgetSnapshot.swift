import CodexBarCore
import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

extension UsageStore {
    func persistWidgetSnapshot(reason: String) {
        let snapshot = self.makeWidgetSnapshot()
        let previousTask = self.widgetSnapshotPersistTask
        self.widgetSnapshotPersistTask = Task { @MainActor in
            _ = await previousTask?.result

            if let override = self._test_widgetSnapshotSaveOverride {
                await override(snapshot)
                return
            }

            await Task.detached(priority: .utility) {
                WidgetSnapshotStore.save(snapshot)
            }.value
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        }
    }

    private func makeWidgetSnapshot() -> WidgetSnapshot {
        let enabledProviders = self.enabledProviders()
        let entries = UsageProvider.allCases.flatMap { provider in
            self.makeWidgetEntries(for: provider)
        }
        return WidgetSnapshot(entries: entries, enabledProviders: enabledProviders, generatedAt: Date())
    }

    private func makeWidgetEntries(for provider: UsageProvider) -> [WidgetSnapshot.ProviderEntry] {
        if provider == .opencode {
            let workspaceAccounts = self.settings.openCodeWorkspaceAccounts
            guard !workspaceAccounts.isEmpty else {
                guard let entry = self.makeWidgetEntry(for: provider, snapshot: self.snapshots[provider]) else {
                    return []
                }
                return [entry]
            }

            let cachedSnapshots = self.tokenAccountSnapshotCache[provider] ?? [:]
            return workspaceAccounts.compactMap { account in
                let snapshot = if account.id == self.settings.selectedOpenCodeWorkspaceAccount?.id {
                    self.snapshots[provider] ?? cachedSnapshots[account.id]
                } else {
                    cachedSnapshots[account.id]
                }
                return self.makeWidgetEntry(
                    for: provider,
                    snapshot: snapshot,
                    accountID: account.id,
                    accountLabel: account.workspaceLabel)
            }
        }

        guard let entry = self.makeWidgetEntry(for: provider, snapshot: self.snapshots[provider]) else { return [] }
        return [entry]
    }

    private func makeWidgetEntry(
        for provider: UsageProvider,
        snapshot: UsageSnapshot?,
        accountID: UUID? = nil,
        accountLabel: String? = nil) -> WidgetSnapshot.ProviderEntry?
    {
        guard let snapshot else { return nil }

        let tokenSnapshot = self.tokenSnapshots[provider]
        let dailyUsage = tokenSnapshot?.daily.map { entry in
            WidgetSnapshot.DailyUsagePoint(
                dayKey: entry.date,
                totalTokens: entry.totalTokens,
                costUSD: entry.costUSD)
        } ?? []

        let tokenUsage = Self.widgetTokenUsageSummary(
            provider: provider,
            usageSnapshot: snapshot,
            tokenSnapshot: tokenSnapshot)
        let usageRows = self.widgetUsageRows(provider: provider, snapshot: snapshot)

        let creditsRemaining: Double?
        let codeReviewRemaining: Double?
        if provider == .codex {
            let projection = self.codexConsumerProjection(
                surface: .widget,
                snapshotOverride: snapshot,
                now: snapshot.updatedAt)
            let displayOnlyExtrasHidden = projection.dashboardVisibility == .displayOnly
            creditsRemaining = displayOnlyExtrasHidden ? nil : projection.credits?.remaining
            codeReviewRemaining = displayOnlyExtrasHidden ? nil : projection.remainingPercent(for: .codeReview)
        } else {
            creditsRemaining = nil
            codeReviewRemaining = nil
        }

        let cursorRequestDetails = Self.widgetCursorRequestDetails(provider: provider, snapshot: snapshot)
        let cursorRequestRange = Self.widgetCursorRequestRange(provider: provider, snapshot: snapshot)

        return WidgetSnapshot.ProviderEntry(
            provider: provider,
            accountID: accountID,
            accountLabel: accountLabel,
            updatedAt: snapshot.updatedAt,
            primary: snapshot.primary,
            secondary: snapshot.secondary,
            tertiary: snapshot.tertiary,
            usageRows: usageRows,
            creditsRemaining: creditsRemaining,
            codeReviewRemainingPercent: codeReviewRemaining,
            providerCost: Self.widgetProviderCostSummary(from: snapshot.providerCost),
            tokenUsage: tokenUsage,
            cursorRequestRange: cursorRequestRange,
            cursorRequestDetails: cursorRequestDetails,
            dailyUsage: dailyUsage)
    }

    private nonisolated static func widgetCursorRequestRange(
        provider: UsageProvider,
        snapshot: UsageSnapshot) -> WidgetSnapshot.CursorRequestRange?
    {
        guard provider == .cursor,
              let range = snapshot.cursorRecentRequestRange
        else {
            return nil
        }
        return WidgetSnapshot.CursorRequestRange(start: range.start, end: range.end)
    }

    private nonisolated static func widgetCursorRequestDetails(
        provider: UsageProvider,
        snapshot: UsageSnapshot) -> [WidgetSnapshot.CursorRequestDetail]?
    {
        guard provider == .cursor,
              let recent = snapshot.cursorRecentRequests,
              !recent.isEmpty
        else {
            return nil
        }

        return recent
            .filter { row in
                let model = row.model.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !model.isEmpty else { return false }
                // Legacy request-plan rows must survive even with zero tokens, as long as they
                // represent at least one request. Only drop rows that carry neither tokens nor requests.
                return row.tokens > 0 || row.requests > 0
            }
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(30)
            .map { row in
                let normalized = CursorModelNormalizer.normalize(row.model)
                let estimate = CursorRequestCostEstimator.estimate(for: row)
                return WidgetSnapshot.CursorRequestDetail(
                    timestamp: row.timestamp,
                    model: row.model,
                    tokens: row.tokens,
                    requests: row.requests,
                    compactModel: UsageFormatter.cursorCompactModelLabel(normalized),
                    estimateText: UsageFormatter.cursorEstimateText(estimate))
            }
    }

    private nonisolated static func widgetProviderCostSummary(
        from cost: ProviderCostSnapshot?) -> WidgetSnapshot.ProviderCostSummary?
    {
        guard let cost, cost.limit > 0 else { return nil }
        return WidgetSnapshot.ProviderCostSummary(
            used: cost.used,
            limit: cost.limit,
            currencyCode: cost.currencyCode,
            period: cost.period,
            resetsAt: cost.resetsAt)
    }

    private nonisolated static func widgetTokenUsageSummary(
        provider: UsageProvider,
        usageSnapshot: UsageSnapshot,
        tokenSnapshot: CostUsageTokenSnapshot?) -> WidgetSnapshot.TokenUsageSummary?
    {
        if provider == .cursor,
           let cursorTokenUsage = usageSnapshot.cursorTokenUsage
        {
            return WidgetSnapshot.TokenUsageSummary(
                sessionCostUSD: nil,
                sessionTokens: cursorTokenUsage.billingCycleTokensUsed,
                last30DaysCostUSD: nil,
                last30DaysTokens: nil,
                sessionLabel: "Cycle",
                last30DaysLabel: nil)
        }

        guard let snapshot = tokenSnapshot else { return nil }
        let fallbackTokens = snapshot.daily.compactMap(\.totalTokens).reduce(0, +)
        let monthTokensValue = snapshot.last30DaysTokens ?? (fallbackTokens > 0 ? fallbackTokens : nil)
        return WidgetSnapshot.TokenUsageSummary(
            sessionCostUSD: snapshot.sessionCostUSD,
            sessionTokens: snapshot.sessionTokens,
            last30DaysCostUSD: snapshot.last30DaysCostUSD,
            last30DaysTokens: monthTokensValue)
    }

    private func widgetUsageRows(
        provider: UsageProvider,
        snapshot: UsageSnapshot) -> [WidgetSnapshot.WidgetUsageRowSnapshot]
    {
        let metadata = ProviderDefaults.metadata[provider]
        if provider == .codex {
            let projection = self.codexConsumerProjection(
                surface: .widget,
                snapshotOverride: snapshot,
                now: snapshot.updatedAt)
            return projection.visibleRateLanes.compactMap { lane in
                guard let window = projection.rateWindow(for: lane) else { return nil }
                let title = switch lane {
                case .session:
                    metadata?.sessionLabel ?? "Session"
                case .weekly:
                    metadata?.weeklyLabel ?? "Weekly"
                }
                return WidgetSnapshot.WidgetUsageRowSnapshot(
                    id: lane.rawValue,
                    title: title,
                    percentLeft: window.remainingPercent,
                    detailText: Self.widgetUsageRowDetail(window: window))
            }
        }

        if provider == .zai {
            let rows: [WidgetSnapshot.WidgetUsageRowSnapshot] = [
                WidgetSnapshot.WidgetUsageRowSnapshot(
                    id: "primary",
                    title: metadata?.sessionLabel ?? "Session",
                    percentLeft: snapshot.primary?.remainingPercent,
                    detailText: snapshot.primary.flatMap(Self.widgetUsageRowDetail)),
                WidgetSnapshot.WidgetUsageRowSnapshot(
                    id: "secondary",
                    title: metadata?.weeklyLabel ?? "Weekly",
                    percentLeft: snapshot.secondary?.remainingPercent,
                    detailText: snapshot.secondary.flatMap(Self.widgetUsageRowDetail)),
                WidgetSnapshot.WidgetUsageRowSnapshot(
                    id: "tertiary",
                    title: metadata?.opusLabel ?? "MCP",
                    percentLeft: snapshot.tertiary?.remainingPercent,
                    detailText: snapshot.tertiary.flatMap(Self.widgetUsageRowDetail)),
            ]
            return rows.filter { $0.percentLeft != nil }
        }

        let rows: [WidgetSnapshot.WidgetUsageRowSnapshot] = [
            WidgetSnapshot.WidgetUsageRowSnapshot(
                id: "primary",
                title: metadata?.sessionLabel ?? "Session",
                percentLeft: snapshot.primary?.remainingPercent,
                detailText: snapshot.primary.flatMap(Self.widgetUsageRowDetail)),
            WidgetSnapshot.WidgetUsageRowSnapshot(
                id: "secondary",
                title: metadata?.weeklyLabel ?? "Weekly",
                percentLeft: snapshot.secondary?.remainingPercent,
                detailText: snapshot.secondary.flatMap(Self.widgetUsageRowDetail)),
        ]
        return rows.filter { $0.percentLeft != nil }
    }

    private nonisolated static func widgetUsageRowDetail(window: RateWindow) -> String? {
        let detail = window.resetDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
        return detail?.isEmpty == false ? detail : nil
    }
}
