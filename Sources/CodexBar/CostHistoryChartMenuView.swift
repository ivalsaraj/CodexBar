import Charts
import CodexBarCore
import Foundation
import SwiftUI

struct CostHistoryModelColor: Equatable, Hashable {
    let red: Double
    let green: Double
    let blue: Double
}

enum CostHistoryModelColorPolicy {
    static let basePalette = [
        CostHistoryModelColor(red: 76.0 / 255.0, green: 139.0 / 255.0, blue: 245.0 / 255.0),
        CostHistoryModelColor(red: 192.0 / 255.0, green: 107.0 / 255.0, blue: 224.0 / 255.0),
        CostHistoryModelColor(red: 70.0 / 255.0, green: 194.0 / 255.0, blue: 210.0 / 255.0),
        CostHistoryModelColor(red: 96.0 / 255.0, green: 187.0 / 255.0, blue: 120.0 / 255.0),
        CostHistoryModelColor(red: 242.0 / 255.0, green: 140.0 / 255.0, blue: 56.0 / 255.0),
        CostHistoryModelColor(red: 234.0 / 255.0, green: 102.0 / 255.0, blue: 140.0 / 255.0),
        CostHistoryModelColor(red: 105.0 / 255.0, green: 112.0 / 255.0, blue: 219.0 / 255.0),
        CostHistoryModelColor(red: 69.0 / 255.0, green: 185.0 / 255.0, blue: 169.0 / 255.0),
        CostHistoryModelColor(red: 228.0 / 255.0, green: 92.0 / 255.0, blue: 92.0 / 255.0),
        CostHistoryModelColor(red: 152.0 / 255.0, green: 116.0 / 255.0, blue: 216.0 / 255.0),
        CostHistoryModelColor(red: 90.0 / 255.0, green: 183.0 / 255.0, blue: 232.0 / 255.0),
        CostHistoryModelColor(red: 232.0 / 255.0, green: 121.0 / 255.0, blue: 94.0 / 255.0),
    ]
    static let unattributedColor = CostHistoryModelColor(
        red: 139.0 / 255.0,
        green: 144.0 / 255.0,
        blue: 152.0 / 255.0)

    static func colors(for identities: Set<CostHistoryChartDataPolicy.Identity>)
        -> [CostHistoryChartDataPolicy.Identity: CostHistoryModelColor]
    {
        let models = identities.compactMap(\.modelName).sorted()
        var colors: [CostHistoryChartDataPolicy.Identity: CostHistoryModelColor] = [:]
        if identities.contains(.unattributed) {
            colors[.unattributed] = self.unattributedColor
        }

        var available = Set(self.basePalette.indices)
        var overflowModels: [String] = []
        for model in models {
            guard !available.isEmpty else {
                overflowModels.append(model)
                continue
            }

            let start = Int(self.fnv1a64(model) % UInt64(self.basePalette.count))
            for offset in self.basePalette.indices {
                let index = (start + offset) % self.basePalette.count
                if available.remove(index) != nil {
                    colors[.model(model)] = self.basePalette[index]
                    break
                }
            }
        }

        for (index, model) in overflowModels.enumerated() {
            colors[.model(model)] = self.overflowColor(index: index, count: overflowModels.count)
        }
        return colors
    }

    private static func fnv1a64(_ value: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return hash
    }

    private static func overflowColor(index: Int, count: Int) -> CostHistoryModelColor {
        let slotWidth = 330.0 / Double(count)
        let position = (Double(index) + 0.5) * slotWidth
        let hue = position < 45 ? position : position + 30
        return self.hslColor(hue: hue, saturation: 0.65, lightness: 0.68)
    }

    private static func hslColor(hue: Double, saturation: Double, lightness: Double) -> CostHistoryModelColor {
        let chroma = (1 - abs((2 * lightness) - 1)) * saturation
        let x = chroma * (1 - abs((hue / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = lightness - (chroma / 2)
        let components: (Double, Double, Double) = switch hue {
        case 0..<60: (chroma, x, 0)
        case 60..<120: (x, chroma, 0)
        case 120..<180: (0, chroma, x)
        case 180..<240: (0, x, chroma)
        case 240..<300: (x, 0, chroma)
        default: (chroma, 0, x)
        }
        return CostHistoryModelColor(
            red: components.0 + m,
            green: components.1 + m,
            blue: components.2 + m)
    }
}

enum CostHistoryChartDataPolicy {
    enum Identity: Hashable, Comparable {
        case model(String)
        case unattributed

        var modelName: String? {
            guard case let .model(name) = self else { return nil }
            return name
        }

        var displayName: String {
            switch self {
            case let .model(name): UsageFormatter.modelDisplayName(name)
            case .unattributed: "Unattributed"
            }
        }

        var chartKey: String {
            switch self {
            case let .model(name): "model:\(name)"
            case .unattributed: "unattributed"
            }
        }

        static func < (lhs: Identity, rhs: Identity) -> Bool {
            lhs.chartKey < rhs.chartKey
        }
    }

    struct DatePoint: Identifiable {
        let key: String
        let date: Date

        var id: String {
            self.key
        }
    }

    struct Segment: Identifiable {
        let dateKey: String
        let date: Date
        let identity: Identity
        let costUSD: Double

        var id: String {
            "\(self.dateKey)-\(self.identity.chartKey)"
        }
    }

    struct TokenActivitySegment: Identifiable {
        let dateKey: String
        let date: Date
        let identity: Identity
        let share: Double

        var id: String {
            "token-\(self.dateKey)-\(self.identity.chartKey)"
        }
    }

    struct DetailRow: Identifiable {
        let identity: Identity
        let costUSD: Double?
        let totalTokens: Int?

        var id: String {
            self.identity.chartKey
        }
    }

    struct Data {
        let datePoints: [DatePoint]
        let tokenOnlyDatePoints: [DatePoint]
        let tokenActivitySegments: [TokenActivitySegment]
        let segments: [Segment]
        let periodRows: [DetailRow]
        let dailyRowsByDateKey: [String: [DetailRow]]
        let renderedTotalsByDateKey: [String: Double]
        let totalTokensByDateKey: [String: Int]
        let peakKey: String?
        let colors: [Identity: CostHistoryModelColor]
        let activityBarHeight: Double
        let chartUpperBound: Double

        var axisDates: [Date] {
            guard let first = self.datePoints.first?.date, let last = self.datePoints.last?.date else { return [] }
            return Calendar.current.isDate(first, inSameDayAs: last) ? [first] : [first, last]
        }
    }

    private struct DailyData {
        let shouldInclude: Bool
        let hasPositiveTokens: Bool
        let rows: [DetailRow]
        let segments: [(identity: Identity, costUSD: Double)]
        let renderedCost: Double
    }

    private struct Totals {
        var hasKnownCost = false
        var costUSD = 0.0
        var hasKnownTokens = false
        var totalTokens = 0

        mutating func add(costUSD: Double?, totalTokens: Int?) {
            if let costUSD, costUSD.isFinite, costUSD >= 0 {
                self.hasKnownCost = true
                self.costUSD += costUSD
            }
            if let totalTokens, totalTokens >= 0 {
                self.hasKnownTokens = true
                self.totalTokens += totalTokens
            }
        }
    }

    static func build(daily: [CostUsageDailyReport.Entry]) -> Data {
        let sorted = daily.sorted { $0.date < $1.date }
        var datePoints: [DatePoint] = []
        var tokenOnlyDatePoints: [DatePoint] = []
        var tokenActivitySegments: [TokenActivitySegment] = []
        var segments: [Segment] = []
        var dailyRowsByDateKey: [String: [DetailRow]] = [:]
        var renderedTotalsByDateKey: [String: Double] = [:]
        var totalTokensByDateKey: [String: Int] = [:]
        var periodTotals: [Identity: Totals] = [:]
        var peakKey: String?
        var peakCost = 0.0

        for entry in sorted {
            guard let date = self.dateFromDayKey(entry.date) else { continue }
            let dailyData = self.dailyData(for: entry)
            guard dailyData.shouldInclude else { continue }

            let point = DatePoint(key: entry.date, date: date)
            datePoints.append(point)
            if dailyData.renderedCost == 0, dailyData.hasPositiveTokens {
                tokenOnlyDatePoints.append(point)
                let activityRows = dailyData.rows.compactMap { row -> (Identity, Int)? in
                    guard let totalTokens = row.totalTokens, totalTokens > 0 else { return nil }
                    return (row.identity, totalTokens)
                }
                let totalTokens = activityRows.reduce(0) { $0 + $1.1 }
                if totalTokens > 0 {
                    for (identity, tokens) in activityRows {
                        tokenActivitySegments.append(TokenActivitySegment(
                            dateKey: entry.date,
                            date: date,
                            identity: identity,
                            share: Double(tokens) / Double(totalTokens)))
                    }
                } else {
                    tokenActivitySegments.append(TokenActivitySegment(
                        dateKey: entry.date,
                        date: date,
                        identity: .unattributed,
                        share: 1))
                }
            }
            dailyRowsByDateKey[entry.date] = dailyData.rows
            renderedTotalsByDateKey[entry.date] = dailyData.renderedCost
            totalTokensByDateKey[entry.date] = entry.totalTokens.flatMap { $0 >= 0 ? $0 : nil }

            for row in dailyData.rows {
                var total = periodTotals[row.identity] ?? Totals()
                total.add(costUSD: row.costUSD, totalTokens: row.identity == .unattributed ? nil : row.totalTokens)
                periodTotals[row.identity] = total
            }
            for segment in dailyData.segments {
                segments.append(Segment(
                    dateKey: entry.date,
                    date: date,
                    identity: segment.identity,
                    costUSD: segment.costUSD))
            }
            if dailyData.renderedCost > peakCost {
                peakCost = dailyData.renderedCost
                peakKey = entry.date
            }
        }

        let periodRows = self.sortedRows(periodTotals.map { identity, total in
            DetailRow(
                identity: identity,
                costUSD: total.hasKnownCost ? total.costUSD : nil,
                totalTokens: identity == .unattributed ? nil : (total.hasKnownTokens ? total.totalTokens : nil))
        })
        let identities = Set(periodRows.map(\.identity)).union(tokenActivitySegments.map(\.identity))
        let maxRenderedCost = renderedTotalsByDateKey.values.max() ?? 0
        let chartUpperBound = maxRenderedCost > 0 ? maxRenderedCost * 1.05 : 1
        return Data(
            datePoints: datePoints,
            tokenOnlyDatePoints: tokenOnlyDatePoints,
            tokenActivitySegments: tokenActivitySegments,
            segments: segments,
            periodRows: periodRows,
            dailyRowsByDateKey: dailyRowsByDateKey,
            renderedTotalsByDateKey: renderedTotalsByDateKey,
            totalTokensByDateKey: totalTokensByDateKey,
            peakKey: peakKey,
            colors: CostHistoryModelColorPolicy.colors(for: identities),
            activityBarHeight: chartUpperBound * 0.035,
            chartUpperBound: chartUpperBound)
    }

    private static func dailyData(for entry: CostUsageDailyReport.Entry) -> DailyData {
        var totals: [Identity: Totals] = [:]
        for model in entry.modelsUsed ?? [] {
            let name = model.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            totals[.model(name)] = totals[.model(name)] ?? Totals()
        }

        var breakdownCost = 0.0
        var unattributedCost = 0.0
        var hasPositiveUnattributedTokens = false
        for breakdown in entry.modelBreakdowns ?? [] {
            let name = breakdown.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
            let cost = self.validCost(breakdown.costUSD)
            let tokens = self.validTokens(breakdown.totalTokens)
            guard !name.isEmpty else {
                if let tokens, tokens > 0 {
                    hasPositiveUnattributedTokens = true
                }
                if let cost, cost > 0 {
                    breakdownCost += cost
                    unattributedCost += cost
                }
                continue
            }

            var total = totals[.model(name)] ?? Totals()
            total.add(costUSD: cost, totalTokens: tokens)
            totals[.model(name)] = total
            if let cost, cost > 0 {
                breakdownCost += cost
            }
        }

        if let aggregate = self.validCost(entry.costUSD) {
            let tolerance = max(0.000_001, aggregate * 0.000_000_001)
            if aggregate - breakdownCost > tolerance {
                unattributedCost += aggregate - breakdownCost
            }
        }
        if unattributedCost > 0 {
            var unattributed = totals[.unattributed] ?? Totals()
            unattributed.add(costUSD: unattributedCost, totalTokens: nil)
            totals[.unattributed] = unattributed
        }

        let rows = self.sortedRows(totals.map { identity, total in
            DetailRow(
                identity: identity,
                costUSD: total.hasKnownCost ? total.costUSD : nil,
                totalTokens: identity == .unattributed ? nil : (total.hasKnownTokens ? total.totalTokens : nil))
        })
        let segments = rows.compactMap { row -> (identity: Identity, costUSD: Double)? in
            guard let costUSD = row.costUSD, costUSD > 0 else { return nil }
            return (row.identity, costUSD)
        }
        let renderedCost = segments.reduce(0) { $0 + $1.costUSD }
        let hasPositiveEntryTokens = [
            entry.totalTokens,
            entry.inputTokens,
            entry.outputTokens,
            entry.cacheReadTokens,
            entry.cacheCreationTokens,
        ].contains { ($0 ?? 0) > 0 }
        let hasPositiveTokens = hasPositiveEntryTokens ||
            hasPositiveUnattributedTokens ||
            rows.contains { ($0.totalTokens ?? 0) > 0 }
        let shouldInclude = self.validCost(entry.costUSD) != nil || hasPositiveTokens || renderedCost > 0
        return DailyData(
            shouldInclude: shouldInclude,
            hasPositiveTokens: hasPositiveTokens,
            rows: rows,
            segments: segments,
            renderedCost: renderedCost)
    }

    private static func validCost(_ costUSD: Double?) -> Double? {
        guard let costUSD, costUSD.isFinite, costUSD >= 0 else { return nil }
        return costUSD
    }

    private static func validTokens(_ totalTokens: Int?) -> Int? {
        guard let totalTokens, totalTokens >= 0 else { return nil }
        return totalTokens
    }

    private static func sortedRows(_ rows: [DetailRow]) -> [DetailRow] {
        rows.sorted { lhs, rhs in
            switch (lhs.costUSD, rhs.costUSD) {
            case let (lhs?, rhs?) where lhs != rhs:
                return lhs > rhs
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            default:
                break
            }

            switch (lhs.totalTokens, rhs.totalTokens) {
            case let (lhs?, rhs?) where lhs != rhs:
                return lhs > rhs
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            default:
                return lhs.identity < rhs.identity
            }
        }
    }

    static func dateFromDayKey(_ key: String) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else { return nil }

        var components = DateComponents()
        components.calendar = Calendar.current
        components.timeZone = TimeZone.current
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return components.date
    }
}

@MainActor
struct CostHistoryChartMenuView: View {
    typealias DailyEntry = CostUsageDailyReport.Entry

    private struct DetailRow: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let accentColor: Color
    }

    private struct DetailContent {
        let primary: String
        let rows: [DetailRow]
    }

    private let daily: [DailyEntry]
    private let totalCostUSD: Double?
    private let width: CGFloat
    @State private var selectedDateKey: String?

    init(provider _: UsageProvider, daily: [DailyEntry], totalCostUSD: Double?, width: CGFloat) {
        self.daily = daily
        self.totalCostUSD = totalCostUSD
        self.width = width
    }

    var body: some View {
        let model = CostHistoryChartDataPolicy.build(daily: self.daily)
        VStack(alignment: .leading, spacing: 10) {
            if model.datePoints.isEmpty {
                Text("No cost history data.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(model.datePoints) { point in
                        BarMark(
                            x: .value("Day", point.date, unit: .day),
                            y: .value("Cost", 0))
                            .foregroundStyle(Color.clear)
                    }
                    ForEach(model.tokenActivitySegments) { segment in
                        BarMark(
                            x: .value("Day", segment.date, unit: .day),
                            y: .value("Token activity", segment.share * model.activityBarHeight))
                            .foregroundStyle(by: .value("Model", segment.identity.chartKey))
                    }
                    ForEach(model.segments) { segment in
                        BarMark(
                            x: .value("Day", segment.date, unit: .day),
                            y: .value("Cost", segment.costUSD))
                            .foregroundStyle(by: .value("Model", segment.identity.chartKey))
                    }
                    if let peak = self.peakPoint(model: model) {
                        let total = model.renderedTotalsByDateKey[peak.key] ?? 0
                        let capStart = max(total - Self.capHeight(maxValue: total), 0)
                        BarMark(
                            x: .value("Day", peak.date, unit: .day),
                            yStart: .value("Cap start", capStart),
                            yEnd: .value("Cap end", total))
                            .foregroundStyle(Color(nsColor: .systemYellow))
                    }
                }
                .chartForegroundStyleScale(
                    domain: model.colors.keys.map(\.chartKey).sorted(),
                    range: model.colors.keys.sorted().map { self.color(for: model.colors[$0]) })
                .chartYScale(domain: 0...model.chartUpperBound)
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: model.axisDates) { _ in
                        AxisGridLine().foregroundStyle(Color.clear)
                        AxisTick().foregroundStyle(Color.clear)
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(.caption2)
                            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    }
                }
                .chartLegend(.hidden)
                .frame(height: 130)
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        ZStack(alignment: .topLeading) {
                            if let rect = self.selectionBandRect(model: model, proxy: proxy, geo: geo) {
                                Rectangle()
                                    .fill(Self.selectionBandColor)
                                    .frame(width: rect.width, height: rect.height)
                                    .position(x: rect.midX, y: rect.midY)
                                    .allowsHitTesting(false)
                            }
                            MouseLocationReader { location in
                                self.updateSelection(location: location, model: model, proxy: proxy, geo: geo)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                        }
                    }
                }

                let detail = self.detailContent(model: model)
                VStack(alignment: .leading, spacing: Self.detailSpacing) {
                    Text(detail.primary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(height: Self.detailPrimaryLineHeight, alignment: .leading)
                    ForEach(detail.rows) { row in
                        HStack(alignment: .top, spacing: 8) {
                            Rectangle()
                                .fill(row.accentColor)
                                .frame(width: 2, height: Self.detailRowHeight)
                                .padding(.top, 1)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Text(row.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                        .frame(height: Self.detailRowHeight, alignment: .leading)
                    }
                    ForEach(0..<max(model.periodRows.count - detail.rows.count, 0), id: \.self) { _ in
                        Text(" ")
                            .font(.caption)
                            .frame(height: Self.detailRowHeight, alignment: .leading)
                            .opacity(0)
                    }
                }
                .frame(height: Self.detailBlockHeight(rowCount: model.periodRows.count), alignment: .topLeading)
            }

            if let total = self.totalCostUSD {
                Text("Total (30d): \(UsageFormatter.usdString(total))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minWidth: self.width, maxWidth: .infinity, alignment: .leading)
    }

    private static let selectionBandColor = Color(nsColor: .labelColor).opacity(0.1)
    private static let detailPrimaryLineHeight: CGFloat = 16
    private static let detailRowHeight: CGFloat = 24
    private static let detailSpacing: CGFloat = 6

    private static func capHeight(maxValue: Double) -> Double {
        maxValue * 0.05
    }

    private static func detailBlockHeight(rowCount: Int) -> CGFloat {
        guard rowCount > 0 else { return self.detailPrimaryLineHeight }
        return self.detailPrimaryLineHeight +
            (CGFloat(rowCount) * self.detailRowHeight) +
            (CGFloat(rowCount) * self.detailSpacing)
    }

    private func peakPoint(model: CostHistoryChartDataPolicy.Data) -> CostHistoryChartDataPolicy.DatePoint? {
        guard let key = model.peakKey else { return nil }
        return model.datePoints.first { $0.key == key }
    }

    private func selectionBandRect(
        model: CostHistoryChartDataPolicy.Data,
        proxy: ChartProxy,
        geo: GeometryProxy) -> CGRect?
    {
        guard let key = self.selectedDateKey,
              let plotAnchor = proxy.plotFrame,
              let index = model.datePoints.firstIndex(where: { $0.key == key }),
              let x = proxy.position(forX: model.datePoints[index].date)
        else { return nil }
        let plotFrame = geo[plotAnchor]

        func xForIndex(_ index: Int) -> CGFloat? {
            guard model.datePoints.indices.contains(index) else { return nil }
            return proxy.position(forX: model.datePoints[index].date)
        }

        let previous = xForIndex(index - 1)
        let next = xForIndex(index + 1)
        let left: CGFloat = if let previous {
            (previous + x) / 2
        } else if let next {
            x - ((next - x) / 2)
        } else {
            x - 8
        }
        let right: CGFloat = if let next {
            (next + x) / 2
        } else if let previous {
            x + ((x - previous) / 2)
        } else {
            x + 8
        }
        return CGRect(
            x: plotFrame.origin.x + min(left, right),
            y: plotFrame.origin.y,
            width: abs(right - left),
            height: plotFrame.height)
    }

    private func updateSelection(
        location: CGPoint?,
        model: CostHistoryChartDataPolicy.Data,
        proxy: ChartProxy,
        geo: GeometryProxy)
    {
        guard let location else {
            self.selectedDateKey = nil
            return
        }
        guard let plotAnchor = proxy.plotFrame else { return }
        let plotFrame = geo[plotAnchor]
        guard plotFrame.contains(location) else { return }
        guard let date: Date = proxy.value(atX: location.x - plotFrame.origin.x) else { return }
        guard let nearest = self.nearestDateKey(to: date, model: model) else { return }
        self.selectedDateKey = nearest
    }

    private func nearestDateKey(to date: Date, model: CostHistoryChartDataPolicy.Data) -> String? {
        model.datePoints.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(date)) < abs(rhs.date.timeIntervalSince(date))
        }?.key
    }

    private func detailContent(model: CostHistoryChartDataPolicy.Data) -> DetailContent {
        guard let key = self.selectedDateKey,
              let point = model.datePoints.first(where: { $0.key == key })
        else {
            return DetailContent(
                primary: "Last 30 days by model",
                rows: self.detailRows(model.periodRows, model: model))
        }

        let total = model.renderedTotalsByDateKey[key] ?? 0
        let dayLabel = point.date.formatted(.dateTime.month(.abbreviated).day())
        let primary = if let tokens = model.totalTokensByDateKey[key] {
            "\(dayLabel): \(UsageFormatter.usdString(total)) · \(UsageFormatter.tokenCountString(tokens)) tokens"
        } else {
            "\(dayLabel): \(UsageFormatter.usdString(total))"
        }
        return DetailContent(
            primary: primary,
            rows: self.detailRows(model.dailyRowsByDateKey[key] ?? [], model: model))
    }

    private func detailRows(
        _ rows: [CostHistoryChartDataPolicy.DetailRow],
        model: CostHistoryChartDataPolicy.Data) -> [DetailRow]
    {
        rows.map { row in
            let cost = row.costUSD.map(UsageFormatter.usdString) ?? "—"
            let subtitle: String = if let tokens = row.totalTokens {
                "\(cost) · \(UsageFormatter.tokenCountString(tokens)) tokens"
            } else {
                cost
            }
            return DetailRow(
                id: row.id,
                title: row.identity.displayName,
                subtitle: subtitle,
                accentColor: self.color(for: model.colors[row.identity]))
        }
    }

    private func color(for color: CostHistoryModelColor?) -> Color {
        guard let color else { return .clear }
        return Color(red: color.red, green: color.green, blue: color.blue)
    }
}
