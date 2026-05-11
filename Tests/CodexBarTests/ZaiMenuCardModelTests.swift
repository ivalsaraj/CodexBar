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

    @Test
    func `zai model shows tokens weekly and MCP as separate metrics`() throws {
        let now = Date()
        let metadata = try #require(ProviderDefaults.metadata[.zai])
        let snapshot = ZaiUsageSnapshot(
            tokenLimit: ZaiLimitEntry(
                type: .tokensLimit,
                unit: .hours,
                number: 5,
                usage: nil,
                currentValue: nil,
                remaining: nil,
                percentage: 21,
                usageDetails: [],
                nextResetTime: now.addingTimeInterval(5 * 3600)),
            secondaryTokenLimit: ZaiLimitEntry(
                type: .tokensLimit,
                unit: .weeks,
                number: 1,
                usage: nil,
                currentValue: nil,
                remaining: nil,
                percentage: 30,
                usageDetails: [],
                nextResetTime: now.addingTimeInterval(7 * 24 * 3600)),
            timeLimit: ZaiLimitEntry(
                type: .timeLimit,
                unit: .minutes,
                number: 1,
                usage: 1000,
                currentValue: 0,
                remaining: 1000,
                percentage: 0,
                usageDetails: [ZaiUsageDetail(modelCode: "search-prime", usage: 0)],
                nextResetTime: now.addingTimeInterval(9 * 24 * 3600)),
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
            resetTimeDisplayStyle: .absolute,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            now: now))

        let metricTitles: [String] = model.metrics.map(\.title)
        #expect(metricTitles == ["Tokens", "Weekly", "MCP"])
        #expect(model.metrics.first?.detailText == "5 hours window")
        #expect(model.metrics.dropFirst().first?.detailText == "1 week window")
        #expect(model.metrics.last?.detailText == "0 / 1K (1K remaining) · 1 minute window")
    }
}
