import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

struct CostHistoryChartDataTests {
    @Test
    func `stacks daily model costs and sums period model totals`() {
        let data = CostHistoryChartDataPolicy.build(daily: [
            Self.entry(
                date: "2026-07-01",
                costUSD: 3,
                totalTokens: 300,
                modelsUsed: nil,
                modelBreakdowns: [
                    .init(modelName: "alpha", costUSD: 1, totalTokens: 100),
                    .init(modelName: "beta", costUSD: 2, totalTokens: 200),
                ]),
            Self.entry(
                date: "2026-07-02",
                costUSD: 4,
                totalTokens: 400,
                modelsUsed: nil,
                modelBreakdowns: [
                    .init(modelName: "alpha", costUSD: 1.5, totalTokens: 150),
                    .init(modelName: "alpha", costUSD: 2.5, totalTokens: 250),
                ]),
        ])

        #expect(data.datePoints.map(\.key) == ["2026-07-01", "2026-07-02"])
        #expect(Self.segmentValues(data.segments) == [
            .init(dateKey: "2026-07-01", identity: .model("beta"), costUSD: 2),
            .init(dateKey: "2026-07-01", identity: .model("alpha"), costUSD: 1),
            .init(dateKey: "2026-07-02", identity: .model("alpha"), costUSD: 4),
        ])
        #expect(data.tokenOnlyDatePoints.isEmpty)
        #expect(Self.rowValues(data.periodRows) == [
            .init(identity: .model("alpha"), costUSD: 5, totalTokens: 500),
            .init(identity: .model("beta"), costUSD: 2, totalTokens: 200),
        ])
        #expect(Self.rowValues(data.dailyRowsByDateKey["2026-07-02"] ?? []) == [
            .init(identity: .model("alpha"), costUSD: 4, totalTokens: 400),
        ])
    }

    @Test
    func `keeps token-only dates and models with unknown cost`() {
        let data = CostHistoryChartDataPolicy.build(daily: [
            Self.entry(
                date: "2026-07-01",
                costUSD: nil,
                totalTokens: 200,
                modelsUsed: [" alpha ", "only-listed", " "],
                modelBreakdowns: [
                    .init(modelName: "alpha", costUSD: nil, totalTokens: 200),
                ]),
        ])

        #expect(data.datePoints.map(\.key) == ["2026-07-01"])
        #expect(data.segments.isEmpty)
        #expect(data.tokenOnlyDatePoints.map(\.key) == ["2026-07-01"])
        #expect(Self.activitySegmentValues(data.tokenActivitySegments) == [
            .init(dateKey: "2026-07-01", identity: .model("alpha"), share: 1),
        ])
        #expect(data.renderedTotalsByDateKey["2026-07-01"] == 0)
        #expect(Self.rowValues(data.dailyRowsByDateKey["2026-07-01"] ?? []) == [
            .init(identity: .model("alpha"), costUSD: nil, totalTokens: 200),
            .init(identity: .model("only-listed"), costUSD: nil, totalTokens: nil),
        ])
        #expect(data.peakKey == nil)
    }

    @Test
    func `uses model breakdown tokens for token-only activity`() {
        let data = CostHistoryChartDataPolicy.build(daily: [
            Self.entry(
                date: "2026-07-01",
                costUSD: nil,
                totalTokens: nil,
                modelsUsed: nil,
                modelBreakdowns: [
                    .init(modelName: "alpha", costUSD: nil, totalTokens: 80),
                    .init(modelName: "beta", costUSD: nil, totalTokens: 20),
                ]),
        ])

        #expect(data.datePoints.map(\.key) == ["2026-07-01"])
        #expect(Self.activitySegmentValues(data.tokenActivitySegments) == [
            .init(dateKey: "2026-07-01", identity: .model("alpha"), share: 0.8),
            .init(dateKey: "2026-07-01", identity: .model("beta"), share: 0.2),
        ])
        #expect(data.activityBarHeight == 0.035)
        #expect(data.chartUpperBound == 1)
    }

    @Test
    func `uses unattributed activity for unnamed breakdown tokens`() {
        let data = CostHistoryChartDataPolicy.build(daily: [
            Self.entry(
                date: "2026-07-01",
                costUSD: nil,
                totalTokens: nil,
                modelsUsed: nil,
                modelBreakdowns: [
                    .init(modelName: " ", costUSD: nil, totalTokens: 100),
                ]),
        ])

        #expect(data.datePoints.map(\.key) == ["2026-07-01"])
        #expect(Self.activitySegmentValues(data.tokenActivitySegments) == [
            .init(dateKey: "2026-07-01", identity: .unattributed, share: 1),
        ])
    }

    @Test
    func `falls back to unattributed cost without changing source breakdown values`() {
        let data = CostHistoryChartDataPolicy.build(daily: [
            Self.entry(
                date: "2026-07-01",
                costUSD: 10,
                totalTokens: 500,
                modelsUsed: nil,
                modelBreakdowns: [
                    .init(modelName: "alpha", costUSD: 3, totalTokens: 300),
                    .init(modelName: " ", costUSD: 2, totalTokens: 200),
                ]),
            Self.entry(
                date: "2026-07-02",
                costUSD: 1,
                totalTokens: 100,
                modelsUsed: nil,
                modelBreakdowns: [
                    .init(modelName: "beta", costUSD: 3, totalTokens: 100),
                ]),
            Self.entry(
                date: "2026-07-03",
                costUSD: 4,
                totalTokens: 50,
                modelsUsed: nil,
                modelBreakdowns: nil),
        ])

        #expect(Self.rowValues(data.dailyRowsByDateKey["2026-07-01"] ?? []) == [
            .init(identity: .unattributed, costUSD: 7, totalTokens: nil),
            .init(identity: .model("alpha"), costUSD: 3, totalTokens: 300),
        ])
        #expect(Self.rowValues(data.dailyRowsByDateKey["2026-07-02"] ?? []) == [
            .init(identity: .model("beta"), costUSD: 3, totalTokens: 100),
        ])
        #expect(Self.rowValues(data.dailyRowsByDateKey["2026-07-03"] ?? []) == [
            .init(identity: .unattributed, costUSD: 4, totalTokens: nil),
        ])
        #expect(Self.rowValues(data.periodRows) == [
            .init(identity: .unattributed, costUSD: 11, totalTokens: nil),
            .init(identity: .model("alpha"), costUSD: 3, totalTokens: 300),
            .init(identity: .model("beta"), costUSD: 3, totalTokens: 100),
        ])
        #expect(data.renderedTotalsByDateKey == ["2026-07-01": 10, "2026-07-02": 3, "2026-07-03": 4])
    }

    @Test
    func `ignores invalid values preserves zero-cost rows and distinguishes literal unattributed`() {
        let data = CostHistoryChartDataPolicy.build(daily: [
            Self.entry(
                date: "2026-07-01",
                costUSD: .infinity,
                totalTokens: -1,
                modelsUsed: ["Unattributed", "zero"],
                modelBreakdowns: [
                    .init(modelName: "negative", costUSD: -1, totalTokens: -1),
                    .init(modelName: "infinite", costUSD: .infinity, totalTokens: 1),
                    .init(modelName: "zero", costUSD: 0, totalTokens: 0),
                    .init(modelName: "Unattributed", costUSD: 2, totalTokens: 2),
                ]),
            Self.entry(
                date: "2026-07-02",
                costUSD: nil,
                totalTokens: nil,
                modelsUsed: nil,
                modelBreakdowns: [
                    .init(modelName: "alpha", costUSD: -1, totalTokens: -1),
                ]),
        ])

        #expect(data.datePoints.map(\.key) == ["2026-07-01"])
        #expect(Self.rowValues(data.dailyRowsByDateKey["2026-07-01"] ?? []) == [
            .init(identity: .model("Unattributed"), costUSD: 2, totalTokens: 2),
            .init(identity: .model("zero"), costUSD: 0, totalTokens: 0),
            .init(identity: .model("infinite"), costUSD: nil, totalTokens: 1),
            .init(identity: .model("negative"), costUSD: nil, totalTokens: nil),
        ])
        #expect(Self.segmentValues(data.segments) == [
            .init(dateKey: "2026-07-01", identity: .model("Unattributed"), costUSD: 2),
        ])
        #expect(data.tokenOnlyDatePoints.isEmpty)
    }

    @Test
    func `selects the earliest rendered-cost peak including unknown aggregate days`() {
        let data = CostHistoryChartDataPolicy.build(daily: [
            Self.entry(
                date: "2026-07-01",
                costUSD: 0,
                totalTokens: 1,
                modelsUsed: nil,
                modelBreakdowns: [.init(modelName: "alpha", costUSD: 5, totalTokens: 1)]),
            Self.entry(
                date: "2026-07-02",
                costUSD: nil,
                totalTokens: 1,
                modelsUsed: nil,
                modelBreakdowns: [.init(modelName: "beta", costUSD: 5, totalTokens: 1)]),
            Self.entry(
                date: "2026-07-03",
                costUSD: 0,
                totalTokens: 1,
                modelsUsed: nil,
                modelBreakdowns: nil),
        ])

        #expect(data.peakKey == "2026-07-01")
        #expect(data.renderedTotalsByDateKey == ["2026-07-01": 5, "2026-07-02": 5, "2026-07-03": 0])
    }

    @Test
    func `assigns deterministic distinct palette colors and neutral unattributed`() {
        let identities: Set<CostHistoryChartDataPolicy.Identity> = [
            .model("alpha"),
            .model("beta"),
            .model("gamma"),
            .unattributed,
        ]
        let first = CostHistoryModelColorPolicy.colors(for: identities)
        let second = CostHistoryModelColorPolicy.colors(for: identities)

        #expect(first == second)
        #expect(first[.unattributed] == .init(red: 139.0 / 255.0, green: 144.0 / 255.0, blue: 152.0 / 255.0))
        #expect(Set(identities.compactMap { first[$0] }).count == identities.count)

        let literal = CostHistoryModelColorPolicy.colors(for: [.unattributed, .model("Unattributed")])
        #expect(literal[.unattributed] != literal[.model("Unattributed")])
    }

    @Test
    func `assigns evenly spaced non-yellow overflow colors`() {
        let identities = Set((0..<14).map { CostHistoryChartDataPolicy.Identity.model("model-\($0)") })
        let colors = CostHistoryModelColorPolicy.colors(for: identities)
        let overflow = (0..<14).compactMap { colors[.model("model-\($0)")] }.filter { color in
            !CostHistoryModelColorPolicy.basePalette.contains(color)
        }

        #expect(overflow.count == 2)
        #expect(overflow[0] != overflow[1])
        #expect(overflow.allSatisfy { $0.red.isFinite && $0.green.isFinite && $0.blue.isFinite })
        #expect(abs(overflow[0].red - 0.524) < 0.000_000_000_001)
        #expect(abs(overflow[0].green - 0.888) < 0.000_000_000_001)
        #expect(abs(overflow[0].blue - 0.472) < 0.000_000_000_001)
        #expect(abs(overflow[1].red - 0.732) < 0.000_000_000_001)
        #expect(abs(overflow[1].green - 0.472) < 0.000_000_000_001)
        #expect(abs(overflow[1].blue - 0.888) < 0.000_000_000_001)
    }

    private static func entry(
        date: String,
        costUSD: Double?,
        totalTokens: Int?,
        modelsUsed: [String]?,
        modelBreakdowns: [CostUsageDailyReport.ModelBreakdown]?) -> CostUsageDailyReport.Entry
    {
        CostUsageDailyReport.Entry(
            date: date,
            inputTokens: nil,
            outputTokens: nil,
            totalTokens: totalTokens,
            costUSD: costUSD,
            modelsUsed: modelsUsed,
            modelBreakdowns: modelBreakdowns)
    }

    private static func rowValues(_ rows: [CostHistoryChartDataPolicy.DetailRow]) -> [RowValue] {
        rows.map { .init(identity: $0.identity, costUSD: $0.costUSD, totalTokens: $0.totalTokens) }
    }

    private static func segmentValues(_ segments: [CostHistoryChartDataPolicy.Segment]) -> [SegmentValue] {
        segments.map { .init(dateKey: $0.dateKey, identity: $0.identity, costUSD: $0.costUSD) }
    }

    private static func activitySegmentValues(
        _ segments: [CostHistoryChartDataPolicy.TokenActivitySegment]) -> [ActivitySegmentValue]
    {
        segments.map { .init(dateKey: $0.dateKey, identity: $0.identity, share: $0.share) }
    }

    private struct RowValue: Equatable {
        let identity: CostHistoryChartDataPolicy.Identity
        let costUSD: Double?
        let totalTokens: Int?
    }

    private struct SegmentValue: Equatable {
        let dateKey: String
        let identity: CostHistoryChartDataPolicy.Identity
        let costUSD: Double
    }

    private struct ActivitySegmentValue: Equatable {
        let dateKey: String
        let identity: CostHistoryChartDataPolicy.Identity
        let share: Double
    }
}
