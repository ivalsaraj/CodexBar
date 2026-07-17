import CodexBarCore
import SwiftUI

struct TokenUsageContentView: View {
    let provider: UsageProvider
    let tokenUsage: UsageMenuCardView.Model.TokenUsageSection
    let lineFont: Font
    let detailFont: Font
    @Environment(\.menuItemHighlighted) private var isHighlighted
    @State private var selectedCursorRangeKind: CursorUsageRangeKind?

    private var effectiveCursorRangeKind: CursorUsageRangeKind? {
        self.selectedCursorRangeKind ?? self.tokenUsage.selectedCursorRangeKind
    }

    private var cursorPresentation: UsageMenuCardView.Model.TokenUsageSection.CursorRangePresentation? {
        guard let effectiveCursorRangeKind else { return nil }
        return self.tokenUsage.cursorRangePresentations[effectiveCursorRangeKind]
    }

    private var visibleTokenUsage: UsageMenuCardView.Model.TokenUsageSection {
        guard let cursorPresentation else { return self.tokenUsage }
        return UsageMenuCardView.Model.TokenUsageSection(
            title: self.tokenUsage.title,
            sessionLine: cursorPresentation.sessionLine,
            monthLine: cursorPresentation.monthLine,
            detailLines: self.tokenUsage.detailLines,
            cursorRequestRange: cursorPresentation.cursorRequestRange,
            cursorRequestDetails: cursorPresentation.cursorRequestDetails,
            selectedCursorRangeKind: self.effectiveCursorRangeKind,
            availableCursorRangeKinds: self.tokenUsage.availableCursorRangeKinds,
            cursorRangePresentations: self.tokenUsage.cursorRangePresentations,
            selectCursorRange: self.tokenUsage.selectCursorRange,
            cursorRequestNow: self.tokenUsage.cursorRequestNow,
            renewalLine: self.tokenUsage.renewalLine,
            hintLine: self.tokenUsage.hintLine,
            errorLine: self.tokenUsage.errorLine,
            errorCopyText: self.tokenUsage.errorCopyText)
    }

    var body: some View {
        let visible = self.visibleTokenUsage
        VStack(alignment: .leading, spacing: 6) {
            TokenUsageTitleRow(
                tokenUsage: visible,
                selectedCursorRangeKind: self.effectiveCursorRangeKind,
                selectCursorRange: { range in
                    self.selectedCursorRangeKind = range
                    self.tokenUsage.selectCursorRange?(range)
                })
            Text(visible.sessionLine)
                .font(self.lineFont)
            if let monthLine = visible.monthLine {
                Text(monthLine)
                    .font(self.lineFont)
            }
            TokenUsageDetailLinesView(
                provider: self.provider,
                tokenUsage: visible,
                font: self.detailFont)
            if let renewalLine = visible.renewalLine {
                Text(renewalLine)
                    .font(.footnote)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            }
            if let hint = visible.hintLine, !hint.isEmpty {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = visible.errorLine, !error.isEmpty {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(MenuHighlightStyle.error(self.isHighlighted))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .overlay {
                        ClickToCopyOverlay(copyText: visible.errorCopyText ?? error)
                    }
            }
        }
    }
}
