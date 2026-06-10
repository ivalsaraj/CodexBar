import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct OpenCodeMenuCardTests {
    @Test
    func `opencode model does not show synthetic weekly pace details`() throws {
        let now = Date()
        let metadata = try #require(ProviderDefaults.metadata[.opencode])
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 54,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(90 * 60),
                resetDescription: nil),
            secondary: RateWindow(
                usedPercent: 69,
                windowMinutes: 10080,
                resetsAt: now.addingTimeInterval(2 * 24 * 60 * 60 + 11 * 60 * 60),
                resetDescription: nil),
            tertiary: RateWindow(
                usedPercent: 34,
                windowMinutes: 30 * 24 * 60,
                resetsAt: now.addingTimeInterval(29 * 24 * 60 * 60),
                resetDescription: nil),
            updatedAt: now)

        let model = UsageMenuCardView.Model.make(.init(
            provider: .opencode,
            metadata: metadata,
            snapshot: snapshot,
            credits: nil,
            creditsError: nil,
            dashboard: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: nil, plan: nil),
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: false,
            resetTimeDisplayStyle: .absolute,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            weeklyPace: nil,
            now: now))

        #expect(model.metrics.count == 3)
        #expect(model.metrics[1].title == "Weekly")
        #expect(model.metrics[1].detailLeftText == nil)
        #expect(model.metrics[1].detailRightText == nil)
        #expect(model.metrics[1].pacePercent == nil)
    }
}
