import Foundation
import Testing
@testable import CodexBarCore

struct CursorStatusProbeUsageSummaryTests {
    @Test
    func `parse usage summary carries billing cycle tokens without token limit`() {
        let summary = CursorUsageSummary(
            billingCycleStart: "2026-04-17T17:18:07.000Z",
            billingCycleEnd: "2026-05-17T17:18:07.000Z",
            membershipType: "pro",
            limitType: "user",
            isUnlimited: false,
            autoModelSelectedDisplayMessage: nil,
            namedModelSelectedDisplayMessage: nil,
            individualUsage: CursorIndividualUsage(
                plan: CursorPlanUsage(
                    enabled: true,
                    used: 280,
                    limit: 2000,
                    remaining: 1720,
                    breakdown: nil,
                    autoPercentUsed: 0,
                    apiPercentUsed: 6.222222222222222,
                    totalPercentUsed: 1.866666666666667),
                onDemand: nil),
            teamUsage: nil)
        let requestUsage = CursorUsageResponse(
            gpt4: CursorModelUsage(
                numRequests: 70,
                numRequestsTotal: 70,
                numTokens: 86_684_822,
                maxRequestUsage: 500,
                maxTokenUsage: nil),
            startOfMonth: "2026-04-17T17:18:07.000Z")

        let snapshot = CursorStatusProbe(browserDetection: BrowserDetection(cacheTTL: 0)).parseUsageSummary(
            summary,
            userInfo: nil,
            rawJSON: nil,
            requestUsage: requestUsage)
        let usageSnapshot = snapshot.toUsageSnapshot()

        #expect(snapshot.billingCycleTokensUsed == 86_684_822)
        #expect(usageSnapshot.cursorTokenUsage?.billingCycleTokensUsed == 86_684_822)
        #expect(usageSnapshot.cursorRequests?.used == 70)
    }

    @Test
    func `parse usage summary carries recent cursor request events`() {
        let summary = CursorUsageSummary(
            billingCycleStart: "2026-05-01T00:00:00.000Z",
            billingCycleEnd: "2026-06-01T00:00:00.000Z",
            membershipType: "pro",
            limitType: "user",
            isUnlimited: false,
            autoModelSelectedDisplayMessage: nil,
            namedModelSelectedDisplayMessage: nil,
            individualUsage: nil,
            teamUsage: nil)
        let events = [
            CursorUsageEvent(
                timestamp: "1779888240000",
                model: "claude-opus-4-7-thinking-xhigh",
                requestsCosts: 1,
                tokenUsage: CursorUsageEventTokenUsage(
                    inputTokens: 100,
                    outputTokens: 200,
                    cacheReadTokens: 300,
                    cacheWriteTokens: 400,
                    totalTokens: nil)),
        ]

        let snapshot = CursorStatusProbe(browserDetection: BrowserDetection(cacheTTL: 0)).parseUsageSummary(
            summary,
            userInfo: nil,
            rawJSON: nil,
            usageEvents: events)
        let usageSnapshot = snapshot.toUsageSnapshot()

        #expect(usageSnapshot.cursorRecentRequests?.count == 1)
        #expect(usageSnapshot.cursorRecentRequests?.first?.model == "claude-opus-4-7-thinking-xhigh")
        #expect(usageSnapshot.cursorRecentRequests?.first?.tokens == 1000)
        #expect(usageSnapshot.cursorRecentRequests?.first?.requests == 1)
        let expectedDate = Date(timeIntervalSince1970: 1_779_888_240)
        #expect(usageSnapshot.cursorRecentRequests?.first?.timestamp == expectedDate)
        #expect(usageSnapshot.cursorRecentRequestRange?.start == Date(timeIntervalSince1970: 1_777_593_600))
        #expect(usageSnapshot.cursorRecentRequestRange?.end == Date(timeIntervalSince1970: 1_780_272_000))
    }

    /// Event rows from POST /api/dashboard/get-filtered-usage-events (`usageEventsDisplay`).
    /// Timestamp is Unix milliseconds as a string; model + tokenUsage drive widget rows; `kind` is not surfaced.
    @Test
    func `fixture usage events decode to recent cursor requests`() throws {
        let url = try #require(Bundle.module.url(
            forResource: "cursor-usage-events",
            withExtension: "json",
            subdirectory: "Fixtures"))
        let data = try Data(contentsOf: url)
        let events = try CursorStatusProbe.decodeUsageEventsResponse(from: data)
        let recent = CursorStatusProbe.recentRequests(from: events)

        #expect(events.count == 2)
        #expect(recent.count == 2)
        #expect(recent.first?.model == "claude-opus-4-7-thinking-xhigh")
        #expect(recent.first?.tokens == 1000)
        #expect(recent.first?.requests == 1)
        #expect(recent.first?.timestamp == Date(timeIntervalSince1970: 1_779_888_240))
        #expect(recent[1].model == "composer-2")
        #expect(recent[1].tokens == 120)
        #expect(recent[1].requests == 2)
    }

    @Test
    func `recent request preserves full token breakdown`() {
        let events = [
            CursorUsageEvent(
                timestamp: "1770201720000",
                model: "claude-opus-4-8-thinking-xhigh",
                requestsCosts: 1,
                tokenUsage: CursorUsageEventTokenUsage(
                    inputTokens: 120_000,
                    outputTokens: 42000,
                    cacheReadTokens: 34_600_000,
                    cacheWriteTokens: 210_000,
                    totalTokens: nil)),
        ]

        let recent = CursorStatusProbe.recentRequests(from: events)

        #expect(recent.count == 1)
        let request = recent.first
        #expect(request?.tokens == 34_972_000)
        #expect(request?.requests == 1)
        let breakdown = request?.tokenBreakdown
        #expect(breakdown?.inputTokens == 120_000)
        #expect(breakdown?.outputTokens == 42000)
        #expect(breakdown?.cacheReadTokens == 34_600_000)
        #expect(breakdown?.cacheWriteTokens == 210_000)
        #expect(breakdown?.totalTokens == 34_972_000)
        #expect(breakdown?.confidence == .exactBreakdown)
    }

    @Test
    func `recent request marks total-only usage`() {
        let events = [
            CursorUsageEvent(
                timestamp: "1770201720000",
                model: "claude-opus-4-8-thinking-xhigh",
                requestsCosts: 1,
                tokenUsage: CursorUsageEventTokenUsage(totalTokens: 35_000_000)),
        ]

        let recent = CursorStatusProbe.recentRequests(from: events)

        #expect(recent.count == 1)
        let breakdown = recent.first?.tokenBreakdown
        #expect(recent.first?.tokens == 35_000_000)
        #expect(breakdown?.totalTokens == 35_000_000)
        #expect(breakdown?.inputTokens == nil)
        #expect(breakdown?.outputTokens == nil)
        #expect(breakdown?.confidence == .totalOnly)
    }

    @Test
    func `recent request marks partial token parts`() {
        let events = [
            CursorUsageEvent(
                timestamp: "1770201720000",
                model: "claude-opus-4-8-thinking-xhigh",
                requestsCosts: 1,
                tokenUsage: CursorUsageEventTokenUsage(
                    inputTokens: 100,
                    outputTokens: 200,
                    cacheReadTokens: nil,
                    cacheWriteTokens: nil,
                    totalTokens: nil)),
        ]

        let recent = CursorStatusProbe.recentRequests(from: events)

        #expect(recent.count == 1)
        let breakdown = recent.first?.tokenBreakdown
        #expect(recent.first?.tokens == 300)
        #expect(breakdown?.inputTokens == 100)
        #expect(breakdown?.outputTokens == 200)
        #expect(breakdown?.cacheReadTokens == nil)
        #expect(breakdown?.cacheWriteTokens == nil)
        #expect(breakdown?.confidence == .partialBreakdown)
    }
}
