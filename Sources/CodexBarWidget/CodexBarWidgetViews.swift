import CodexBarCore
import SwiftUI
import WidgetKit

struct CodexBarUsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CodexBarWidgetEntry

    var body: some View {
        let providerEntry = self.entry.snapshot.entry(for: self.entry.provider, accountID: self.entry.accountID)
        ZStack {
            Color.black.opacity(0.02)
            if let providerEntry {
                self.content(providerEntry: providerEntry)
            } else {
                self.emptyState
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder
    private func content(providerEntry: WidgetSnapshot.ProviderEntry) -> some View {
        switch self.family {
        case .systemSmall:
            SmallUsageView(entry: providerEntry)
        case .systemMedium:
            MediumUsageView(entry: providerEntry)
        default:
            LargeUsageView(entry: providerEntry)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Open CodexBar")
                .font(.body)
                .fontWeight(.semibold)
            Text("Usage data will appear once the app refreshes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }
}

struct CodexBarHistoryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CodexBarWidgetEntry

    var body: some View {
        let providerEntry = self.entry.snapshot.entry(for: self.entry.provider, accountID: self.entry.accountID)
        ZStack {
            Color.black.opacity(0.02)
            if let providerEntry {
                HistoryView(entry: providerEntry, isLarge: self.family == .systemLarge)
            } else {
                self.emptyState
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Open CodexBar")
                .font(.body)
                .fontWeight(.semibold)
            Text("Usage history will appear after a refresh.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }
}

struct CodexBarCompactWidgetView: View {
    let entry: CodexBarCompactEntry

    var body: some View {
        let providerEntry = self.entry.snapshot.entry(for: self.entry.provider, accountID: self.entry.accountID)
        ZStack {
            Color.black.opacity(0.02)
            if let providerEntry {
                CompactMetricView(entry: providerEntry, metric: self.entry.metric)
            } else {
                self.emptyState
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Open CodexBar")
                .font(.body)
                .fontWeight(.semibold)
            Text("Usage data will appear once the app refreshes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }
}

struct CodexBarSwitcherWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CodexBarSwitcherEntry

    var body: some View {
        let providerEntry = self.entry.snapshot.entry(for: self.entry.provider, accountID: self.entry.accountID)
        let openCodeAccounts = self.entry.snapshot.entries(for: .opencode)
        ZStack {
            Color.black.opacity(0.02)
            VStack(alignment: .leading, spacing: 10) {
                ProviderSwitcherRow(
                    providers: self.entry.availableProviders,
                    selected: self.entry.provider,
                    updatedAt: providerEntry?.updatedAt ?? Date(),
                    compact: self.family == .systemSmall,
                    showsTimestamp: self.family != .systemSmall)
                if self.entry.provider == .opencode, openCodeAccounts.count > 1 {
                    OpenCodeWorkspaceSwitcherRow(
                        accounts: openCodeAccounts,
                        selectedAccountID: self.entry.accountID)
                }
                if let providerEntry {
                    self.content(providerEntry: providerEntry)
                } else {
                    self.emptyState
                }
            }
            .padding(12)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder
    private func content(providerEntry: WidgetSnapshot.ProviderEntry) -> some View {
        switch self.family {
        case .systemSmall:
            SwitcherSmallUsageView(entry: providerEntry)
        case .systemMedium:
            SwitcherMediumUsageView(entry: providerEntry)
        default:
            SwitcherLargeUsageView(entry: providerEntry)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Open CodexBar")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Usage data appears after a refresh.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct OpenCodeWorkspaceSwitcherRow: View {
    let accounts: [WidgetSnapshot.ProviderEntry]
    let selectedAccountID: UUID?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(self.accounts, id: \.accountID) { account in
                    if let accountID = account.accountID {
                        Button(intent: SwitchWidgetOpenCodeWorkspaceIntent(accountID: accountID)) {
                            Text(account.accountLabel ?? "Workspace")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(self.background(for: accountID))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func background(for accountID: UUID) -> some ShapeStyle {
        if accountID == self.selectedAccountID {
            return AnyShapeStyle(Color.primary.opacity(0.14))
        }
        return AnyShapeStyle(Color.primary.opacity(0.06))
    }
}

private struct CompactMetricView: View {
    let entry: WidgetSnapshot.ProviderEntry
    let metric: CompactMetric

    var body: some View {
        let display = self.display
        VStack(alignment: .leading, spacing: 8) {
            HeaderView(provider: self.entry.provider, updatedAt: self.entry.updatedAt)
            VStack(alignment: .leading, spacing: 2) {
                Text(display.value)
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(display.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let detail = display.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
    }

    private var display: (value: String, label: String, detail: String?) {
        switch self.metric {
        case .credits:
            let value = self.entry.creditsRemaining.map(WidgetFormat.credits) ?? "—"
            return (value, "Credits left", nil)
        case .todayCost:
            guard let tokenUsage = self.entry.tokenUsage else { return ("—", "Today cost", nil) }
            if let sessionCostText = tokenUsage.sessionCostText {
                let detail = tokenUsage.sessionTokens.map(WidgetFormat.tokenCount)
                return (sessionCostText, tokenUsage.primaryLabel, detail)
            }
            if let sessionCostUSD = tokenUsage.sessionCostUSD {
                let detail = tokenUsage.sessionTokens.map(WidgetFormat.tokenCount)
                return (WidgetFormat.usd(sessionCostUSD), tokenUsage.primaryLabel, detail)
            }
            return (
                WidgetFormat.costAndTokens(cost: nil, tokens: tokenUsage.sessionTokens),
                tokenUsage.primaryLabel,
                nil)
        case .last30DaysCost:
            guard let tokenUsage = self.entry.tokenUsage else { return ("—", "30d cost", nil) }
            if let last30DaysCostUSD = tokenUsage.last30DaysCostUSD {
                let detail = tokenUsage.last30DaysTokens.map(WidgetFormat.tokenCount)
                return (WidgetFormat.usd(last30DaysCostUSD), tokenUsage.secondaryLabel, detail)
            }
            return (
                WidgetFormat.costAndTokens(cost: nil, tokens: tokenUsage.last30DaysTokens),
                tokenUsage.secondaryLabel,
                nil)
        }
    }
}

private struct ProviderSwitcherRow: View {
    let providers: [UsageProvider]
    let selected: UsageProvider
    let updatedAt: Date
    let compact: Bool
    let showsTimestamp: Bool

    var body: some View {
        HStack(spacing: self.compact ? 4 : 6) {
            ForEach(self.providers, id: \.self) { provider in
                ProviderSwitchChip(
                    provider: provider,
                    selected: provider == self.selected,
                    compact: self.compact)
            }
            if self.showsTimestamp {
                Spacer(minLength: 6)
                Text(WidgetFormat.relativeDate(self.updatedAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ProviderSwitchChip: View {
    let provider: UsageProvider
    let selected: Bool
    let compact: Bool

    var body: some View {
        let label = self.compact ? self.shortLabel : self.longLabel
        let background = self.selected
            ? WidgetColors.color(for: self.provider).opacity(0.2)
            : Color.primary.opacity(0.08)

        if let choice = ProviderChoice(provider: self.provider) {
            Button(intent: SwitchWidgetProviderIntent(provider: choice)) {
                Text(label)
                    .font(self.compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                    .foregroundStyle(self.selected ? Color.primary : Color.secondary)
                    .padding(.horizontal, self.compact ? 6 : 8)
                    .padding(.vertical, self.compact ? 3 : 4)
                    .background(Capsule().fill(background))
            }
            .buttonStyle(.plain)
        } else {
            Text(label)
                .font(self.compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                .foregroundStyle(self.selected ? Color.primary : Color.secondary)
                .padding(.horizontal, self.compact ? 6 : 8)
                .padding(.vertical, self.compact ? 3 : 4)
                .background(Capsule().fill(background))
        }
    }

    private var longLabel: String {
        ProviderDefaults.metadata[self.provider]?.displayName ?? self.provider.rawValue.capitalized
    }

    private var shortLabel: String {
        switch self.provider {
        case .codex: "Codex"
        case .claude: "Claude"
        case .gemini: "Gemini"
        case .antigravity: "Anti"
        case .cursor: "Cursor"
        case .opencode: "OpenCode"
        case .opencodego: "OpenCode Go"
        case .alibaba: "Alibaba"
        case .zai: "z.ai"
        case .factory: "Droid"
        case .copilot: "Copilot"
        case .minimax: "MiniMax"
        case .vertexai: "Vertex"
        case .kilo: "Kilo"
        case .kiro: "Kiro"
        case .augment: "Augment"
        case .jetbrains: "JetBrains"
        case .kimi: "Kimi"
        case .kimik2: "Kimi K2"
        case .amp: "Amp"
        case .ollama: "Ollama"
        case .synthetic: "Synthetic"
        case .openrouter: "OpenRouter"
        case .warp: "Warp"
        case .perplexity: "Pplx"
        }
    }
}

private struct SwitcherSmallUsageView: View {
    let entry: WidgetSnapshot.ProviderEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(WidgetUsageRow.rows(for: self.entry)) { row in
                UsageBarRow(
                    title: row.title,
                    percentLeft: row.percentLeft,
                    detailText: row.detailText,
                    color: WidgetColors.color(for: self.entry.provider))
            }
            if let codeReview = entry.codeReviewRemainingPercent {
                UsageBarRow(
                    title: "Code review",
                    percentLeft: codeReview,
                    color: WidgetColors.color(for: self.entry.provider))
            }
        }
    }
}

private struct SwitcherMediumUsageView: View {
    let entry: WidgetSnapshot.ProviderEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(WidgetUsageRow.rows(for: self.entry)) { row in
                UsageBarRow(
                    title: row.title,
                    percentLeft: row.percentLeft,
                    detailText: row.detailText,
                    color: WidgetColors.color(for: self.entry.provider))
            }
            if let credits = entry.creditsRemaining {
                ValueLine(title: "Credits", value: WidgetFormat.credits(credits))
            }
            if let providerCost = entry.providerCost, !self.entry.showsCursorRequestDetails {
                ProviderCostLines(cost: providerCost)
            }
            if let token = entry.tokenUsage, token.hasPrimaryValue {
                ValueLine(
                    title: token.primaryLabel,
                    value: token.primaryCostAndTokensValue())
            }
            if let presentation = CursorWidgetRequestPresentation.selection(
                provider: self.entry.provider,
                details: self.entry.cursorRequestDetails,
                range: self.entry.cursorRequestRange,
                size: .medium)
            {
                CursorRequestDetailsView(presentation: presentation)
            }
        }
    }
}

private struct SwitcherLargeUsageView: View {
    let entry: WidgetSnapshot.ProviderEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(WidgetUsageRow.rows(for: self.entry)) { row in
                UsageBarRow(
                    title: row.title,
                    percentLeft: row.percentLeft,
                    detailText: row.detailText,
                    color: WidgetColors.color(for: self.entry.provider))
            }
            if let codeReview = entry.codeReviewRemainingPercent {
                UsageBarRow(
                    title: "Code review",
                    percentLeft: codeReview,
                    color: WidgetColors.color(for: self.entry.provider))
            }
            if let credits = entry.creditsRemaining {
                ValueLine(title: "Credits", value: WidgetFormat.credits(credits))
            }
            if let providerCost = entry.providerCost, !self.entry.showsCursorRequestDetails {
                ProviderCostLines(cost: providerCost)
            }
            if let token = entry.tokenUsage {
                VStack(alignment: .leading, spacing: 4) {
                    if token.hasPrimaryValue {
                        ValueLine(
                            title: token.primaryLabel,
                            value: token.primaryCostAndTokensValue())
                    }
                    if token.hasSecondaryValue {
                        ValueLine(
                            title: token.secondaryLabel,
                            value: WidgetFormat.costAndTokens(
                                cost: token.last30DaysCostUSD,
                                tokens: token.last30DaysTokens))
                    }
                }
            }
            if let presentation = CursorWidgetRequestPresentation.selection(
                provider: self.entry.provider,
                details: self.entry.cursorRequestDetails,
                range: self.entry.cursorRequestRange,
                size: .large)
            {
                CursorRequestDetailsView(presentation: presentation)
            } else {
                UsageHistoryChart(points: self.entry.dailyUsage, color: WidgetColors.color(for: self.entry.provider))
                    .frame(height: 50)
            }
        }
    }
}

private struct SmallUsageView: View {
    let entry: WidgetSnapshot.ProviderEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HeaderView(provider: self.entry.provider, updatedAt: self.entry.updatedAt)
            ForEach(WidgetUsageRow.rows(for: self.entry)) { row in
                UsageBarRow(
                    title: row.title,
                    percentLeft: row.percentLeft,
                    detailText: row.detailText,
                    color: WidgetColors.color(for: self.entry.provider))
            }
            if let codeReview = entry.codeReviewRemainingPercent {
                UsageBarRow(
                    title: "Code review",
                    percentLeft: codeReview,
                    color: WidgetColors.color(for: self.entry.provider))
            }
        }
        .padding(12)
    }
}

private struct MediumUsageView: View {
    let entry: WidgetSnapshot.ProviderEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HeaderView(provider: self.entry.provider, updatedAt: self.entry.updatedAt)
            ForEach(WidgetUsageRow.rows(for: self.entry)) { row in
                UsageBarRow(
                    title: row.title,
                    percentLeft: row.percentLeft,
                    detailText: row.detailText,
                    color: WidgetColors.color(for: self.entry.provider))
            }
            if let credits = entry.creditsRemaining {
                ValueLine(title: "Credits", value: WidgetFormat.credits(credits))
            }
            if let providerCost = entry.providerCost, !self.entry.showsCursorRequestDetails {
                ProviderCostLines(cost: providerCost)
            }
            if let token = entry.tokenUsage, token.hasPrimaryValue {
                ValueLine(
                    title: token.primaryLabel,
                    value: token.primaryCostAndTokensValue())
            }
            if let presentation = CursorWidgetRequestPresentation.selection(
                provider: self.entry.provider,
                details: self.entry.cursorRequestDetails,
                range: self.entry.cursorRequestRange,
                size: .medium)
            {
                CursorRequestDetailsView(presentation: presentation)
            }
        }
        .padding(12)
    }
}

private struct LargeUsageView: View {
    let entry: WidgetSnapshot.ProviderEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HeaderView(provider: self.entry.provider, updatedAt: self.entry.updatedAt)
            ForEach(WidgetUsageRow.rows(for: self.entry)) { row in
                UsageBarRow(
                    title: row.title,
                    percentLeft: row.percentLeft,
                    detailText: row.detailText,
                    color: WidgetColors.color(for: self.entry.provider))
            }
            if let codeReview = entry.codeReviewRemainingPercent {
                UsageBarRow(
                    title: "Code review",
                    percentLeft: codeReview,
                    color: WidgetColors.color(for: self.entry.provider))
            }
            if let credits = entry.creditsRemaining {
                ValueLine(title: "Credits", value: WidgetFormat.credits(credits))
            }
            if let providerCost = entry.providerCost, !self.entry.showsCursorRequestDetails {
                ProviderCostLines(cost: providerCost)
            }
            if let token = entry.tokenUsage {
                VStack(alignment: .leading, spacing: 4) {
                    if token.hasPrimaryValue {
                        ValueLine(
                            title: token.primaryLabel,
                            value: token.primaryCostAndTokensValue())
                    }
                    if token.hasSecondaryValue {
                        ValueLine(
                            title: token.secondaryLabel,
                            value: WidgetFormat.costAndTokens(
                                cost: token.last30DaysCostUSD,
                                tokens: token.last30DaysTokens))
                    }
                }
            }
            if let presentation = CursorWidgetRequestPresentation.selection(
                provider: self.entry.provider,
                details: self.entry.cursorRequestDetails,
                range: self.entry.cursorRequestRange,
                size: .large)
            {
                CursorRequestDetailsView(presentation: presentation)
            } else {
                UsageHistoryChart(points: self.entry.dailyUsage, color: WidgetColors.color(for: self.entry.provider))
                    .frame(height: 50)
            }
        }
        .padding(12)
    }
}

struct WidgetUsageRow: Identifiable, Equatable {
    let id: String
    let title: String
    let percentLeft: Double?
    let detailText: String?

    init(id: String, title: String, percentLeft: Double?, detailText: String? = nil) {
        self.id = id
        self.title = title
        self.percentLeft = percentLeft
        self.detailText = detailText
    }

    static func rows(for entry: WidgetSnapshot.ProviderEntry) -> [WidgetUsageRow] {
        if let usageRows = entry.usageRows {
            return usageRows.map { row in
                WidgetUsageRow(id: row.id, title: row.title, percentLeft: row.percentLeft, detailText: row.detailText)
            }
        }

        let metadata = ProviderDefaults.metadata[entry.provider]
        return [
            WidgetUsageRow(
                id: "primary",
                title: metadata?.sessionLabel ?? "Session",
                percentLeft: entry.primary?.remainingPercent,
                detailText: entry.primary.flatMap(Self.detailText)),
            WidgetUsageRow(
                id: "secondary",
                title: metadata?.weeklyLabel ?? "Weekly",
                percentLeft: entry.secondary?.remainingPercent,
                detailText: entry.secondary.flatMap(Self.detailText)),
        ].filter { $0.percentLeft != nil }
    }

    private static func detailText(window: RateWindow) -> String? {
        let detail = window.resetDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
        return detail?.isEmpty == false ? detail : nil
    }
}

private struct HistoryView: View {
    let entry: WidgetSnapshot.ProviderEntry
    let isLarge: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HeaderView(provider: self.entry.provider, updatedAt: self.entry.updatedAt)
            UsageHistoryChart(points: self.entry.dailyUsage, color: WidgetColors.color(for: self.entry.provider))
                .frame(height: self.isLarge ? 90 : 60)
            if let providerCost = entry.providerCost {
                ProviderCostLines(cost: providerCost)
            }
            if let token = entry.tokenUsage {
                if token.hasPrimaryValue {
                    ValueLine(
                        title: token.primaryLabel,
                        value: token.primaryCostAndTokensValue())
                }
                if token.hasSecondaryValue {
                    ValueLine(
                        title: token.secondaryLabel,
                        value: WidgetFormat.costAndTokens(
                            cost: token.last30DaysCostUSD,
                            tokens: token.last30DaysTokens))
                }
            }
        }
        .padding(12)
    }
}

private struct ProviderCostLines: View {
    let cost: WidgetSnapshot.ProviderCostSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ValueLine(
                title: self.cost.title,
                value: WidgetFormat.providerCostValue(self.cost))
            if let periodLine = WidgetFormat.providerCostPeriodLine(self.cost) {
                Text(periodLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

extension WidgetSnapshot.TokenUsageSummary {
    fileprivate var primaryLabel: String {
        self.sessionLabel ?? "Today"
    }

    fileprivate var secondaryLabel: String {
        self.last30DaysLabel ?? "30d"
    }

    fileprivate var hasPrimaryValue: Bool {
        self.sessionCostUSD != nil || self.sessionCostText != nil || self.sessionTokens != nil
    }

    fileprivate func primaryCostAndTokensValue() -> String {
        WidgetFormat.costAndTokens(
            costText: self.sessionCostText,
            cost: self.sessionCostUSD,
            tokens: self.sessionTokens)
    }

    fileprivate var hasSecondaryValue: Bool {
        self.last30DaysCostUSD != nil || self.last30DaysTokens != nil
    }
}

extension WidgetSnapshot.ProviderCostSummary {
    fileprivate var title: String {
        self.currencyCode == "Quota" ? "Quota" : "Extra usage"
    }
}

private struct HeaderView: View {
    let provider: UsageProvider
    let updatedAt: Date

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(ProviderDefaults.metadata[self.provider]?.displayName ?? self.provider.rawValue.capitalized)
                .font(.body)
                .fontWeight(.semibold)
            Spacer()
            Text(WidgetFormat.relativeDate(self.updatedAt))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct UsageBarRow: View {
    let title: String
    let percentLeft: Double?
    let detailText: String?
    let color: Color

    init(title: String, percentLeft: Double?, detailText: String? = nil, color: Color) {
        self.title = title
        self.percentLeft = percentLeft
        self.detailText = detailText
        self.color = color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(self.title)
                    .font(.caption)
                Spacer()
                Text(WidgetFormat.percent(self.percentLeft))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                let width = max(0, min(1, (percentLeft ?? 0) / 100)) * proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(self.color).frame(width: width)
                }
            }
            .frame(height: 6)
            if let detailText {
                Text(detailText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ValueLine: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(self.title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(self.value)
                .font(.caption)
        }
    }
}

private struct UsageHistoryChart: View {
    let points: [WidgetSnapshot.DailyUsagePoint]
    let color: Color

    var body: some View {
        let values = self.points.map { point -> Double in
            if let cost = point.costUSD { return cost }
            return Double(point.totalTokens ?? 0)
        }
        let maxValue = values.max() ?? 0
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(values.indices, id: \.self) { index in
                let value = values[index]
                let height = maxValue > 0 ? CGFloat(value / maxValue) : 0
                RoundedRectangle(cornerRadius: 2)
                    .fill(self.color.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .scaleEffect(x: 1, y: height, anchor: .bottom)
                    .animation(.easeOut(duration: 0.2), value: height)
            }
        }
    }
}

enum WidgetColors {
    // swiftlint:disable:next cyclomatic_complexity
    static func color(for provider: UsageProvider) -> Color {
        switch provider {
        case .codex:
            Color(red: 73 / 255, green: 163 / 255, blue: 176 / 255)
        case .claude:
            Color(red: 204 / 255, green: 124 / 255, blue: 94 / 255)
        case .gemini:
            Color(red: 171 / 255, green: 135 / 255, blue: 234 / 255)
        case .antigravity:
            Color(red: 96 / 255, green: 186 / 255, blue: 126 / 255)
        case .cursor:
            Color(red: 0 / 255, green: 191 / 255, blue: 165 / 255) // #00BFA5 - Cursor teal
        case .opencode:
            Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255)
        case .opencodego:
            Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255)
        case .alibaba:
            Color(red: 1.0, green: 106 / 255, blue: 0)
        case .zai:
            Color(red: 232 / 255, green: 90 / 255, blue: 106 / 255)
        case .factory:
            Color(red: 255 / 255, green: 107 / 255, blue: 53 / 255) // Factory orange
        case .copilot:
            Color(red: 168 / 255, green: 85 / 255, blue: 247 / 255) // Purple
        case .minimax:
            Color(red: 254 / 255, green: 96 / 255, blue: 60 / 255)
        case .vertexai:
            Color(red: 66 / 255, green: 133 / 255, blue: 244 / 255) // Google Blue
        case .kilo:
            Color(red: 242 / 255, green: 112 / 255, blue: 39 / 255) // Kilo orange
        case .kiro:
            Color(red: 255 / 255, green: 153 / 255, blue: 0 / 255) // AWS orange
        case .augment:
            Color(red: 99 / 255, green: 102 / 255, blue: 241 / 255) // Augment purple
        case .jetbrains:
            Color(red: 255 / 255, green: 51 / 255, blue: 153 / 255) // JetBrains pink
        case .kimi:
            Color(red: 254 / 255, green: 96 / 255, blue: 60 / 255) // Kimi orange
        case .kimik2:
            Color(red: 76 / 255, green: 0 / 255, blue: 255 / 255) // Kimi K2 purple
        case .amp:
            Color(red: 220 / 255, green: 38 / 255, blue: 38 / 255) // Amp red
        case .ollama:
            Color(red: 32 / 255, green: 32 / 255, blue: 32 / 255) // Ollama charcoal
        case .synthetic:
            Color(red: 20 / 255, green: 20 / 255, blue: 20 / 255) // Synthetic charcoal
        case .openrouter:
            Color(red: 111 / 255, green: 66 / 255, blue: 193 / 255) // OpenRouter purple
        case .warp:
            Color(red: 147 / 255, green: 139 / 255, blue: 180 / 255)
        case .perplexity:
            Color(red: 32 / 255, green: 178 / 255, blue: 170 / 255) // Perplexity teal
        }
    }
}

extension WidgetSnapshot.ProviderEntry {
    fileprivate var showsCursorRequestDetails: Bool {
        self.provider == .cursor && !(self.cursorRequestDetails?.isEmpty ?? true)
    }
}

enum CursorWidgetRequestPresentation {
    enum WidgetSize {
        case medium
        case large
    }

    /// Compact widget row. The widget has no hover, so only display-ready fields are kept; the raw
    /// model and breakdown stay out of the visible row.
    struct Row: Equatable, Identifiable {
        let id: Int
        let modelText: String
        let metaText: String
        let tokenText: String
        let estimateText: String?
    }

    struct Selection: Equatable {
        let visible: [WidgetSnapshot.CursorRequestDetail]
        let rows: [Row]
        let hiddenCount: Int
        let range: WidgetSnapshot.CursorRequestRange?
    }

    static func selection(
        provider: UsageProvider,
        details: [WidgetSnapshot.CursorRequestDetail]?,
        range: WidgetSnapshot.CursorRequestRange? = nil,
        size: WidgetSize) -> Selection?
    {
        guard provider == .cursor,
              let details,
              !details.isEmpty
        else {
            return nil
        }

        let maxVisible = size == .medium ? 3 : 5
        let visible = Array(details.prefix(maxVisible))
        let hiddenCount = max(0, details.count - visible.count)
        let rows = visible.enumerated().map { index, detail -> Row in
            let time = WidgetFormat.requestDateTime(detail.timestamp)
            let count = WidgetFormat.requestCountLabel(detail.requests)
            return Row(
                id: index,
                modelText: detail.compactModel ?? detail.model,
                metaText: "\(time) · \(count)",
                tokenText: UsageFormatter.tokenCountString(detail.tokens),
                estimateText: detail.estimateText)
        }
        return Selection(visible: visible, rows: rows, hiddenCount: hiddenCount, range: range)
    }
}

private struct CursorRequestDetailsView: View {
    let presentation: CursorWidgetRequestPresentation.Selection

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let range = self.presentation.range {
                Text(WidgetFormat.cursorRequestRange(range))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ForEach(self.presentation.rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(row.modelText)
                        .font(.caption2)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(row.metaText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(row.tokenText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let estimateText = row.estimateText {
                        Text(estimateText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if self.presentation.hiddenCount > 0 {
                Text("+\(self.presentation.hiddenCount) more")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

enum WidgetFormat {
    static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f%%", value)
    }

    static func credits(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    static func costAndTokens(costText: String? = nil, cost: Double?, tokens: Int?) -> String {
        let costLabel = costText ?? cost.map { self.usd($0) }
        if let costLabel, let tokens {
            return "\(costLabel) · \(self.tokenCount(tokens))"
        }
        if let costLabel {
            return costLabel
        }
        if let tokens {
            return self.tokenCount(tokens)
        }
        return "—"
    }

    static func usd(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }

    static func tokenCount(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        let raw = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return "\(raw) tokens"
    }

    static func requestTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func requestDateTime(_ date: Date) -> String {
        "\(date.formatted(.dateTime.month(.abbreviated).day())) · \(self.requestTime(date))"
    }

    static func requestCountLabel(_ count: Int) -> String {
        count == 1 ? "Req 1" : "Req \(count)"
    }

    static func cursorRequestRange(_ range: WidgetSnapshot.CursorRequestRange) -> String {
        let start = range.start.formatted(.dateTime.month(.abbreviated).day())
        let end = range.end.formatted(.dateTime.month(.abbreviated).day())
        return "\(start) - \(end)"
    }

    static func providerCostValue(_ cost: WidgetSnapshot.ProviderCostSummary) -> String {
        let used: String
        let limit: String
        if cost.currencyCode == "Quota" {
            used = String(format: "%.0f", cost.used)
            limit = String(format: "%.0f", cost.limit)
        } else {
            used = self.currency(cost.used, currencyCode: cost.currencyCode)
            limit = self.currency(cost.limit, currencyCode: cost.currencyCode)
        }
        return "\(used) / \(limit)"
    }

    static func providerCostPeriodLine(
        _ cost: WidgetSnapshot.ProviderCostSummary,
        now: Date = Date()) -> String?
    {
        let period = cost.period?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let renewal = cost.resetsAt else { return nil }
        let renewalText = "renews \(self.relativeDate(renewal, relativeTo: now))"
        switch period?.isEmpty == false ? period : nil {
        case let period?:
            return "\(period) · \(renewalText)"
        case nil:
            return renewalText
        }
    }

    static func relativeDate(_ date: Date) -> String {
        self.relativeDate(date, relativeTo: Date())
    }

    private static func relativeDate(_ date: Date, relativeTo now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: now)
    }

    private static func currency(_ value: Double, currencyCode: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "\(currencyCode) \(String(format: "%.2f", value))"
    }
}
