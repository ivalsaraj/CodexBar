import CodexBarCore
import Testing
@testable import CodexBar

struct CostHistoryChartDataTests {
    @Test
    func `chart includes token usage when cost is unavailable`() {
        let entry = Self.entry(totalTokens: 42, costUSD: nil)

        #expect(CostHistoryChartEntryPolicy.shouldInclude(entry))
    }

    @Test
    func `chart includes positive component tokens when total is unavailable`() {
        let entry = Self.entry(inputTokens: 42, totalTokens: nil, costUSD: nil)

        #expect(CostHistoryChartEntryPolicy.shouldInclude(entry))
    }

    @Test(arguments: [0, -1])
    func `chart excludes nonpositive token usage without cost`(totalTokens: Int) {
        let entry = Self.entry(totalTokens: totalTokens, costUSD: nil)

        #expect(!CostHistoryChartEntryPolicy.shouldInclude(entry))
    }

    @Test
    func `chart retains token usage when cost is negative`() {
        let entry = Self.entry(totalTokens: 42, costUSD: -1)

        #expect(CostHistoryChartEntryPolicy.shouldInclude(entry))
        #expect(CostHistoryChartEntryPolicy.knownCostUSD(entry) == nil)
    }

    @Test
    func `chart peak candidates require known nonnegative cost`() {
        let known = Self.entry(totalTokens: 42, costUSD: 1.25)
        let unknown = Self.entry(totalTokens: 100, costUSD: nil)

        #expect(CostHistoryChartEntryPolicy.knownCostUSD(known) == 1.25)
        #expect(CostHistoryChartEntryPolicy.knownCostUSD(unknown) == nil)
    }

    private static func entry(
        inputTokens: Int? = nil,
        totalTokens: Int?,
        costUSD: Double?) -> CostUsageDailyReport.Entry
    {
        CostUsageDailyReport.Entry(
            date: "2026-07-13",
            inputTokens: inputTokens,
            outputTokens: nil,
            totalTokens: totalTokens,
            costUSD: costUSD,
            modelsUsed: nil,
            modelBreakdowns: nil)
    }
}
