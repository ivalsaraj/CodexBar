import Charts
import CodexBarCore
import SwiftUI

@MainActor
struct ProviderUtilizationChartMenuView: View {
    private struct SelectedValues {
        let date: Date
        let primaryUsedPercent: Double
        let secondaryUsedPercent: Double?
    }

    private let provider: UsageProvider
    private let historyStore: ProviderUtilizationHistoryStore
    private let width: CGFloat
    @State private var selectedRange: ProviderUtilizationTimeRange = .day1
    @State private var hoverDate: Date?

    init(provider: UsageProvider, historyStore: ProviderUtilizationHistoryStore, width: CGFloat) {
        self.provider = provider
        self.historyStore = historyStore
        self.width = width
    }

    var body: some View {
        let points = self.historyStore.downsampledPoints(for: self.provider, range: self.selectedRange)
        let selection = self.selectedValues(in: points)
        let metadata = ProviderDescriptorRegistry.descriptor(for: self.provider).metadata
        let medianVal = Self.medianValue(of: points.map(\.primaryUsedPercent))

        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: self.$selectedRange) {
                ForEach(ProviderUtilizationTimeRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if points.isEmpty {
                Text("No utilization history yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 130, alignment: .center)
            } else {
                Chart {
                    ForEach(points) { point in
                        LineMark(
                            x: .value("Time", point.timestamp),
                            y: .value(metadata.sessionLabel, point.primaryUsedPercent))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(by: .value("Series", metadata.sessionLabel))
                    }

                    ForEach(points) { point in
                        if let secondary = point.secondaryUsedPercent {
                            LineMark(
                                x: .value("Time", point.timestamp),
                                y: .value(metadata.weeklyLabel, secondary))
                                .interpolationMethod(.monotone)
                                .foregroundStyle(by: .value("Series", metadata.weeklyLabel))
                        }
                    }

                    RuleMark(y: .value("Median", medianVal))
                        .foregroundStyle(Self.medianColor)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

                    if self.hoverDate != nil, let selection {
                        RuleMark(x: .value("Selected", selection.date))
                            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                            .lineStyle(StrokeStyle(lineWidth: 1))

                        PointMark(
                            x: .value("Time", selection.date),
                            y: .value(metadata.sessionLabel, selection.primaryUsedPercent))
                            .foregroundStyle(Self.primaryColor(for: self.provider))
                            .symbolSize(20)

                        if let secondary = selection.secondaryUsedPercent {
                            PointMark(
                                x: .value("Time", selection.date),
                                y: .value(metadata.weeklyLabel, secondary))
                                .foregroundStyle(Self.secondaryColor)
                                .symbolSize(20)
                        }
                    }
                }
                .chartXScale(domain: self.xDomain)
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                        AxisGridLine().foregroundStyle(Color(nsColor: .quaternaryLabelColor))
                        AxisTick().foregroundStyle(Color.clear)
                        AxisValueLabel {
                            if let percent = value.as(Double.self) {
                                Text("\(Int(percent))%")
                                    .font(.caption2)
                                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine().foregroundStyle(Color.clear)
                        AxisTick().foregroundStyle(Color.clear)
                        AxisValueLabel(format: self.xAxisFormat)
                            .font(.caption2)
                            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    }
                }
                .chartLegend(.hidden)
                .chartForegroundStyleScale([
                    metadata.sessionLabel: Self.primaryColor(for: self.provider),
                    metadata.weeklyLabel: Self.secondaryColor,
                ])
                .chartPlotStyle { plot in
                    plot.clipped()
                }
                .frame(height: 130)
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        MouseLocationReader { location in
                            self.updateHover(location: location, proxy: proxy, geometry: geo)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                    }
                }

                if let selection {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(self.selectionDateText(for: selection.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        HStack(spacing: 10) {
                            Label(
                                "\(metadata.sessionLabel) \(Self.percentText(selection.primaryUsedPercent))",
                                systemImage: "circle.fill")
                                .font(.caption)
                                .foregroundStyle(Self.primaryColor(for: self.provider))
                            if let secondary = selection.secondaryUsedPercent {
                                Label(
                                    "\(metadata.weeklyLabel) \(Self.percentText(secondary))",
                                    systemImage: "circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(Self.secondaryColor)
                            }
                        }
                        .lineLimit(1)
                        .truncationMode(.tail)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(minWidth: self.width, maxWidth: .infinity, alignment: .leading)
    }

    private var xDomain: ClosedRange<Date> {
        let now = Date()
        return now.addingTimeInterval(-self.selectedRange.interval)...now
    }

    private func updateHover(location: CGPoint?, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let location, let plotFrame = proxy.plotFrame else {
            if self.hoverDate != nil {
                self.hoverDate = nil
            }
            return
        }

        let plotBounds = geometry[plotFrame]
        guard plotBounds.contains(location) else {
            if self.hoverDate != nil {
                self.hoverDate = nil
            }
            return
        }

        let relativeX = location.x - plotBounds.origin.x
        guard let date: Date = proxy.value(atX: relativeX) else {
            if self.hoverDate != nil {
                self.hoverDate = nil
            }
            return
        }

        self.hoverDate = date
    }

    private func selectedValues(in points: [ProviderUtilizationHistoryPoint]) -> SelectedValues? {
        guard !points.isEmpty else { return nil }
        guard let hoverDate = self.hoverDate else {
            guard let last = points.last else { return nil }
            return SelectedValues(
                date: last.timestamp,
                primaryUsedPercent: last.primaryUsedPercent,
                secondaryUsedPercent: last.secondaryUsedPercent)
        }
        return self.interpolateValues(at: hoverDate, in: points)
    }

    private func interpolateValues(
        at date: Date,
        in points: [ProviderUtilizationHistoryPoint])
        -> SelectedValues?
    {
        let sorted = points.sorted { $0.timestamp < $1.timestamp }
        guard let first = sorted.first, let last = sorted.last else { return nil }
        if sorted.count == 1 {
            return SelectedValues(
                date: first.timestamp,
                primaryUsedPercent: first.primaryUsedPercent,
                secondaryUsedPercent: first.secondaryUsedPercent)
        }
        if date <= first.timestamp {
            return SelectedValues(
                date: first.timestamp,
                primaryUsedPercent: first.primaryUsedPercent,
                secondaryUsedPercent: first.secondaryUsedPercent)
        }
        if date >= last.timestamp {
            return SelectedValues(
                date: last.timestamp,
                primaryUsedPercent: last.primaryUsedPercent,
                secondaryUsedPercent: last.secondaryUsedPercent)
        }

        for index in 0..<(sorted.count - 1) {
            let lhs = sorted[index]
            let rhs = sorted[index + 1]
            guard date >= lhs.timestamp, date <= rhs.timestamp else { continue }
            let span = rhs.timestamp.timeIntervalSince(lhs.timestamp)
            let progress = span > 0 ? date.timeIntervalSince(lhs.timestamp) / span : 0
            return SelectedValues(
                date: date,
                primaryUsedPercent: lhs
                    .primaryUsedPercent + (rhs.primaryUsedPercent - lhs.primaryUsedPercent) * progress,
                secondaryUsedPercent: Self.interpolateOptional(
                    lhs: lhs.secondaryUsedPercent,
                    rhs: rhs.secondaryUsedPercent,
                    progress: progress))
        }

        return nil
    }

    private func selectionDateText(for date: Date) -> String {
        if self.hoverDate == nil {
            return "Latest sample: \(date.formatted(self.selectionDateFormat))"
        }
        return date.formatted(self.selectionDateFormat)
    }

    private var xAxisFormat: Date.FormatStyle {
        switch self.selectedRange {
        case .hour1:
            .dateTime.hour().minute()
        case .hour6, .day1:
            .dateTime.hour()
        case .day7:
            .dateTime.weekday(.abbreviated)
        case .day30:
            .dateTime.month(.abbreviated).day()
        }
    }

    private var selectionDateFormat: Date.FormatStyle {
        switch self.selectedRange {
        case .hour1, .hour6, .day1:
            .dateTime.hour().minute()
        case .day7:
            .dateTime.weekday(.abbreviated).hour().minute()
        case .day30:
            .dateTime.month(.abbreviated).day().hour()
        }
    }

    private static func percentText(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    private static func primaryColor(for provider: UsageProvider) -> Color {
        let color = ProviderDescriptorRegistry.descriptor(for: provider).branding.color
        return Color(red: color.red, green: color.green, blue: color.blue)
    }

    private static var secondaryColor: Color {
        Color(nsColor: .systemYellow)
    }

    private static func interpolateOptional(lhs: Double?, rhs: Double?, progress: Double) -> Double? {
        guard let lhs, let rhs else { return lhs ?? rhs }
        return lhs + (rhs - lhs) * progress
    }

    private static var medianColor: Color {
        Color(nsColor: .secondaryLabelColor)
    }

    private static func medianValue(of values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
}
