import AppKit
import CodexBarCore
import SwiftUI

/// One compact two-line request row for the menu. Expanded detail lines are click-accessible; `help`
/// remains a best-effort duplicate for hover.
struct CursorMenuRequestRowPresentation: Equatable, Identifiable {
    let id: String
    let primaryLeft: String
    let primaryRight: String
    let secondaryLeft: String
    let secondaryRight: String?
    let detailLines: [String]
    let help: String

    static func make(request: CursorRecentRequest, index: Int, now: Date) -> Self {
        let normalized = CursorModelNormalizer.normalize(request.model)
        let estimate = CursorRequestCostEstimator.estimate(for: request)
        let timestamp = UsageFormatter.cursorRequestRowTimestamp(request.timestamp)
        let requestLabel = UsageFormatter.cursorRequestCountLabel(
            requests: request.requests,
            requestCost: request.requestCost)
        let detailLines = UsageFormatter.cursorRequestDetailLines(
            request: request,
            estimate: estimate,
            now: now)
        return CursorMenuRequestRowPresentation(
            id: "\(index)-\(request.timestamp.timeIntervalSince1970)-\(request.model)",
            primaryLeft: UsageFormatter.cursorCompactModelLabel(normalized),
            primaryRight: UsageFormatter.tokenCountString(request.tokens),
            secondaryLeft: "\(timestamp) · \(requestLabel)",
            secondaryRight: UsageFormatter.cursorEstimateText(estimate),
            detailLines: detailLines,
            help: detailLines.joined(separator: "\n"))
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
    @State private var expandedRequestID: String?

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
                .contentShape(Rectangle())
                .onTapGesture {
                    self.expandedRequestID = self.expandedRequestID == row.id ? nil : row.id
                }

                if self.expandedRequestID == row.id {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(row.detailLines, id: \.self) { detail in
                            Text(detail)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .font(self.font)
            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(row.help)
        }
    }
}
