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
    func `cursor request row exposes expanded detail lines`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let request = CursorRecentRequest(
            timestamp: now,
            model: "composer-2.5",
            tokens: 2_000_000,
            requests: 1,
            requestCost: 2,
            tokenBreakdown: CursorRecentRequestTokenBreakdown(
                inputTokens: 1_000_000,
                outputTokens: 1_000_000,
                cacheReadTokens: 0,
                cacheWriteTokens: 0,
                totalTokens: 2_000_000,
                confidence: .exactBreakdown))

        let row = CursorMenuRequestRowPresentation.make(request: request, index: 0, now: now)

        #expect(row.detailLines.contains { $0.contains("composer-2.5") })
        #expect(row.detailLines.contains { $0.contains("1M in") })
        #expect(row.detailLines.contains { $0.contains("Est.") })
        #expect(row.detailLines.contains { $0.contains("Cursor Composer 2.5 changelog") })
        #expect(row.detailLines.contains { $0.contains("request-based") })
        #expect(row.secondaryLeft.contains("Req 2"))
    }

    @Test
    func `cursor request row shows weighted request cost in expanded details`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let request = CursorRecentRequest(
            timestamp: now,
            model: "gpt-5.5-extra-high",
            tokens: 1_000_000,
            requests: 1,
            requestCost: 2,
            tokenBreakdown: CursorRecentRequestTokenBreakdown(
                inputTokens: nil,
                outputTokens: nil,
                cacheReadTokens: nil,
                cacheWriteTokens: nil,
                totalTokens: 1_000_000,
                confidence: .totalOnly))

        let row = CursorMenuRequestRowPresentation.make(request: request, index: 0, now: now)

        #expect(row.secondaryLeft.contains("Req 2"))
        #expect(row.detailLines.contains("Request cost: 2"))
        #expect(row.detailLines.contains { $0.contains("lower-bound") })
        #expect(row.secondaryRight == "Approx. $5.00+")
        #expect(row.help.contains("total token count"))
    }

    @Test
    func `cursor request detail lines include approximate range for total only composer`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let request = CursorRecentRequest(
            timestamp: now,
            model: "composer-2.5",
            tokens: 2_000_000,
            requests: 1,
            tokenBreakdown: CursorRecentRequestTokenBreakdown(
                inputTokens: nil,
                outputTokens: nil,
                cacheReadTokens: nil,
                cacheWriteTokens: nil,
                totalTokens: 2_000_000,
                confidence: .totalOnly))
        let estimate = CursorRequestCostEstimator.estimate(for: request)

        let lines = UsageFormatter.cursorRequestDetailLines(request: request, estimate: estimate, now: now)

        #expect(lines.contains { $0.contains("Approx.") })
        #expect(lines.contains { $0.lowercased().contains("approx") })
        #expect(lines.contains { $0.contains("Cursor Composer 2.5 changelog") })
        #expect(lines.contains { $0.contains("request-based") })
    }

    @Test
    func `cursor request detail lines include disclaimer when estimate unavailable`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let request = CursorRecentRequest(
            timestamp: now,
            model: "some-internal-model-x1",
            tokens: 300,
            requests: 1,
            tokenBreakdown: CursorRecentRequestTokenBreakdown(
                inputTokens: 100,
                outputTokens: 200,
                cacheReadTokens: 0,
                cacheWriteTokens: 0,
                totalTokens: 300,
                confidence: .exactBreakdown))
        let estimate = CursorRequestCostEstimator.estimate(for: request)

        let lines = UsageFormatter.cursorRequestDetailLines(request: request, estimate: estimate, now: now)

        #expect(lines.contains { $0.contains("100 in") })
        #expect(lines.contains { $0.contains("Cost estimate unavailable") })
        #expect(lines.contains { $0.contains("request-based") })
    }

    @Test
    func `cursor request detail presentation keeps fixed scroll height independent of expansion`() {
        #expect(
            CursorMenuRequestDetailPresentation.scrollHeight
                == CGFloat(CursorMenuRequestDetailPresentation.maxVisibleRequestRows)
                * CursorMenuRequestDetailPresentation.rowHeight)
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
        #expect(row.secondaryLeft.contains(UsageFormatter.cursorRequestRowTimestamp(now)))
        #expect(row.secondaryLeft.contains("Req 1"))
        // total-only composer rows without breakdown show no compact estimate.
        #expect(row.secondaryRight == nil)
        #expect(!row.help.contains("Type"))
        #expect(!row.help.contains("Included"))
        #expect(!row.help.lowercased().contains("kind"))
        #expect(row.help.contains("request-based"))
    }

    @Test
    func `cursor request row shows approximate estimate for anthropic total without breakdown`() {
        let now = Date(timeIntervalSince1970: 1_770_201_720)
        let request = CursorRecentRequest(
            timestamp: now,
            model: "claude-opus-4-8-thinking-max",
            tokens: 252_000,
            requests: 1)

        let row = CursorMenuRequestRowPresentation.make(request: request, index: 0, now: now)

        #expect(row.primaryLeft == "Opus 4.8 · max")
        #expect(row.primaryRight == "252K")
        #expect(row.secondaryLeft.contains(UsageFormatter.cursorRequestRowTimestamp(now)))
        #expect(row.secondaryLeft.contains("Req 1"))
        #expect(row.secondaryRight == "Approx. $0.13-$6.30")
        #expect(row.detailLines.contains { $0.contains("Approx.") })
        #expect(row.help.contains("total tokens only"))
    }

    @Test
    func `cursor request row shows approximate estimate for anthropic empty breakdown`() {
        let now = Date(timeIntervalSince1970: 1_770_201_720)
        let request = CursorRecentRequest(
            timestamp: now,
            model: "claude-opus-4-8-thinking-max",
            tokens: 252_000,
            requests: 1,
            tokenBreakdown: CursorRecentRequestTokenBreakdown(
                inputTokens: nil,
                outputTokens: nil,
                cacheReadTokens: nil,
                cacheWriteTokens: nil,
                totalTokens: 0,
                confidence: .empty))

        let row = CursorMenuRequestRowPresentation.make(request: request, index: 0, now: now)

        #expect(row.primaryLeft == "Opus 4.8 · max")
        #expect(row.primaryRight == "252K")
        #expect(row.secondaryRight == "Approx. $0.13-$6.30")
        #expect(row.detailLines.contains { $0.contains("Approx.") })
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
    func `cursor request row shows approximate help for anthropic total only row`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let request = CursorRecentRequest(
            timestamp: now,
            model: "claude-opus-4-8-thinking-max",
            tokens: 252_000,
            requests: 1,
            tokenBreakdown: CursorRecentRequestTokenBreakdown(
                inputTokens: nil,
                outputTokens: nil,
                cacheReadTokens: nil,
                cacheWriteTokens: nil,
                totalTokens: 252_000,
                confidence: .totalOnly))

        let presentation = CursorMenuRequestDetailPresentation(
            range: nil,
            requests: [request],
            now: now)
        let row = try #require(presentation.requestRows.first)

        #expect(row.primaryLeft == "Opus 4.8 · max")
        #expect(row.secondaryRight?.hasPrefix("Approx.") == true)
        #expect(row.help.contains("Tokens: 252K (total only)"))
        #expect(row.help.contains("request-based"))
        #expect(row.help.lowercased().contains("unknown input/output/cache split"))
    }

    @Test
    func `cursor request row estimates cache writes with five minute default`() throws {
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

        #expect(row.secondaryRight?.hasPrefix("Est. ") == true)
        #expect(row.help.lowercased().contains("5-minute"))
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
        #expect(model.tokenUsage?.monthLine == "Cycle: 87M tokens · Approx. $0.50-$25.00")
        #expect(model.tokenUsage?.cursorRequestDetails.count == 1)
    }

    @Test
    func `cursor range summaries switch token lines range and request details`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let metadata = try #require(ProviderDefaults.metadata[.cursor])
        let billingRequest = CursorRecentRequest(
            timestamp: now,
            model: "claude-opus-4-8-thinking-max",
            tokens: 2_000_000,
            requests: 1)
        let olderRequest = CursorRecentRequest(
            timestamp: now.addingTimeInterval(-20 * 24 * 60 * 60),
            model: "composer-2.5",
            tokens: 1_000_000,
            requests: 1)
        let billingRange = CursorRecentRequestRange(start: now.addingTimeInterval(-7 * 24 * 60 * 60), end: now)
        let last30DaysRange = CursorRecentRequestRange(start: now.addingTimeInterval(-30 * 24 * 60 * 60), end: now)
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 14, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            cursorRequests: CursorRequestUsage(used: 44, limit: 500, metric: .requests),
            cursorTokenUsage: CursorTokenUsage(billingCycleTokensUsed: 2_000_000),
            cursorRangeSummaries: [
                CursorRangeUsageSummary(
                    rangeKind: .billingCycle,
                    range: billingRange,
                    tokens: 2_000_000,
                    requests: 1,
                    requestCostSummary: CursorRequestCostEstimator.summarizedEstimate(for: [billingRequest]),
                    recentRequests: [billingRequest]),
                CursorRangeUsageSummary(
                    rangeKind: .last30Days,
                    range: last30DaysRange,
                    tokens: 3_000_000,
                    requests: 2,
                    requestCostSummary: nil,
                    recentRequests: [billingRequest, olderRequest]),
            ],
            updatedAt: now)

        let cycleModel = UsageMenuCardView.Model.make(.init(
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

        #expect(cycleModel.tokenUsage?.sessionLine == "Requests: 44 / 500")
        #expect(cycleModel.tokenUsage?.monthLine == "Cycle: 2M tokens · Approx. $1.00-$50.00")
        #expect(cycleModel.tokenUsage?.cursorRequestRange == billingRange)
        #expect(cycleModel.tokenUsage?.cursorRequestDetails.map(\.model) == ["claude-opus-4-8-thinking-max"])
        #expect(cycleModel.tokenUsage?.selectedCursorRangeKind == .billingCycle)
        #expect(cycleModel.tokenUsage?.availableCursorRangeKinds == CursorUsageRangeKind.allCases)

        let last30DaysModel = UsageMenuCardView.Model.make(.init(
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
            cursorUsageRangeKind: .last30Days,
            now: now))

        #expect(last30DaysModel.tokenUsage?.sessionLine == "Requests: 2")
        #expect(last30DaysModel.tokenUsage?.monthLine == "30d: 3M tokens")
        #expect(last30DaysModel.tokenUsage?.cursorRequestRange == last30DaysRange)
        #expect(last30DaysModel.tokenUsage?.cursorRequestDetails.map(\.model) == [
            "claude-opus-4-8-thinking-max",
            "composer-2.5",
        ])
        #expect(last30DaysModel.tokenUsage?.selectedCursorRangeKind == .last30Days)
    }

    @Test
    func `cursor range summary billing cycle without quota collapses token and request count`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let metadata = try #require(ProviderDefaults.metadata[.cursor])
        let billingRequest = CursorRecentRequest(
            timestamp: now,
            model: "claude-opus-4-8-thinking-max",
            tokens: 2_000_000,
            requests: 1)
        let billingRange = CursorRecentRequestRange(start: now.addingTimeInterval(-7 * 24 * 60 * 60), end: now)
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 14, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            cursorRangeSummaries: [
                CursorRangeUsageSummary(
                    rangeKind: .billingCycle,
                    range: billingRange,
                    tokens: 2_000_000,
                    requests: 1,
                    requestCostSummary: CursorRequestCostEstimator.summarizedEstimate(for: [billingRequest]),
                    recentRequests: [billingRequest]),
            ],
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

        #expect(model.tokenUsage?.sessionLine == "Cycle: 2M tokens · Approx. $1.00-$50.00 · Req 1")
        #expect(model.tokenUsage?.monthLine == nil)
    }

    @Test
    func `cursor fallback menu recomputes stale gpt cycle cost summary`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let metadata = try #require(ProviderDefaults.metadata[.cursor])
        let staleCycleCostSummary = CursorRequestCostSummary(
            exactUSD: nil,
            lowerBoundUSD: 10,
            upperBoundUSD: 627,
            containsApproximation: true)
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 14, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            cursorTokenUsage: CursorTokenUsage(
                billingCycleTokensUsed: 20_912_049,
                requestCostSummary: staleCycleCostSummary),
            cursorRecentRequests: [
                CursorRecentRequest(
                    timestamp: now,
                    model: "gpt-5.5-extra-high",
                    tokens: 20_912_049,
                    requests: 1,
                    requestCost: 2,
                    tokenBreakdown: CursorRecentRequestTokenBreakdown(
                        inputTokens: nil,
                        outputTokens: nil,
                        cacheReadTokens: 20_912_049,
                        cacheWriteTokens: nil,
                        totalTokens: 20_912_049,
                        confidence: .partialBreakdown)),
            ],
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

        #expect(model.tokenUsage?.sessionLine == "Cycle: 21M tokens · Approx. $10.46+")
        #expect(model.tokenUsage?.monthLine == nil)
        #expect(model.tokenUsage?.cursorRequestDetails.first?.requests == 1)
    }

    @Test
    func `cursor fallback model keeps range switch and derives last thirty days locally`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let metadata = try #require(ProviderDefaults.metadata[.cursor])
        let recentRequest = CursorRecentRequest(
            timestamp: now.addingTimeInterval(-60),
            model: "claude-opus-4-8-thinking-max",
            tokens: 2_000_000,
            requests: 1)
        let olderRequest = CursorRecentRequest(
            timestamp: now.addingTimeInterval(-40 * 24 * 60 * 60),
            model: "composer-2.5",
            tokens: 1_000_000,
            requests: 1)
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 14, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            cursorRequests: CursorRequestUsage(used: 44, limit: 500),
            cursorTokenUsage: CursorTokenUsage(billingCycleTokensUsed: 3_000_000),
            cursorRecentRequests: [recentRequest, olderRequest],
            cursorRecentRequestRange: CursorRecentRequestRange(
                start: olderRequest.timestamp,
                end: recentRequest.timestamp),
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
            cursorUsageRangeKind: .last30Days,
            now: now))

        #expect(model.tokenUsage?.sessionLine == "Requests: 1")
        #expect(model.tokenUsage?.monthLine?.hasPrefix("30d: 2M tokens") == true)
        #expect(model.tokenUsage?.cursorRequestDetails.map(\.model) == ["claude-opus-4-8-thinking-max"])
        #expect(model.tokenUsage?.cursorRequestRange?.start == now.addingTimeInterval(-30 * 24 * 60 * 60))
        #expect(model.tokenUsage?.cursorRequestRange?.end == now)
        #expect(model.tokenUsage?.selectedCursorRangeKind == .last30Days)
        #expect(model.tokenUsage?.availableCursorRangeKinds == CursorUsageRangeKind.allCases)
    }

    @Test
    func `cursor fallback billing cycle without quota shows token line once`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let metadata = try #require(ProviderDefaults.metadata[.cursor])
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 14, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            cursorTokenUsage: CursorTokenUsage(billingCycleTokensUsed: 2_000_000),
            cursorRecentRequests: [
                CursorRecentRequest(
                    timestamp: now,
                    model: "claude-opus-4-8-thinking-max",
                    tokens: 2_000_000,
                    requests: 1),
            ],
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

        #expect(model.tokenUsage?.sessionLine == "Cycle: 2M tokens · Approx. $1.00-$50.00")
        #expect(model.tokenUsage?.monthLine == nil)
    }

    @Test
    func `cursor fallback last thirty days avoids capped aggregate totals`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let metadata = try #require(ProviderDefaults.metadata[.cursor])
        let requests = (0..<30).map { index in
            CursorRecentRequest(
                timestamp: now.addingTimeInterval(Double(-index * 60)),
                model: "claude-opus-4-8-thinking-max",
                tokens: 100_000,
                requests: 1)
        }
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 14, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            cursorTokenUsage: CursorTokenUsage(billingCycleTokensUsed: 3_000_000),
            cursorRecentRequests: requests,
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
            cursorUsageRangeKind: .last30Days,
            now: now))

        #expect(model.tokenUsage?.sessionLine == "Requests: 30+")
        #expect(model.tokenUsage?.monthLine == nil)
        #expect(model.tokenUsage?.cursorRequestRange?.start == now.addingTimeInterval(-30 * 24 * 60 * 60))
        #expect(model.tokenUsage?.cursorRequestDetails.count == 30)
    }

    @Test
    func `cursor cycle line includes summed request estimate when breakdowns are priced`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let metadata = try #require(ProviderDefaults.metadata[.cursor])
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 14, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            cursorRequests: CursorRequestUsage(used: 70, limit: 500, metric: .requests),
            cursorTokenUsage: CursorTokenUsage(billingCycleTokensUsed: 2_000_000),
            cursorRecentRequests: [
                CursorRecentRequest(
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
                        confidence: .exactBreakdown)),
            ],
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

        #expect(model.tokenUsage?.monthLine == "Cycle: 2M tokens · Est. $30.00")
    }
}
