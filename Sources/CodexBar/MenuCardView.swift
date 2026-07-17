import AppKit
import CodexBarCore
import SwiftUI

/// SwiftUI card used inside the NSMenu to mirror Apple's rich menu panels.
struct UsageMenuCardView: View {
    struct Model {
        enum PercentStyle: String {
            case left
            case used

            var labelSuffix: String {
                switch self {
                case .left: "left"
                case .used: "used"
                }
            }

            var accessibilityLabel: String {
                switch self {
                case .left: "Usage remaining"
                case .used: "Usage used"
                }
            }
        }

        struct Metric: Identifiable {
            let id: String
            let title: String
            let percent: Double
            let percentStyle: PercentStyle
            let statusText: String?
            let resetText: String?
            let detailText: String?
            let detailLeftText: String?
            let detailRightText: String?
            let pacePercent: Double?
            let paceOnTop: Bool

            init(
                id: String,
                title: String,
                percent: Double,
                percentStyle: PercentStyle,
                statusText: String? = nil,
                resetText: String?,
                detailText: String?,
                detailLeftText: String?,
                detailRightText: String?,
                pacePercent: Double?,
                paceOnTop: Bool)
            {
                self.id = id
                self.title = title
                self.percent = percent
                self.percentStyle = percentStyle
                self.statusText = statusText
                self.resetText = resetText
                self.detailText = detailText
                self.detailLeftText = detailLeftText
                self.detailRightText = detailRightText
                self.pacePercent = pacePercent
                self.paceOnTop = paceOnTop
            }

            var percentLabel: String {
                String(format: "%.0f%% %@", self.percent, self.percentStyle.labelSuffix)
            }
        }

        enum SubtitleStyle {
            case info
            case loading
            case error
        }

        struct TokenUsageSection {
            struct CursorRangePresentation {
                let sessionLine: String
                let monthLine: String?
                let cursorRequestRange: CursorRecentRequestRange?
                let cursorRequestDetails: [CursorRecentRequest]
            }

            let title: String
            let sessionLine: String
            let monthLine: String?
            let detailLines: [String]
            let cursorRequestRange: CursorRecentRequestRange?
            let cursorRequestDetails: [CursorRecentRequest]
            let selectedCursorRangeKind: CursorUsageRangeKind?
            let availableCursorRangeKinds: [CursorUsageRangeKind]
            let cursorRangePresentations: [CursorUsageRangeKind: CursorRangePresentation]
            let selectCursorRange: ((CursorUsageRangeKind) -> Void)?
            let cursorRequestNow: Date?
            let renewalLine: String?
            let hintLine: String?
            let errorLine: String?
            let errorCopyText: String?

            init(
                title: String,
                sessionLine: String,
                monthLine: String?,
                detailLines: [String] = [],
                cursorRequestRange: CursorRecentRequestRange? = nil,
                cursorRequestDetails: [CursorRecentRequest] = [],
                selectedCursorRangeKind: CursorUsageRangeKind? = nil,
                availableCursorRangeKinds: [CursorUsageRangeKind] = [],
                cursorRangePresentations: [CursorUsageRangeKind: CursorRangePresentation] = [:],
                selectCursorRange: ((CursorUsageRangeKind) -> Void)? = nil,
                cursorRequestNow: Date? = nil,
                renewalLine: String?,
                hintLine: String?,
                errorLine: String?,
                errorCopyText: String?)
            {
                self.title = title
                self.sessionLine = sessionLine
                self.monthLine = monthLine
                self.detailLines = detailLines
                self.cursorRequestRange = cursorRequestRange
                self.cursorRequestDetails = cursorRequestDetails
                self.selectedCursorRangeKind = selectedCursorRangeKind
                self.availableCursorRangeKinds = availableCursorRangeKinds
                self.cursorRangePresentations = cursorRangePresentations
                self.selectCursorRange = selectCursorRange
                self.cursorRequestNow = cursorRequestNow
                self.renewalLine = renewalLine
                self.hintLine = hintLine
                self.errorLine = errorLine
                self.errorCopyText = errorCopyText
            }
        }

        struct ProviderCostSection {
            let title: String
            let percentUsed: Double
            let spendLine: String
            let renewalLine: String?
        }

        let provider: UsageProvider
        let providerName: String
        let email: String
        let subtitleText: String
        let subtitleStyle: SubtitleStyle
        let planText: String?
        let metrics: [Metric]
        let usageNotes: [String]
        let creditsText: String?
        let creditsRemaining: Double?
        let creditsHintText: String?
        let creditsHintCopyText: String?
        let providerCost: ProviderCostSection?
        let tokenUsage: TokenUsageSection?
        let placeholder: String?
        let progressColor: Color
    }

    let model: Model
    let width: CGFloat
    @Environment(\.menuItemHighlighted) private var isHighlighted

    static func popupMetricTitle(provider: UsageProvider, metric: Model.Metric) -> String {
        if provider == .openrouter, metric.id == "primary" {
            return "API key limit"
        }
        return metric.title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            UsageMenuCardHeaderView(model: self.model)

            if self.hasDetails {
                Divider()
            }

            if self.model.metrics.isEmpty {
                if !self.model.usageNotes.isEmpty {
                    UsageNotesContent(notes: self.model.usageNotes)
                } else if let placeholder = self.model.placeholder {
                    Text(placeholder)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                        .font(.subheadline)
                }
            } else {
                let hasUsage = !self.model.metrics.isEmpty || !self.model.usageNotes.isEmpty
                let hasCredits = self.model.creditsText != nil
                let hasProviderCost = self.model.providerCost != nil
                let hasCost = self.model.tokenUsage != nil || hasProviderCost

                VStack(alignment: .leading, spacing: 12) {
                    if hasUsage {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(self.model.metrics, id: \.id) { metric in
                                MetricRow(
                                    metric: metric,
                                    title: Self.popupMetricTitle(provider: self.model.provider, metric: metric),
                                    progressColor: self.model.progressColor)
                            }
                            if !self.model.usageNotes.isEmpty {
                                UsageNotesContent(notes: self.model.usageNotes)
                            }
                        }
                    }
                    if hasUsage, hasCredits || hasCost {
                        Divider()
                    }
                    if let credits = self.model.creditsText {
                        CreditsBarContent(
                            creditsText: credits,
                            creditsRemaining: self.model.creditsRemaining,
                            hintText: self.model.creditsHintText,
                            hintCopyText: self.model.creditsHintCopyText,
                            progressColor: self.model.progressColor)
                    }
                    if hasCredits, hasCost {
                        Divider()
                    }
                    if let providerCost = self.model.providerCost {
                        ProviderCostContent(
                            section: providerCost,
                            progressColor: self.model.progressColor)
                    }
                    if hasProviderCost, self.model.tokenUsage != nil {
                        Divider()
                    }
                    if let tokenUsage = self.model.tokenUsage {
                        TokenUsageContentView(
                            provider: self.model.provider,
                            tokenUsage: tokenUsage,
                            lineFont: .footnote,
                            detailFont: .caption)
                    }
                }
                .padding(.bottom, self.model.creditsText == nil ? 6 : 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 2)
        .frame(width: self.width, alignment: .leading)
    }

    private var hasDetails: Bool {
        !self.model.metrics.isEmpty || !self.model.usageNotes.isEmpty || self.model.placeholder != nil ||
            self.model.tokenUsage != nil ||
            self.model.providerCost != nil
    }
}

private struct UsageMenuCardHeaderView: View {
    let model: UsageMenuCardView.Model
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(self.model.providerName)
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Text(self.model.email)
                    .font(.subheadline)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            }
            let subtitleAlignment: VerticalAlignment = self.model.subtitleStyle == .error ? .top : .firstTextBaseline
            HStack(alignment: subtitleAlignment) {
                Text(self.model.subtitleText)
                    .font(.footnote)
                    .foregroundStyle(self.subtitleColor)
                    .lineLimit(self.model.subtitleStyle == .error ? 4 : 1)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                    .padding(.bottom, self.model.subtitleStyle == .error ? 4 : 0)
                Spacer()
                if self.model.subtitleStyle == .error, !self.model.subtitleText.isEmpty {
                    CopyIconButton(copyText: self.model.subtitleText, isHighlighted: self.isHighlighted)
                }
                if let plan = self.model.planText {
                    Text(plan)
                        .font(.footnote)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                        .lineLimit(1)
                }
            }
        }
    }

    private var subtitleColor: Color {
        switch self.model.subtitleStyle {
        case .info: MenuHighlightStyle.secondary(self.isHighlighted)
        case .loading: MenuHighlightStyle.secondary(self.isHighlighted)
        case .error: MenuHighlightStyle.error(self.isHighlighted)
        }
    }
}

private struct CopyIconButtonStyle: ButtonStyle {
    let isHighlighted: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(4)
            .background {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(MenuHighlightStyle.secondary(self.isHighlighted).opacity(configuration.isPressed ? 0.18 : 0))
            }
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct CopyIconButton: View {
    let copyText: String
    let isHighlighted: Bool

    @State private var didCopy = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        Button {
            self.copyToPasteboard()
            withAnimation(.easeOut(duration: 0.12)) {
                self.didCopy = true
            }
            self.resetTask?.cancel()
            self.resetTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.9))
                withAnimation(.easeOut(duration: 0.2)) {
                    self.didCopy = false
                }
            }
        } label: {
            Image(systemName: self.didCopy ? "checkmark" : "doc.on.doc")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(CopyIconButtonStyle(isHighlighted: self.isHighlighted))
        .accessibilityLabel(self.didCopy ? "Copied" : "Copy error")
    }

    private func copyToPasteboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(self.copyText, forType: .string)
    }
}

private struct UsageNotesContent: View {
    let notes: [String]
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(self.notes.enumerated()), id: \.offset) { _, note in
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct UsageMenuCardHeaderSectionView: View {
    let model: UsageMenuCardView.Model
    let showDivider: Bool
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            UsageMenuCardHeaderView(model: self.model)

            if self.showDivider {
                Divider()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, self.model.subtitleStyle == .error ? 2 : 0)
        .frame(width: self.width, alignment: .leading)
    }
}

struct UsageMenuCardUsageSectionView: View {
    let model: UsageMenuCardView.Model
    let showBottomDivider: Bool
    let bottomPadding: CGFloat
    let width: CGFloat
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if self.model.metrics.isEmpty {
                if !self.model.usageNotes.isEmpty {
                    UsageNotesContent(notes: self.model.usageNotes)
                } else if let placeholder = self.model.placeholder {
                    Text(placeholder)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                        .font(.subheadline)
                }
            } else {
                ForEach(self.model.metrics, id: \.id) { metric in
                    MetricRow(
                        metric: metric,
                        title: UsageMenuCardView.popupMetricTitle(provider: self.model.provider, metric: metric),
                        progressColor: self.model.progressColor)
                }
                if !self.model.usageNotes.isEmpty {
                    UsageNotesContent(notes: self.model.usageNotes)
                }
            }
            if self.showBottomDivider {
                Divider()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, self.bottomPadding)
        .frame(width: self.width, alignment: .leading)
    }
}

struct UsageMenuCardCreditsSectionView: View {
    let model: UsageMenuCardView.Model
    let showBottomDivider: Bool
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let width: CGFloat

    var body: some View {
        if let credits = self.model.creditsText {
            VStack(alignment: .leading, spacing: 6) {
                CreditsBarContent(
                    creditsText: credits,
                    creditsRemaining: self.model.creditsRemaining,
                    hintText: self.model.creditsHintText,
                    hintCopyText: self.model.creditsHintCopyText,
                    progressColor: self.model.progressColor)
                if self.showBottomDivider {
                    Divider()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, self.topPadding)
            .padding(.bottom, self.bottomPadding)
            .frame(width: self.width, alignment: .leading)
        }
    }
}

private struct CreditsBarContent: View {
    private static let fullScaleTokens: Double = 1000

    let creditsText: String
    let creditsRemaining: Double?
    let hintText: String?
    let hintCopyText: String?
    let progressColor: Color
    @Environment(\.menuItemHighlighted) private var isHighlighted

    private var percentLeft: Double? {
        guard let creditsRemaining else { return nil }
        let percent = (creditsRemaining / Self.fullScaleTokens) * 100
        return min(100, max(0, percent))
    }

    private var scaleText: String {
        let scale = UsageFormatter.tokenCountString(Int(Self.fullScaleTokens))
        return "\(scale) tokens"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Credits")
                .font(.body)
                .fontWeight(.medium)
            if let percentLeft {
                UsageProgressBar(
                    percent: percentLeft,
                    tint: self.progressColor,
                    accessibilityLabel: "Credits remaining")
                HStack(alignment: .firstTextBaseline) {
                    Text(self.creditsText)
                        .font(.caption)
                    Spacer()
                    Text(self.scaleText)
                        .font(.caption)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                }
            } else {
                Text(self.creditsText)
                    .font(.caption)
            }
            if let hintText, !hintText.isEmpty {
                Text(hintText)
                    .font(.footnote)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .overlay {
                        ClickToCopyOverlay(copyText: self.hintCopyText ?? hintText)
                    }
            }
        }
    }
}

struct UsageMenuCardCostSectionView: View {
    let model: UsageMenuCardView.Model
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let width: CGFloat
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        let hasTokenCost = self.model.tokenUsage != nil
        return Group {
            if hasTokenCost {
                VStack(alignment: .leading, spacing: 10) {
                    if let tokenUsage = self.model.tokenUsage {
                        TokenUsageContentView(
                            provider: self.model.provider,
                            tokenUsage: tokenUsage,
                            lineFont: .caption,
                            detailFont: .caption2)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, self.topPadding)
                .padding(.bottom, self.bottomPadding)
                .frame(width: self.width, alignment: .leading)
            }
        }
    }
}

struct UsageMenuCardExtraUsageSectionView: View {
    let model: UsageMenuCardView.Model
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let width: CGFloat

    var body: some View {
        Group {
            if let providerCost = self.model.providerCost {
                ProviderCostContent(
                    section: providerCost,
                    progressColor: self.model.progressColor)
                    .padding(.horizontal, 16)
                    .padding(.top, self.topPadding)
                    .padding(.bottom, self.bottomPadding)
                    .frame(width: self.width, alignment: .leading)
            }
        }
    }
}

// MARK: - Model factory

extension UsageMenuCardView.Model {
    struct Input {
        let provider: UsageProvider
        let metadata: ProviderMetadata
        let snapshot: UsageSnapshot?
        let codexProjection: CodexConsumerProjection?
        let credits: CreditsSnapshot?
        let creditsError: String?
        let dashboard: OpenAIDashboardSnapshot?
        let dashboardError: String?
        let tokenSnapshot: CostUsageTokenSnapshot?
        let tokenError: String?
        let account: AccountInfo
        let isRefreshing: Bool
        let lastError: String?
        let usageBarsShowUsed: Bool
        let resetTimeDisplayStyle: ResetTimeDisplayStyle
        let tokenCostUsageEnabled: Bool
        let showOptionalCreditsAndExtraUsage: Bool
        let sourceLabel: String?
        let kiloAutoMode: Bool
        let hidePersonalInfo: Bool
        let forceLoadingSubtitle: Bool
        let weeklyPace: UsagePace?
        let cursorUsageRangeKind: CursorUsageRangeKind
        let selectCursorUsageRange: ((CursorUsageRangeKind) -> Void)?
        let now: Date

        init(
            provider: UsageProvider,
            metadata: ProviderMetadata,
            snapshot: UsageSnapshot?,
            codexProjection: CodexConsumerProjection? = nil,
            credits: CreditsSnapshot?,
            creditsError: String?,
            dashboard: OpenAIDashboardSnapshot?,
            dashboardError: String?,
            tokenSnapshot: CostUsageTokenSnapshot?,
            tokenError: String?,
            account: AccountInfo,
            isRefreshing: Bool,
            lastError: String?,
            usageBarsShowUsed: Bool,
            resetTimeDisplayStyle: ResetTimeDisplayStyle,
            tokenCostUsageEnabled: Bool,
            showOptionalCreditsAndExtraUsage: Bool,
            sourceLabel: String? = nil,
            kiloAutoMode: Bool = false,
            hidePersonalInfo: Bool,
            forceLoadingSubtitle: Bool = false,
            weeklyPace: UsagePace? = nil,
            cursorUsageRangeKind: CursorUsageRangeKind = .billingCycle,
            selectCursorUsageRange: ((CursorUsageRangeKind) -> Void)? = nil,
            now: Date)
        {
            self.provider = provider
            self.metadata = metadata
            self.snapshot = snapshot
            self.codexProjection = codexProjection
            self.credits = credits
            self.creditsError = creditsError
            self.dashboard = dashboard
            self.dashboardError = dashboardError
            self.tokenSnapshot = tokenSnapshot
            self.tokenError = tokenError
            self.account = account
            self.isRefreshing = isRefreshing
            self.lastError = lastError
            self.usageBarsShowUsed = usageBarsShowUsed
            self.resetTimeDisplayStyle = resetTimeDisplayStyle
            self.tokenCostUsageEnabled = tokenCostUsageEnabled
            self.showOptionalCreditsAndExtraUsage = showOptionalCreditsAndExtraUsage
            self.sourceLabel = sourceLabel
            self.kiloAutoMode = kiloAutoMode
            self.hidePersonalInfo = hidePersonalInfo
            self.forceLoadingSubtitle = forceLoadingSubtitle
            self.weeklyPace = weeklyPace
            self.cursorUsageRangeKind = cursorUsageRangeKind
            self.selectCursorUsageRange = selectCursorUsageRange
            self.now = now
        }
    }

    static func make(_ input: Input) -> UsageMenuCardView.Model {
        let planText = Self.plan(
            for: input.provider,
            snapshot: input.snapshot,
            account: input.account,
            metadata: input.metadata)
        let metrics = Self.metrics(input: input)
        let usageNotes = Self.usageNotes(input: input)
        let creditsText: String? = if input.provider == .openrouter {
            nil
        } else if input.codexProjection != nil, !input.showOptionalCreditsAndExtraUsage {
            nil
        } else {
            Self.creditsLine(metadata: input.metadata, credits: input.credits, error: input.creditsError)
        }
        let providerCost: ProviderCostSection? = if input.provider == .claude, !input.showOptionalCreditsAndExtraUsage {
            nil
        } else {
            Self.providerCostSection(provider: input.provider, cost: input.snapshot?.providerCost, now: input.now)
        }
        let tokenUsage = Self.tokenUsageSection(input: input)
        let subtitle = Self.subtitle(
            snapshot: input.snapshot,
            isRefreshing: input.isRefreshing,
            forceLoading: input.forceLoadingSubtitle,
            lastError: input.lastError)
        let redacted = Self.redactedText(input: input, subtitle: subtitle)
        let placeholder = input.snapshot == nil && !input.isRefreshing && input.lastError == nil ? "No usage yet" : nil

        return UsageMenuCardView.Model(
            provider: input.provider,
            providerName: input.metadata.displayName,
            email: redacted.email,
            subtitleText: redacted.subtitleText,
            subtitleStyle: subtitle.style,
            planText: planText,
            metrics: metrics,
            usageNotes: usageNotes,
            creditsText: creditsText,
            creditsRemaining: input.credits?.remaining,
            creditsHintText: redacted.creditsHintText,
            creditsHintCopyText: redacted.creditsHintCopyText,
            providerCost: providerCost,
            tokenUsage: tokenUsage,
            placeholder: placeholder,
            progressColor: Self.progressColor(for: input.provider))
    }

    private static func usageNotes(input: Input) -> [String] {
        if input.provider == .kilo {
            var notes = Self.kiloLoginDetails(snapshot: input.snapshot)
            let resolvedSource = input.sourceLabel?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if input.kiloAutoMode,
               resolvedSource == "cli",
               !notes.contains(where: { $0.caseInsensitiveCompare("Using CLI fallback") == .orderedSame })
            {
                notes.append("Using CLI fallback")
            }
            return notes
        }

        guard input.provider == .openrouter,
              let openRouter = input.snapshot?.openRouterUsage
        else {
            return []
        }

        return switch openRouter.keyQuotaStatus {
        case .available: []
        case .noLimitConfigured: ["No limit set for the API key"]
        case .unavailable: ["API key limit unavailable right now"]
        }
    }

    private static func email(
        for provider: UsageProvider,
        snapshot: UsageSnapshot?,
        account: AccountInfo,
        metadata: ProviderMetadata) -> String
    {
        if let email = snapshot?.accountEmail(for: provider), !email.isEmpty { return email }
        if metadata.usesAccountFallback,
           let email = account.email, !email.isEmpty
        {
            return email
        }
        return ""
    }

    private static func plan(
        for provider: UsageProvider,
        snapshot: UsageSnapshot?,
        account: AccountInfo,
        metadata: ProviderMetadata) -> String?
    {
        if provider == .kilo {
            guard let pass = self.kiloLoginPass(snapshot: snapshot) else {
                return nil
            }
            return self.planDisplay(pass)
        }
        if let plan = snapshot?.loginMethod(for: provider), !plan.isEmpty {
            return self.planDisplay(plan)
        }
        if metadata.usesAccountFallback,
           let plan = account.plan, !plan.isEmpty
        {
            return Self.planDisplay(plan)
        }
        return nil
    }

    private static func planDisplay(_ text: String) -> String {
        let cleaned = CodexPlanFormatting.displayName(text) ?? UsageFormatter.cleanPlanName(text)
        return cleaned.isEmpty ? text : cleaned
    }

    private static func kiloLoginPass(snapshot: UsageSnapshot?) -> String? {
        self.kiloLoginParts(snapshot: snapshot).pass
    }

    private static func kiloLoginDetails(snapshot: UsageSnapshot?) -> [String] {
        self.kiloLoginParts(snapshot: snapshot).details
    }

    private static func kiloLoginParts(snapshot: UsageSnapshot?) -> (pass: String?, details: [String]) {
        guard let loginMethod = snapshot?.loginMethod(for: .kilo) else {
            return (nil, [])
        }
        let parts = loginMethod
            .components(separatedBy: "·")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else {
            return (nil, [])
        }
        let first = parts[0]
        if self.isKiloActivitySegment(first) {
            return (nil, parts)
        }
        return (first, Array(parts.dropFirst()))
    }

    private static func isKiloActivitySegment(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.hasPrefix("auto top-up:")
    }

    private static func subtitle(
        snapshot: UsageSnapshot?,
        isRefreshing: Bool,
        forceLoading: Bool,
        lastError: String?) -> (text: String, style: SubtitleStyle)
    {
        if forceLoading {
            return ("Loading account...", .loading)
        }

        if let lastError, !lastError.isEmpty {
            return (lastError.trimmingCharacters(in: .whitespacesAndNewlines), .error)
        }

        if isRefreshing, snapshot == nil {
            return ("Refreshing...", .loading)
        }

        if let updated = snapshot?.updatedAt {
            return (UsageFormatter.updatedString(from: updated), .info)
        }

        return ("Not fetched yet", .info)
    }

    private struct RedactedText {
        let email: String
        let subtitleText: String
        let creditsHintText: String?
        let creditsHintCopyText: String?
    }

    private static func redactedText(
        input: Input,
        subtitle: (text: String, style: SubtitleStyle)) -> RedactedText
    {
        let email = PersonalInfoRedactor.redactEmail(
            Self.email(
                for: input.provider,
                snapshot: input.snapshot,
                account: input.account,
                metadata: input.metadata),
            isEnabled: input.hidePersonalInfo)
        let subtitleText = PersonalInfoRedactor.redactEmails(in: subtitle.text, isEnabled: input.hidePersonalInfo)
            ?? subtitle.text
        let creditsHintText = PersonalInfoRedactor.redactEmails(
            in: Self.dashboardHint(error: input.dashboardError),
            isEnabled: input.hidePersonalInfo)
        let creditsHintCopyText = Self.creditsHintCopyText(
            dashboardError: input.dashboardError,
            hidePersonalInfo: input.hidePersonalInfo)
        return RedactedText(
            email: email,
            subtitleText: subtitleText,
            creditsHintText: creditsHintText,
            creditsHintCopyText: creditsHintCopyText)
    }

    private static func creditsHintCopyText(dashboardError: String?, hidePersonalInfo: Bool) -> String? {
        guard let dashboardError, !dashboardError.isEmpty else { return nil }
        return hidePersonalInfo ? "" : dashboardError
    }

    private static func metrics(input: Input) -> [Metric] {
        guard let snapshot = input.snapshot else { return [] }
        if input.provider == .antigravity {
            return Self.antigravityMetrics(input: input, snapshot: snapshot)
        }
        var metrics: [Metric] = []
        let percentStyle: PercentStyle = input.usageBarsShowUsed ? .used : .left
        let zaiUsage = input.provider == .zai ? snapshot.zaiUsage : nil
        let zaiTokenDetail = Self.zaiLimitDetailText(limit: zaiUsage?.tokenLimit)
        let zaiWeeklyDetail = Self.zaiLimitDetailText(limit: zaiUsage?.secondaryTokenLimit)
        let zaiTimeDetail = Self.zaiLimitDetailText(limit: zaiUsage?.timeLimit)
        let openRouterQuotaDetail = Self.openRouterQuotaDetail(provider: input.provider, snapshot: snapshot)
        if input.provider == .codex, let codexProjection = input.codexProjection {
            metrics.append(contentsOf: Self.codexRateMetrics(
                input: input,
                projection: codexProjection,
                percentStyle: percentStyle))
        } else if let primary = snapshot.primary {
            metrics.append(Self.primaryMetric(
                input: input,
                primary: primary,
                percentStyle: percentStyle,
                zaiTokenDetail: zaiTokenDetail,
                openRouterQuotaDetail: openRouterQuotaDetail))
        }
        if input.provider != .codex, let weekly = snapshot.secondary {
            metrics.append(Self.secondaryMetric(
                input: input,
                weekly: weekly,
                percentStyle: percentStyle,
                zaiSecondaryDetail: zaiWeeklyDetail))
        }
        if input.provider == .kilo,
           metrics.contains(where: { $0.id == "primary" }),
           metrics.contains(where: { $0.id == "secondary" })
        {
            metrics.sort { lhs, rhs in
                let kiloOrder: [String: Int] = [
                    "secondary": 0,
                    "primary": 1,
                ]
                return (kiloOrder[lhs.id] ?? Int.max) < (kiloOrder[rhs.id] ?? Int.max)
            }
        }
        if input.metadata.supportsOpus, let opus = snapshot.tertiary {
            var tertiaryDetailText: String?
            if input.provider == .zai {
                tertiaryDetailText = zaiTimeDetail ?? Self.rateWindowDetailText(opus)
            } else if input.provider == .alibaba,
                      let detail = opus.resetDescription,
                      !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                tertiaryDetailText = detail
            }
            // Perplexity purchased credits don't reset; show balance without "Resets" prefix.
            let opusResetText: String? = input.provider == .perplexity
                ? opus.resetDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
                : Self.resetText(for: opus, style: input.resetTimeDisplayStyle, now: input.now)
            metrics.append(Metric(
                id: "tertiary",
                title: input.metadata.opusLabel ?? "Sonnet",
                percent: Self.clamped(input.usageBarsShowUsed ? opus.usedPercent : opus.remainingPercent),
                percentStyle: percentStyle,
                resetText: opusResetText,
                detailText: tertiaryDetailText,
                detailLeftText: nil,
                detailRightText: nil,
                pacePercent: nil,
                paceOnTop: true))
        }

        if let codexProjection = input.codexProjection,
           codexProjection.supplementalMetrics.contains(.codeReview),
           let remaining = codexProjection.remainingPercent(for: .codeReview)
        {
            let percent = input.usageBarsShowUsed ? (100 - remaining) : remaining
            let resetText = codexProjection.limitWindow(for: .codeReview).flatMap {
                Self.resetText(for: $0, style: input.resetTimeDisplayStyle, now: input.now)
            }
            metrics.append(Metric(
                id: "code-review",
                title: "Code review",
                percent: Self.clamped(percent),
                percentStyle: percentStyle,
                resetText: resetText,
                detailText: nil,
                detailLeftText: nil,
                detailRightText: nil,
                pacePercent: nil,
                paceOnTop: true))
        }
        if let codexProjection = input.codexProjection,
           codexProjection.supplementalMetrics.contains(.spark),
           let remaining = codexProjection.remainingPercent(for: .spark)
        {
            let percent = input.usageBarsShowUsed ? (100 - remaining) : remaining
            let resetText = codexProjection.limitWindow(for: .spark).flatMap {
                Self.resetText(for: $0, style: input.resetTimeDisplayStyle, now: input.now)
            }
            metrics.append(Metric(
                id: "codex-spark",
                title: "Codex Spark",
                percent: Self.clamped(percent),
                percentStyle: percentStyle,
                resetText: resetText,
                detailText: nil,
                detailLeftText: nil,
                detailRightText: nil,
                pacePercent: nil,
                paceOnTop: true))
        }
        return metrics
    }

    private static func primaryMetric(
        input: Input,
        primary: RateWindow,
        percentStyle: PercentStyle,
        zaiTokenDetail: String?,
        openRouterQuotaDetail: String?) -> Metric
    {
        var primaryDetailText: String? = if input.provider == .zai {
            zaiTokenDetail ?? Self.rateWindowDetailText(primary)
        } else {
            nil
        }
        var primaryResetText = Self.resetText(for: primary, style: input.resetTimeDisplayStyle, now: input.now)
        if input.provider == .openrouter,
           let openRouterQuotaDetail
        {
            primaryResetText = openRouterQuotaDetail
        }
        if input.provider == .warp || input.provider == .kilo,
           let detail = primary.resetDescription,
           !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            primaryDetailText = detail
        }
        if input.provider == .alibaba,
           let detail = primary.resetDescription,
           !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            primaryDetailText = detail
        }
        if input.provider == .warp || input.provider == .kilo, primary.resetsAt == nil {
            primaryResetText = nil
        }
        return Metric(
            id: "primary",
            title: input.metadata.sessionLabel,
            percent: Self.clamped(
                input.usageBarsShowUsed ? primary.usedPercent : primary.remainingPercent),
            percentStyle: percentStyle,
            resetText: primaryResetText,
            detailText: primaryDetailText,
            detailLeftText: nil,
            detailRightText: nil,
            pacePercent: nil,
            paceOnTop: true)
    }

    private static func secondaryMetric(
        input: Input,
        weekly: RateWindow,
        percentStyle: PercentStyle,
        zaiSecondaryDetail: String?) -> Metric
    {
        let paceDetail = Self.weeklyPaceDetail(
            window: weekly,
            now: input.now,
            pace: input.weeklyPace,
            showUsed: input.usageBarsShowUsed)
        var weeklyResetText = Self.resetText(for: weekly, style: input.resetTimeDisplayStyle, now: input.now)
        var weeklyDetailText: String? = if input.provider == .zai {
            zaiSecondaryDetail ?? Self.rateWindowDetailText(weekly)
        } else {
            nil
        }
        if input.provider == .warp,
           let detail = weekly.resetDescription,
           !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            weeklyResetText = nil
            weeklyDetailText = detail
        }
        if input.provider == .kilo,
           let detail = weekly.resetDescription,
           !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            weeklyDetailText = detail
            if weekly.resetsAt == nil {
                weeklyResetText = nil
            }
        }
        if input.provider == .alibaba,
           let detail = weekly.resetDescription,
           !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            weeklyDetailText = detail
        }
        // Perplexity bonus credits don't reset; show balance without "Resets" prefix.
        if input.provider == .perplexity,
           let detail = weekly.resetDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
           !detail.isEmpty
        {
            weeklyResetText = detail
        }
        return Metric(
            id: "secondary",
            title: input.metadata.weeklyLabel,
            percent: Self.clamped(input.usageBarsShowUsed ? weekly.usedPercent : weekly.remainingPercent),
            percentStyle: percentStyle,
            resetText: weeklyResetText,
            detailText: weeklyDetailText,
            detailLeftText: paceDetail?.leftLabel,
            detailRightText: paceDetail?.rightLabel,
            pacePercent: paceDetail?.pacePercent,
            paceOnTop: paceDetail?.paceOnTop ?? true)
    }

    private static func codexRateMetrics(
        input: Input,
        projection: CodexConsumerProjection,
        percentStyle: PercentStyle) -> [Metric]
    {
        projection.visibleRateLanes.compactMap { lane in
            guard let window = projection.rateWindow(for: lane) else { return nil }

            let title: String
            let id: String
            let paceDetail: PaceDetail?
            switch lane {
            case .session:
                title = input.metadata.sessionLabel
                id = "primary"
                paceDetail = nil
            case .weekly:
                title = input.metadata.weeklyLabel
                id = "secondary"
                paceDetail = Self.weeklyPaceDetail(
                    window: window,
                    now: input.now,
                    pace: input.weeklyPace,
                    showUsed: input.usageBarsShowUsed)
            }

            return Metric(
                id: id,
                title: title,
                percent: Self.clamped(input.usageBarsShowUsed ? window.usedPercent : window.remainingPercent),
                percentStyle: percentStyle,
                resetText: Self.resetText(for: window, style: input.resetTimeDisplayStyle, now: input.now),
                detailText: nil,
                detailLeftText: paceDetail?.leftLabel,
                detailRightText: paceDetail?.rightLabel,
                pacePercent: paceDetail?.pacePercent,
                paceOnTop: paceDetail?.paceOnTop ?? true)
        }
    }

    private static func antigravityMetrics(input: Input, snapshot: UsageSnapshot) -> [Metric] {
        let percentStyle: PercentStyle = input.usageBarsShowUsed ? .used : .left
        return [
            Self.antigravityMetric(
                id: "primary",
                title: input.metadata.sessionLabel,
                window: snapshot.primary,
                input: input,
                percentStyle: percentStyle),
            Self.antigravityMetric(
                id: "secondary",
                title: input.metadata.weeklyLabel,
                window: snapshot.secondary,
                input: input,
                percentStyle: percentStyle),
            Self.antigravityMetric(
                id: "tertiary",
                title: input.metadata.opusLabel ?? "Gemini Flash",
                window: snapshot.tertiary,
                input: input,
                percentStyle: percentStyle),
        ]
    }

    private static func antigravityMetric(
        id: String,
        title: String,
        window: RateWindow?,
        input: Input,
        percentStyle: PercentStyle) -> Metric
    {
        guard let window else {
            let placeholderPercent = input.usageBarsShowUsed ? 100.0 : 0.0
            return Metric(
                id: id,
                title: title,
                percent: placeholderPercent,
                percentStyle: percentStyle,
                statusText: nil,
                resetText: nil,
                detailText: nil,
                detailLeftText: nil,
                detailRightText: nil,
                pacePercent: nil,
                paceOnTop: true)
        }
        let percent = input.usageBarsShowUsed ? window.usedPercent : window.remainingPercent
        return Metric(
            id: id,
            title: title,
            percent: Self.clamped(percent),
            percentStyle: percentStyle,
            resetText: Self.resetText(for: window, style: input.resetTimeDisplayStyle, now: input.now),
            detailText: nil,
            detailLeftText: nil,
            detailRightText: nil,
            pacePercent: nil,
            paceOnTop: true)
    }

    private static func zaiLimitDetailText(limit: ZaiLimitEntry?) -> String? {
        guard let limit else { return nil }

        var parts: [String] = []
        if let currentValue = limit.currentValue,
           let usage = limit.usage,
           let remaining = limit.remaining
        {
            let currentStr = UsageFormatter.tokenCountString(currentValue)
            let usageStr = UsageFormatter.tokenCountString(usage)
            let remainingStr = UsageFormatter.tokenCountString(remaining)
            parts.append("\(currentStr) / \(usageStr) (\(remainingStr) remaining)")
        }

        if let windowLabel = limit.windowLabel {
            parts.append(windowLabel)
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func rateWindowDetailText(_ window: RateWindow) -> String? {
        let detail = window.resetDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
        if detail?.isEmpty == false {
            return detail
        }
        return Self.rateWindowLabel(minutes: window.windowMinutes)
    }

    private static func rateWindowLabel(minutes: Int?) -> String? {
        guard let minutes, minutes > 0 else { return nil }
        if minutes.isMultiple(of: 24 * 60) {
            let days = minutes / (24 * 60)
            return "\(days) \(days == 1 ? "day" : "days") window"
        }
        if minutes.isMultiple(of: 60) {
            let hours = minutes / 60
            return "\(hours) \(hours == 1 ? "hour" : "hours") window"
        }
        return "\(minutes) \(minutes == 1 ? "minute" : "minutes") window"
    }

    private static func openRouterQuotaDetail(provider: UsageProvider, snapshot: UsageSnapshot) -> String? {
        guard provider == .openrouter,
              let usage = snapshot.openRouterUsage,
              usage.hasValidKeyQuota,
              let keyRemaining = usage.keyRemaining,
              let keyLimit = usage.keyLimit
        else {
            return nil
        }

        let remaining = UsageFormatter.usdString(keyRemaining)
        let limit = UsageFormatter.usdString(keyLimit)
        return "\(remaining)/\(limit) left"
    }

    private struct PaceDetail {
        let leftLabel: String
        let rightLabel: String?
        let pacePercent: Double?
        let paceOnTop: Bool
    }

    private static func weeklyPaceDetail(
        window: RateWindow,
        now: Date,
        pace: UsagePace?,
        showUsed: Bool) -> PaceDetail?
    {
        guard let pace else { return nil }
        let detail = UsagePaceText.weeklyDetail(pace: pace, now: now)
        let expectedUsed = detail.expectedUsedPercent
        let actualUsed = window.usedPercent
        let expectedPercent = showUsed ? expectedUsed : (100 - expectedUsed)
        let actualPercent = showUsed ? actualUsed : (100 - actualUsed)
        if expectedPercent.isFinite == false || actualPercent.isFinite == false { return nil }
        let paceOnTop = actualUsed <= expectedUsed
        let pacePercent: Double? = if detail.stage == .onTrack { nil } else { expectedPercent }
        return PaceDetail(
            leftLabel: detail.leftLabel,
            rightLabel: detail.rightLabel,
            pacePercent: pacePercent,
            paceOnTop: paceOnTop)
    }

    private static func creditsLine(
        metadata: ProviderMetadata,
        credits: CreditsSnapshot?,
        error: String?) -> String?
    {
        guard metadata.supportsCredits else { return nil }
        if let credits {
            return UsageFormatter.creditsString(from: credits.remaining)
        }
        if let error, !error.isEmpty {
            return error.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return metadata.creditsHint
    }

    private static func dashboardHint(error: String?) -> String? {
        guard let error, !error.isEmpty else { return nil }
        return error
    }

    private static func tokenUsageSection(input: Input) -> TokenUsageSection? {
        if input.provider == .cursor {
            if let summaries = input.snapshot?.cursorRangeSummaries, !summaries.isEmpty {
                let selectedKind = input.cursorUsageRangeKind
                let summary = summaries.first { $0.rangeKind == selectedKind }
                    ?? summaries.first { $0.rangeKind == .billingCycle }
                    ?? summaries[0]
                let quotaSummary = input.snapshot?.cursorRequests?.summaryText
                let rangePresentations = Dictionary(uniqueKeysWithValues: summaries.map { rangeSummary in
                    (
                        rangeSummary.rangeKind,
                        Self.cursorRangePresentation(summary: rangeSummary, quotaSummary: quotaSummary))
                })
                let presentation = rangePresentations[summary.rangeKind]
                    ?? Self.cursorRangePresentation(summary: summary, quotaSummary: quotaSummary)

                return TokenUsageSection(
                    title: "Tokens",
                    sessionLine: presentation.sessionLine,
                    monthLine: presentation.monthLine,
                    detailLines: [],
                    cursorRequestRange: presentation.cursorRequestRange,
                    cursorRequestDetails: presentation.cursorRequestDetails,
                    selectedCursorRangeKind: summary.rangeKind,
                    availableCursorRangeKinds: CursorUsageRangeKind.allCases,
                    cursorRangePresentations: rangePresentations,
                    selectCursorRange: input.selectCursorUsageRange,
                    cursorRequestNow: input.now,
                    renewalLine: nil,
                    hintLine: nil,
                    errorLine: nil,
                    errorCopyText: nil)
            }

            let cycleFromAPI = input.snapshot?.cursorTokenUsage?.billingCycleTokensUsed
            let cycleFromEvents = input.snapshot?.cursorRecentRequests?.reduce(0) { $0 + $1.tokens }
            let cycleTokens: Int? = if let cycleFromAPI, cycleFromAPI > 0 {
                cycleFromAPI
            } else if let cycleFromEvents, cycleFromEvents > 0 {
                cycleFromEvents
            } else {
                cycleFromAPI
            }
            let quotaSummary = input.snapshot?.cursorRequests?.summaryText
            let cachedRecentRequests = input.snapshot?.cursorRecentRequests ?? []
            let recentRequests = Array(cachedRecentRequests.prefix(30))
            let last30DaysRequests = Self.cursorLast30DaysRequests(cachedRecentRequests, now: input.now)
            let hasCompleteLast30DaysAggregate = last30DaysRequests.count < 30
            let last30DaysTokens = hasCompleteLast30DaysAggregate
                ? Self.cursorRequestTokens(last30DaysRequests)
                : nil
            let last30DaysCost = hasCompleteLast30DaysAggregate
                ? CursorRequestCostEstimator.summarizedEstimate(for: last30DaysRequests)
                : nil
            let selectedKind = input.cursorUsageRangeKind
            let selectedRequests = selectedKind == .last30Days ? last30DaysRequests : recentRequests
            let selectedRange = selectedKind == .last30Days
                ? Self.cursorLast30DaysRange(now: input.now)
                : input.snapshot?.cursorRecentRequestRange
            let fallbackTokens = selectedKind == .last30Days
                ? last30DaysTokens
                : cycleTokens
            let cycleCostSummary = input.snapshot?.cursorRecentRequests
                .flatMap(CursorRequestCostEstimator.summarizedEstimate(for:)) ?? input.snapshot?
                .cursorTokenUsage?.requestCostSummary
            let fallbackCost = selectedKind == .last30Days
                ? last30DaysCost
                : cycleCostSummary
            guard cycleTokens != nil || quotaSummary != nil || !recentRequests.isEmpty else { return nil }

            let rangePresentations: [CursorUsageRangeKind: TokenUsageSection.CursorRangePresentation] = [
                .billingCycle: Self.cursorFallbackRangePresentation(.init(
                    rangeKind: .billingCycle,
                    quotaSummary: quotaSummary,
                    tokens: cycleTokens,
                    costSummary: cycleCostSummary,
                    requests: recentRequests,
                    range: input.snapshot?.cursorRecentRequestRange)),
                .last30Days: Self.cursorFallbackRangePresentation(.init(
                    rangeKind: .last30Days,
                    quotaSummary: nil,
                    tokens: last30DaysTokens,
                    costSummary: last30DaysCost,
                    requests: last30DaysRequests,
                    range: Self.cursorLast30DaysRange(now: input.now))),
            ]
            let presentation = rangePresentations[selectedKind] ?? Self.cursorFallbackRangePresentation(.init(
                rangeKind: selectedKind,
                quotaSummary: selectedKind == .billingCycle ? quotaSummary : nil,
                tokens: fallbackTokens,
                costSummary: fallbackCost,
                requests: selectedRequests,
                range: selectedRange))

            return TokenUsageSection(
                title: "Tokens",
                sessionLine: presentation.sessionLine,
                monthLine: presentation.monthLine,
                detailLines: [],
                cursorRequestRange: presentation.cursorRequestRange,
                cursorRequestDetails: presentation.cursorRequestDetails,
                selectedCursorRangeKind: selectedKind,
                availableCursorRangeKinds: CursorUsageRangeKind.allCases,
                cursorRangePresentations: rangePresentations,
                selectCursorRange: input.selectCursorUsageRange,
                cursorRequestNow: input.now,
                renewalLine: nil,
                hintLine: nil,
                errorLine: nil,
                errorCopyText: nil)
        }

        guard input.provider == .codex || input.provider == .claude || input.provider == .vertexai else { return nil }
        guard input.tokenCostUsageEnabled else { return nil }
        guard let snapshot = input.tokenSnapshot else { return nil }

        let sessionCost = snapshot.sessionCostUSD.map { UsageFormatter.usdString($0) } ?? "—"
        let sessionTokens = snapshot.sessionTokens.map { UsageFormatter.tokenCountString($0) }
        let sessionLine: String = {
            if let sessionTokens {
                return "Today: \(sessionCost) · \(sessionTokens) tokens"
            }
            return "Today: \(sessionCost)"
        }()

        let monthCost = snapshot.last30DaysCostUSD.map { UsageFormatter.usdString($0) } ?? "—"
        let fallbackTokens = snapshot.daily.compactMap(\.totalTokens).reduce(0, +)
        let monthTokensValue = snapshot.last30DaysTokens ?? (fallbackTokens > 0 ? fallbackTokens : nil)
        let monthTokens = monthTokensValue.map { UsageFormatter.tokenCountString($0) }
        let monthLine: String = {
            if let monthTokens {
                return "Last 30 days: \(monthCost) · \(monthTokens) tokens"
            }
            return "Last 30 days: \(monthCost)"
        }()
        let err = (input.tokenError?.isEmpty ?? true) ? nil : input.tokenError
        return TokenUsageSection(
            title: "Cost",
            sessionLine: sessionLine,
            monthLine: monthLine,
            renewalLine: Self.tokenUsageRenewalLine(provider: input.provider, snapshot: input.snapshot, now: input.now),
            hintLine: nil,
            errorLine: err,
            errorCopyText: (input.tokenError?.isEmpty ?? true) ? nil : input.tokenError)
    }

    private static func tokenUsageRenewalLine(provider: UsageProvider, snapshot: UsageSnapshot?, now: Date) -> String? {
        guard provider == .codex,
              let renewal = snapshot?.codexUsage?.subscriptionRenewalAt
        else { return nil }
        return "Monthly renews \(UsageFormatter.resetDescription(from: renewal, now: now))"
    }

    private static func cursorRangePresentation(
        summary: CursorRangeUsageSummary,
        quotaSummary: String?) -> TokenUsageSection.CursorRangePresentation
    {
        let tokensText = "\(summary.rangeKind.label): \(UsageFormatter.tokenCountString(summary.tokens)) tokens"
        let costText = UsageFormatter.cursorEstimatedTotalText(summary.requestCostSummary)
        let tokenLine = costText.map { "\(tokensText) · \($0)" } ?? tokensText
        if summary.rangeKind == .billingCycle, quotaSummary == nil {
            let requestText = summary.weightedRequestCost > 0
                ? " · Req \(UsageFormatter.cursorRequestCostString(summary.weightedRequestCost))"
                : ""
            return TokenUsageSection.CursorRangePresentation(
                sessionLine: "\(tokenLine)\(requestText)",
                monthLine: nil,
                cursorRequestRange: summary.range,
                cursorRequestDetails: summary.recentRequests)
        }
        let sessionLine = if summary.rangeKind == .billingCycle, let quotaSummary {
            quotaSummary
        } else {
            "Requests: \(UsageFormatter.cursorRequestCostString(summary.weightedRequestCost))"
        }
        return TokenUsageSection.CursorRangePresentation(
            sessionLine: sessionLine,
            monthLine: tokenLine,
            cursorRequestRange: summary.range,
            cursorRequestDetails: summary.recentRequests)
    }

    private struct CursorFallbackRangePresentationInput {
        let rangeKind: CursorUsageRangeKind
        let quotaSummary: String?
        let tokens: Int?
        let costSummary: CursorRequestCostSummary?
        let requests: [CursorRecentRequest]
        let range: CursorRecentRequestRange?
    }

    private static func cursorFallbackRangePresentation(
        _ input: CursorFallbackRangePresentationInput) -> TokenUsageSection.CursorRangePresentation
    {
        let monthLine = input.tokens.flatMap { tokenCount -> String? in
            guard tokenCount > 0 else { return nil }
            let tokensText = "\(input.rangeKind.label): \(UsageFormatter.tokenCountString(tokenCount)) tokens"
            return UsageFormatter.cursorEstimatedTotalText(input.costSummary)
                .map { "\(tokensText) · \($0)" }
                ?? tokensText
        }
        let sessionLine: String
        if input.rangeKind == .billingCycle, let quotaSummary = input.quotaSummary {
            sessionLine = quotaSummary
        } else if input.rangeKind == .last30Days {
            let suffix = input.requests.count >= 30 ? "+" : ""
            let requestCost = input.requests.reduce(0) { $0 + ($1.requestCost ?? Double($1.requests)) }
            sessionLine = "Requests: \(UsageFormatter.cursorRequestCostString(requestCost))\(suffix)"
        } else if let monthLine {
            sessionLine = monthLine
        } else {
            sessionLine = "Recent requests"
        }
        let shouldShowMonthLine = input.rangeKind == .last30Days ||
            (input.rangeKind == .billingCycle && input.quotaSummary != nil)
        return TokenUsageSection.CursorRangePresentation(
            sessionLine: sessionLine,
            monthLine: shouldShowMonthLine ? monthLine : nil,
            cursorRequestRange: input.range,
            cursorRequestDetails: input.requests)
    }

    private static func cursorLast30DaysRange(now: Date) -> CursorRecentRequestRange {
        CursorRecentRequestRange(
            start: now.addingTimeInterval(-30 * 24 * 60 * 60),
            end: now)
    }

    private static func cursorLast30DaysRequests(
        _ requests: [CursorRecentRequest],
        now: Date) -> [CursorRecentRequest]
    {
        let cutoff = now.addingTimeInterval(-30 * 24 * 60 * 60)
        return Array(requests.filter { $0.timestamp >= cutoff }.prefix(30))
    }

    private static func cursorRequestTokens(_ requests: [CursorRecentRequest]) -> Int? {
        let tokens = requests.reduce(0) { $0 + $1.tokens }
        return tokens > 0 ? tokens : nil
    }

    private static func cursorRequestRange(for requests: [CursorRecentRequest]) -> CursorRecentRequestRange? {
        guard let first = requests.first else { return nil }
        let timestamps = requests.map(\.timestamp)
        return CursorRecentRequestRange(
            start: timestamps.min() ?? first.timestamp,
            end: timestamps.max() ?? first.timestamp)
    }

    private static func providerCostSection(
        provider: UsageProvider,
        cost: ProviderCostSnapshot?,
        now: Date) -> ProviderCostSection?
    {
        guard let cost else { return nil }
        guard cost.limit > 0 else { return nil }

        let used: String
        let limit: String
        let title: String

        if cost.currencyCode == "Quota" {
            title = "Quota usage"
            used = String(format: "%.0f", cost.used)
            limit = String(format: "%.0f", cost.limit)
        } else {
            title = "Extra usage"
            used = UsageFormatter.currencyString(cost.used, currencyCode: cost.currencyCode)
            limit = UsageFormatter.currencyString(cost.limit, currencyCode: cost.currencyCode)
        }

        let percentUsed = Self.clamped((cost.used / cost.limit) * 100)
        let periodLabel = cost.period ?? "This month"

        return ProviderCostSection(
            title: title,
            percentUsed: percentUsed,
            spendLine: "\(periodLabel): \(used) / \(limit)",
            renewalLine: Self.providerCostRenewalLine(period: cost.period, renewal: cost.resetsAt, now: now))
    }

    private static func providerCostRenewalLine(period: String?, renewal: Date?, now: Date) -> String? {
        guard let renewal else { return nil }
        let periodText = period?.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = if let periodText, !periodText.isEmpty {
            "\(periodText) renews"
        } else {
            "Renews"
        }
        return "\(prefix) \(UsageFormatter.resetDescription(from: renewal, now: now))"
    }

    private static func clamped(_ value: Double) -> Double {
        min(100, max(0, value))
    }

    private static func progressColor(for provider: UsageProvider) -> Color {
        let color = ProviderDescriptorRegistry.descriptor(for: provider).branding.color
        return Color(red: color.red, green: color.green, blue: color.blue)
    }

    private static func resetText(
        for window: RateWindow,
        style: ResetTimeDisplayStyle,
        now: Date) -> String?
    {
        UsageFormatter.resetLine(for: window, style: style, now: now)
    }
}
