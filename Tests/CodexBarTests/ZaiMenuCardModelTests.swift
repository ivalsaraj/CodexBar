import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct ZaiMenuCardModelTests {
    @Test
    func `zai model shows token window when quota counts are missing`() throws {
        let now = Date()
        let metadata = try #require(ProviderDefaults.metadata[.zai])
        let reset = now.addingTimeInterval(3600)
        let snapshot = ZaiUsageSnapshot(
            tokenLimit: ZaiLimitEntry(
                type: .tokensLimit,
                unit: .hours,
                number: 5,
                usage: nil,
                currentValue: nil,
                remaining: nil,
                percentage: 1,
                usageDetails: [],
                nextResetTime: reset),
            timeLimit: nil,
            planName: nil,
            updatedAt: now).toUsageSnapshot()

        let model = UsageMenuCardView.Model.make(.init(
            provider: .zai,
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
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            now: now))

        let primary = try #require(model.metrics.first)
        #expect(primary.detailText == "5 hours window")
    }
}
