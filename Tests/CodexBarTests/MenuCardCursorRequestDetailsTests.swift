import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@Suite
struct MenuCardCursorRequestDetailsTests {
    @Test
    func `cursor model keeps request quota primary and exposes structured rows`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let metadata = try #require(ProviderDefaults.metadata[.cursor])
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 6, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            cursorRequests: CursorRequestUsage(used: 28, limit: 500),
            cursorRecentRequests: [
                CursorRecentRequest(
                    timestamp: now,
                    model: "claude-opus-4-7-thinking-xhigh",
                    tokens: 12500,
                    requests: 1),
            ],
            cursorRecentRequestRange: CursorRecentRequestRange(
                start: now.addingTimeInterval(-24 * 60 * 60),
                end: now),
            updatedAt: now)

        let model = UsageMenuCardView.Model.make(.init(
            provider: .cursor,
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

        let tokenUsage = try #require(model.tokenUsage)
        #expect(tokenUsage.sessionLine == "Requests: 28 / 500")
        #expect(tokenUsage.monthLine?.hasPrefix("Cycle:") == true)
        #expect(tokenUsage.cursorRequestDetails.count == 1)

        let presentation = CursorMenuRequestDetailPresentation(
            range: tokenUsage.cursorRequestRange,
            requests: tokenUsage.cursorRequestDetails,
            now: now)
        let row = try #require(presentation.requestRows.first)
        #expect(row.primaryLeft == "Opus 4.7 · xhigh")
        #expect(row.secondaryLeft.contains("Req 1"))
        #expect(row.help.contains("claude-opus-4-7-thinking-xhigh"))
        #expect(presentation.fixedRows.first?.hasPrefix("Range:") == true)
    }

    @Test
    func `cursor model preserves structured recent requests for menu scrolling`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let metadata = try #require(ProviderDefaults.metadata[.cursor])
        let requests = (0..<35).map { index in
            CursorRecentRequest(
                timestamp: now.addingTimeInterval(Double(-index * 60)),
                model: "model-\(index)",
                tokens: 100_000 + index,
                requests: 1)
        }
        let range = CursorRecentRequestRange(
            start: now.addingTimeInterval(-35 * 60),
            end: now)
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 6, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            cursorRequests: CursorRequestUsage(used: 30, limit: 500),
            cursorRecentRequests: requests,
            cursorRecentRequestRange: range,
            updatedAt: now)

        let model = UsageMenuCardView.Model.make(.init(
            provider: .cursor,
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

        let tokenUsage = try #require(model.tokenUsage)
        #expect(tokenUsage.cursorRequestRange == range)
        #expect(tokenUsage.cursorRequestDetails.count == 30)
        #expect(tokenUsage.cursorRequestDetails.first?.model == "model-0")
        #expect(tokenUsage.cursorRequestDetails.last?.model == "model-29")
    }

    @Test
    func `cursor request row shows compact model token spend and request count without dashboard type`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let request = CursorRecentRequest(
            timestamp: now,
            model: "composer-2.5",
            tokens: 2_500_000,
            requests: 1)

        let presentation = CursorMenuRequestDetailPresentation(
            range: nil,
            requests: [request],
            now: now)
        let row = try #require(presentation.requestRows.first)

        #expect(row.primaryLeft == "Composer 2.5")
        #expect(row.primaryRight == "2.5M")
        #expect(row.secondaryLeft.contains("Req 1"))
        // composer has no shared pricing, so no fabricated estimate.
        #expect(row.secondaryRight == nil)
        #expect(!row.help.contains("Type"))
        #expect(!row.help.contains("Included"))
        #expect(!row.help.lowercased().contains("kind"))
        #expect(row.help.contains("request-based"))
    }

    @Test
    func `cursor request row shows estimate and breakdown help for priced model`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let request = CursorRecentRequest(
            timestamp: now,
            model: "claude-opus-4-8-thinking-xhigh",
            tokens: 2_000_000,
            requests: 1,
            tokenBreakdown: CursorRecentRequestTokenBreakdown(
                inputTokens: 1_000_000,
                outputTokens: 1_000_000,
                cacheReadTokens: 0,
                cacheWriteTokens: 0,
                totalTokens: 2_000_000,
                confidence: .exactBreakdown))

        let presentation = CursorMenuRequestDetailPresentation(
            range: nil,
            requests: [request],
            now: now)
        let row = try #require(presentation.requestRows.first)

        #expect(row.primaryLeft == "Opus 4.8 · xhigh")
        #expect(row.primaryRight == "2M")
        #expect(row.secondaryRight?.hasPrefix("Est. ") == true)
        #expect(row.help.contains("claude-opus-4-8-thinking-xhigh"))
        #expect(row.help.contains("request-based"))
    }

    @Test
    func `cursor request row marks partial estimate when cache write tier missing`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let request = CursorRecentRequest(
            timestamp: now,
            model: "claude-opus-4-8-thinking-xhigh",
            tokens: 1000,
            requests: 1,
            tokenBreakdown: CursorRecentRequestTokenBreakdown(
                inputTokens: 100,
                outputTokens: 200,
                cacheReadTokens: 300,
                cacheWriteTokens: 400,
                totalTokens: 1000,
                confidence: .exactBreakdown))

        let presentation = CursorMenuRequestDetailPresentation(
            range: nil,
            requests: [request],
            now: now)
        let row = try #require(presentation.requestRows.first)

        #expect(row.secondaryRight?.hasPrefix("Partial ") == true)
        #expect(row.help.lowercased().contains("cache-write"))
    }

    @Test
    func `cursor request presentation scrolls overflow rows and keeps range fixed`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let requests = (0..<(CursorMenuRequestDetailPresentation.maxVisibleRequestRows + 1)).map { index in
            CursorRecentRequest(
                timestamp: now.addingTimeInterval(Double(-index * 60)),
                model: "model-\(index)",
                tokens: 100_000 + index,
                requests: 1)
        }
        let range = CursorRecentRequestRange(
            start: now.addingTimeInterval(-60 * 60),
            end: now)

        let presentation = CursorMenuRequestDetailPresentation(
            range: range,
            requests: requests,
            now: now)

        #expect(presentation.shouldScroll)
        #expect(presentation.fixedRows == [UsageFormatter.cursorRecentRequestRangeLine(range)])
        #expect(presentation.requestRows.count == requests.count)
        #expect(presentation.requestRows.first?.primaryLeft.contains("Model 0") == true)
    }

    @Test
    func `cursor legacy request plan keeps request quota primary with recent rows`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let metadata = try #require(ProviderDefaults.metadata[.cursor])
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 14, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            cursorRequests: CursorRequestUsage(used: 70, limit: 500, metric: .requests),
            cursorTokenUsage: CursorTokenUsage(billingCycleTokensUsed: 86_684_822),
            cursorRecentRequests: [
                CursorRecentRequest(
                    timestamp: now,
                    model: "claude-opus-4-8-thinking-xhigh",
                    tokens: 1_000_000,
                    requests: 1),
            ],
            cursorRecentRequestRange: CursorRecentRequestRange(start: now.addingTimeInterval(-3600), end: now),
            updatedAt: now)

        let model = UsageMenuCardView.Model.make(.init(
            provider: .cursor,
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

        #expect(model.tokenUsage?.sessionLine == "Requests: 70 / 500")
        #expect(model.tokenUsage?.monthLine == "Cycle: 87M tokens")
        #expect(model.tokenUsage?.cursorRequestDetails.count == 1)
    }
}
