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
            selectedCursorRange: self.settings.cursorUsageRangeKind,
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

        let cursorRequestDetails = Self.widgetCursorRequestDetails(
            provider: provider,
            snapshot: snapshot,
            selectedCursorRange: self.settings.cursorUsageRangeKind)
        let cursorRequestRange = Self.widgetCursorRequestRange(
            provider: provider,
            snapshot: snapshot,
            selectedCursorRange: self.settings.cursorUsageRangeKind)

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
        snapshot: UsageSnapshot,
        selectedCursorRange: CursorUsageRangeKind) -> WidgetSnapshot.CursorRequestRange?
    {
        let selectedRange = self.selectedCursorRangeSummary(
            snapshot: snapshot,
            selectedCursorRange: selectedCursorRange)?
            .range
        let fallbackRange = if selectedCursorRange == .last30Days {
            self.cursorLast30DaysRange(now: snapshot.updatedAt)
        } else {
            snapshot.cursorRecentRequestRange
        }
        guard provider == .cursor,
              let range = selectedRange ?? fallbackRange
        else {
            return nil
        }
        return WidgetSnapshot.CursorRequestRange(start: range.start, end: range.end)
    }

    private nonisolated static func widgetCursorRequestDetails(
        provider: UsageProvider,
        snapshot: UsageSnapshot,
        selectedCursorRange: CursorUsageRangeKind) -> [WidgetSnapshot.CursorRequestDetail]?
    {
        let sourceRequests = self.selectedCursorRangeSummary(
            snapshot: snapshot,
            selectedCursorRange: selectedCursorRange)?
            .recentRequests ?? self.fallbackCursorRequests(
                snapshot: snapshot,
                selectedCursorRange: selectedCursorRange)
        guard provider == .cursor,
              let recent = sourceRequests,
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
                    requestCost: row.requestCost,
                    compactModel: UsageFormatter.cursorCompactModelLabel(normalized),
                    estimateText: UsageFormatter.cursorEstimateText(estimate))
            }
    }

    private nonisolated static func fallbackCursorRequests(
        snapshot: UsageSnapshot,
        selectedCursorRange: CursorUsageRangeKind) -> [CursorRecentRequest]?
    {
        guard let requests = snapshot.cursorRecentRequests else { return nil }
        guard selectedCursorRange == .last30Days else { return requests }
        let cutoff = snapshot.updatedAt.addingTimeInterval(-30 * 24 * 60 * 60)
        return requests.filter { $0.timestamp >= cutoff }
    }

    private nonisolated static func cursorLast30DaysRange(now: Date) -> CursorRecentRequestRange {
        CursorRecentRequestRange(
            start: now.addingTimeInterval(-30 * 24 * 60 * 60),
            end: now)
    }

    private nonisolated static func cursorRequestRange(
        for requests: [CursorRecentRequest]) -> CursorRecentRequestRange?
    {
        guard let first = requests.first else { return nil }
        let timestamps = requests.map(\.timestamp)
        return CursorRecentRequestRange(
            start: timestamps.min() ?? first.timestamp,
            end: timestamps.max() ?? first.timestamp)
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
        selectedCursorRange: CursorUsageRangeKind,
        tokenSnapshot: CostUsageTokenSnapshot?) -> WidgetSnapshot.TokenUsageSummary?
    {
        if provider == .cursor,
           let summary = self.selectedCursorRangeSummary(
               snapshot: usageSnapshot,
               selectedCursorRange: selectedCursorRange)
        {
            let estimatedCycleCost = summary.requestCostSummary?.exactUSD
                .map { NSDecimalNumber(decimal: $0).doubleValue }
            let sessionCostText = summary.requestCostSummary?.containsApproximation == true
                ? UsageFormatter.cursorEstimatedTotalText(summary.requestCostSummary)
                : nil
            return WidgetSnapshot.TokenUsageSummary(
                sessionCostUSD: estimatedCycleCost,
                sessionCostText: sessionCostText,
                sessionTokens: summary.tokens,
                last30DaysCostUSD: nil,
                last30DaysTokens: nil,
                sessionLabel: summary.rangeKind.label,
                last30DaysLabel: nil)
        }

        if provider == .cursor,
           selectedCursorRange == .last30Days
        {
            guard let requests = self.fallbackCursorRequests(
                snapshot: usageSnapshot,
                selectedCursorRange: selectedCursorRange)
            else {
                return WidgetSnapshot.TokenUsageSummary(
                    sessionCostUSD: nil,
                    sessionCostText: nil,
                    sessionTokens: nil,
                    last30DaysCostUSD: nil,
                    last30DaysTokens: nil,
                    sessionLabel: selectedCursorRange.label,
                    last30DaysLabel: nil)
            }
            let hasCompleteAggregate = requests.count < 30
            let tokens = hasCompleteAggregate ? requests.reduce(0) { $0 + $1.tokens } : 0
            let costSummary = hasCompleteAggregate ? CursorRequestCostEstimator.summarizedEstimate(for: requests) : nil
            let estimatedCost = costSummary?.exactUSD
                .map { NSDecimalNumber(decimal: $0).doubleValue }
            let sessionCostText = costSummary?.containsApproximation == true
                ? UsageFormatter.cursorEstimatedTotalText(costSummary)
                : nil
            return WidgetSnapshot.TokenUsageSummary(
                sessionCostUSD: estimatedCost,
                sessionCostText: sessionCostText,
                sessionTokens: tokens > 0 ? tokens : nil,
                last30DaysCostUSD: nil,
                last30DaysTokens: nil,
                sessionLabel: selectedCursorRange.label,
                last30DaysLabel: nil)
        }

        if provider == .cursor,
           let cursorTokenUsage = usageSnapshot.cursorTokenUsage
        {
            let recomputedCostSummary = usageSnapshot.cursorRecentRequests
                .flatMap(CursorRequestCostEstimator.summarizedEstimate(for:))
            let costSummary = self.cursorWidgetCostSummary(
                preferred: cursorTokenUsage.requestCostSummary,
                recomputed: recomputedCostSummary)
            let estimatedCycleCost = costSummary?.exactUSD
                .map { NSDecimalNumber(decimal: $0).doubleValue }
            let sessionCostText = costSummary?.containsApproximation == true
                ? UsageFormatter.cursorEstimatedTotalText(costSummary)
                : nil
            return WidgetSnapshot.TokenUsageSummary(
                sessionCostUSD: estimatedCycleCost,
                sessionCostText: sessionCostText,
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

    private nonisolated static func selectedCursorRangeSummary(
        snapshot: UsageSnapshot,
        selectedCursorRange: CursorUsageRangeKind) -> CursorRangeUsageSummary?
    {
        snapshot.cursorRangeSummaries?.first { $0.rangeKind == selectedCursorRange }
    }

    private nonisolated static func cursorWidgetCostSummary(
        preferred: CursorRequestCostSummary?,
        recomputed: CursorRequestCostSummary?) -> CursorRequestCostSummary?
    {
        recomputed ?? preferred
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
