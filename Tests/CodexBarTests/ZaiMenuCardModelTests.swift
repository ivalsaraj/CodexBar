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

    @Test
    func `zai model falls back to rate window detail when raw usage is unavailable`() throws {
        let now = Date()
        let metadata = try #require(ProviderDefaults.metadata[.zai])
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 28,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(3600),
                resetDescription: "5 hours window"),
            secondary: RateWindow(
                usedPercent: 0,
                windowMinutes: nil,
                resetsAt: now.addingTimeInterval(48 * 3600),
                resetDescription: "1 minute window"),
            tertiary: nil,
            updatedAt: now)

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
            resetTimeDisplayStyle: .absolute,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            now: now))

        #expect(model.metrics.first?.detailText == "5 hours window")
        #expect(model.metrics.dropFirst().first?.detailText == "1 minute window")
    }

    @Test
    func `zai model formats token window minutes when description is unavailable`() throws {
        let now = Date()
        let metadata = try #require(ProviderDefaults.metadata[.zai])
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 28,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(3600),
                resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            updatedAt: now)

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
            resetTimeDisplayStyle: .absolute,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            now: now))

        #expect(model.metrics.first?.detailText == "5 hours window")
    }
}
