import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@Suite
struct MenuCardProviderCostTests {
    @Test
    func `codex cost section includes subscription renewal date`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let renewal = now.addingTimeInterval(12 * 24 * 60 * 60)
        let metadata = try #require(ProviderDefaults.metadata[.codex])
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 0, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            codexUsage: CodexUsageSnapshot(subscriptionRenewalAt: renewal),
            updatedAt: now)
        let tokenSnapshot = CostUsageTokenSnapshot(
            sessionTokens: 123,
            sessionCostUSD: 1.23,
            last30DaysTokens: 456,
            last30DaysCostUSD: 4.56,
            daily: [],
            updatedAt: now)

        let model = UsageMenuCardView.Model.make(.init(
            provider: .codex,
            metadata: metadata,
            snapshot: snapshot,
            credits: nil,
            creditsError: nil,
            dashboard: nil,
            dashboardError: nil,
            tokenSnapshot: tokenSnapshot,
            tokenError: nil,
            account: AccountInfo(email: nil, plan: nil),
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: false,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: true,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            now: now))

        #expect(model.tokenUsage?
            .renewalLine == "Monthly renews \(UsageFormatter.resetDescription(from: renewal, now: now))")
    }

    @Test
    func `provider cost section includes monthly renewal date`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let renewal = now.addingTimeInterval(6 * 24 * 60 * 60)
        let metadata = try #require(ProviderDefaults.metadata[.claude])
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 0, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(
                usedPercent: 32,
                windowMinutes: 10080,
                resetsAt: now.addingTimeInterval(2 * 24 * 60 * 60),
                resetDescription: nil),
            tertiary: nil,
            providerCost: ProviderCostSnapshot(
                used: 12,
                limit: 200,
                currencyCode: "USD",
                period: "Monthly",
                resetsAt: renewal,
                updatedAt: now),
            updatedAt: now)

        let model = UsageMenuCardView.Model.make(.init(
            provider: .claude,
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
            tokenCostUsageEnabled: true,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            now: now))

        #expect(model.providerCost?
            .renewalLine == "Monthly renews \(UsageFormatter.resetDescription(from: renewal, now: now))")
    }
}
