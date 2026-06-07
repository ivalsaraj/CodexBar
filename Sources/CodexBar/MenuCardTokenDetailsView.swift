import AppKit
import CodexBarCore
import SwiftUI

/// One compact two-line request row for the menu. The raw model and full breakdown live in `help`
/// so long model strings never break the row layout.
struct CursorMenuRequestRowPresentation: Equatable, Identifiable {
    let id: String
    let primaryLeft: String
    let primaryRight: String
    let secondaryLeft: String
    let secondaryRight: String?
    let help: String

    static func make(request: CursorRecentRequest, index: Int, now: Date) -> Self {
        let normalized = CursorModelNormalizer.normalize(request.model)
        let estimate = CursorRequestCostEstimator.estimate(for: request)
        let time = request.timestamp.formatted(date: .omitted, time: .shortened)
        let requestLabel = request.requests == 1 ? "Req 1" : "Req \(request.requests)"
        return CursorMenuRequestRowPresentation(
            id: "\(index)-\(request.timestamp.timeIntervalSince1970)-\(request.model)",
            primaryLeft: UsageFormatter.cursorCompactModelLabel(normalized),
            primaryRight: UsageFormatter.tokenCountString(request.tokens),
            secondaryLeft: "\(time) · \(requestLabel)",
            secondaryRight: UsageFormatter.cursorEstimateText(estimate),
            help: UsageFormatter.cursorRequestHelpText(request: request, estimate: estimate))
    }
}

struct CursorMenuRequestDetailPresentation: Equatable {
    static let maxVisibleRequestRows = 7
    static let rowHeight: CGFloat = 34
    static let scrollHeight = CGFloat(Self.maxVisibleRequestRows) * Self.rowHeight

    let fixedRows: [String]
    let requestRows: [CursorMenuRequestRowPresentation]

    init(range: CursorRecentRequestRange?, requests: [CursorRecentRequest], now: Date) {
        self.fixedRows = range.map { [UsageFormatter.cursorRecentRequestRangeLine($0)] } ?? []
        self.requestRows = requests.enumerated().map { index, request in
            CursorMenuRequestRowPresentation.make(request: request, index: index, now: now)
        }
    }

    var shouldScroll: Bool {
        self.requestRows.count > Self.maxVisibleRequestRows
    }
}

struct TokenUsageDetailLinesView: View {
    let provider: UsageProvider
    let tokenUsage: UsageMenuCardView.Model.TokenUsageSection
    let font: Font
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        if self.provider == .cursor, !self.tokenUsage.cursorRequestDetails.isEmpty {
            let presentation = CursorMenuRequestDetailPresentation(
                range: self.tokenUsage.cursorRequestRange,
                requests: self.tokenUsage.cursorRequestDetails,
                now: self.tokenUsage.cursorRequestNow ?? Date())
            VStack(alignment: .leading, spacing: 6) {
                self.stringRows(presentation.fixedRows)
                if presentation.shouldScroll {
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 6) {
                            self.requestRows(presentation.requestRows)
                        }
                    }
                    .frame(height: CursorMenuRequestDetailPresentation.scrollHeight)
                    .clipped()
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        self.requestRows(presentation.requestRows)
                    }
                }
            }
        } else {
            self.stringRows(self.tokenUsage.detailLines)
        }
    }

    private func stringRows(_ lines: [String]) -> some View {
        ForEach(lines, id: \.self) { line in
            Text(line)
                .font(self.font)
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func requestRows(_ rows: [CursorMenuRequestRowPresentation]) -> some View {
        ForEach(rows) { row in
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(row.primaryLeft)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 6)
                    Text(row.primaryRight)
                        .monospacedDigit()
                        .layoutPriority(1)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(row.secondaryLeft)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    if let secondaryRight = row.secondaryRight {
                        Text(secondaryRight)
                            .monospacedDigit()
                            .layoutPriority(1)
                    }
                }
            }
            .font(self.font)
            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            .help(row.help)
        }
    }
}
