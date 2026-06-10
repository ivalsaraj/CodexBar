import Foundation
import Testing
@testable import CodexBarCore

struct WidgetSnapshotTests {
    @Test
    func `widget snapshot round trip`() throws {
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .codex,
            updatedAt: Date(),
            primary: RateWindow(usedPercent: 10, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 20, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            tertiary: nil,
            usageRows: [
                WidgetSnapshot.WidgetUsageRowSnapshot(
                    id: "session",
                    title: "Session",
                    percentLeft: 90,
                    detailText: "5 hours window"),
                WidgetSnapshot.WidgetUsageRowSnapshot(id: "weekly", title: "Weekly", percentLeft: 80),
            ],
            creditsRemaining: 123.4,
            codeReviewRemainingPercent: 80,
            tokenUsage: WidgetSnapshot.TokenUsageSummary(
                sessionCostUSD: 12.3,
                sessionTokens: 1200,
                last30DaysCostUSD: 456.7,
                last30DaysTokens: 9800),
            dailyUsage: [
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-20", totalTokens: 1200, costUSD: 12.3),
            ])

        let snapshot = WidgetSnapshot(
            entries: [entry],
            enabledProviders: [.codex, .claude],
            generatedAt: Date())

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetSnapshot.self, from: data)

        #expect(decoded.entries.count == 1)
        #expect(decoded.entries.first?.provider == .codex)
        #expect(decoded.entries.first?.tokenUsage?.sessionTokens == 1200)
        #expect(decoded.entries.first?.usageRows?.map(\.id) == ["session", "weekly"])
        #expect(decoded.entries.first?.usageRows?.first?.detailText == "5 hours window")
        #expect(decoded.enabledProviders == [.codex, .claude])
    }

    @Test
    func `widget snapshot round trip preserves token labels`() throws {
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .cursor,
            updatedAt: Date(),
            primary: nil,
            secondary: nil,
            tertiary: nil,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: WidgetSnapshot.TokenUsageSummary(
                sessionCostUSD: nil,
                sessionTokens: 86_684_822,
                last30DaysCostUSD: nil,
                last30DaysTokens: nil,
                sessionLabel: "Cycle",
                last30DaysLabel: nil),
            dailyUsage: [])

        let snapshot = WidgetSnapshot(
            entries: [entry],
            enabledProviders: [.cursor],
            generatedAt: Date())

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetSnapshot.self, from: data)

        #expect(decoded.entries.first?.tokenUsage?.sessionLabel == "Cycle")
        #expect(decoded.entries.first?.tokenUsage?.last30DaysLabel == nil)
    }

    @Test
    func `widget snapshot round trip preserves provider cost period`() throws {
        let resetDate = Date(timeIntervalSince1970: 1_777_680_000)
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .claude,
            updatedAt: Date(),
            primary: nil,
            secondary: nil,
            tertiary: nil,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            providerCost: WidgetSnapshot.ProviderCostSummary(
                used: 12,
                limit: 200,
                currencyCode: "USD",
                period: "Monthly",
                resetsAt: resetDate),
            tokenUsage: nil,
            dailyUsage: [])

        let snapshot = WidgetSnapshot(
            entries: [entry],
            enabledProviders: [.claude],
            generatedAt: Date())

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetSnapshot.self, from: data)

        #expect(decoded.entries.first?.providerCost?.period == "Monthly")
        #expect(decoded.entries.first?.providerCost?.resetsAt == resetDate)
    }

    @Test
    func `widget snapshot round trip preserves kilo provider`() throws {
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .kilo,
            updatedAt: Date(),
            primary: RateWindow(usedPercent: 40, windowMinutes: nil, resetsAt: nil, resetDescription: "40/100 credits"),
            secondary: nil,
            tertiary: nil,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: WidgetSnapshot.TokenUsageSummary(
                sessionCostUSD: 1.25,
                sessionTokens: 4200,
                last30DaysCostUSD: 19.75,
                last30DaysTokens: 58000),
            dailyUsage: [
                WidgetSnapshot.DailyUsagePoint(dayKey: "2026-02-27", totalTokens: 4200, costUSD: 1.25),
            ])

        let snapshot = WidgetSnapshot(
            entries: [entry],
            enabledProviders: [.kilo, .codex],
            generatedAt: Date())

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetSnapshot.self, from: data)

        #expect(decoded.entries.first?.provider == .kilo)
        #expect(decoded.entries.first?.primary?.resetDescription == "40/100 credits")
        #expect(decoded.enabledProviders == [.kilo, .codex])
    }

    @Test
    func `widget snapshot round trip preserves kilo zero total edge state`() throws {
        let now = Date()
        let kiloSnapshot = KiloUsageSnapshot(
            creditsUsed: 0,
            creditsTotal: 0,
            creditsRemaining: 0,
            planName: "Kilo Pass Pro",
            autoTopUpEnabled: true,
            autoTopUpMethod: "visa",
            updatedAt: now).toUsageSnapshot()

        let entry = WidgetSnapshot.ProviderEntry(
            provider: .kilo,
            updatedAt: now,
            primary: kiloSnapshot.primary,
            secondary: kiloSnapshot.secondary,
            tertiary: kiloSnapshot.tertiary,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])

        let snapshot = WidgetSnapshot(
            entries: [entry],
            enabledProviders: [.kilo],
            generatedAt: now)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetSnapshot.self, from: data)

        #expect(decoded.entries.first?.provider == .kilo)
        #expect(decoded.entries.first?.primary?.usedPercent == 100)
        #expect(decoded.entries.first?.primary?.remainingPercent == 0)
        #expect(decoded.entries.first?.primary?.resetDescription == "0/0 credits")
        #expect(decoded.enabledProviders == [.kilo])
    }

    @Test
    func `widget snapshot round trip preserves cursor request details`() throws {
        let timestamp = Date(timeIntervalSince1970: 1_779_888_240)
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .cursor,
            updatedAt: Date(),
            primary: nil,
            secondary: nil,
            tertiary: nil,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: WidgetSnapshot.TokenUsageSummary(
                sessionCostUSD: nil,
                sessionTokens: 86_684_822,
                last30DaysCostUSD: nil,
                last30DaysTokens: nil,
                sessionLabel: "Cycle",
                last30DaysLabel: nil),
            cursorRequestRange: WidgetSnapshot.CursorRequestRange(
                start: timestamp,
                end: timestamp.addingTimeInterval(3600)),
            cursorRequestDetails: [
                WidgetSnapshot.CursorRequestDetail(
                    timestamp: timestamp,
                    model: "claude-opus-4-7-thinking-xhigh",
                    tokens: 1000,
                    requests: 1),
            ],
            dailyUsage: [])

        let snapshot = WidgetSnapshot(
            entries: [entry],
            enabledProviders: [.cursor],
            generatedAt: Date())

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetSnapshot.self, from: data)

        let detail = try #require(decoded.entries.first?.cursorRequestDetails?.first)
        #expect(detail.model == "claude-opus-4-7-thinking-xhigh")
        #expect(detail.tokens == 1000)
        #expect(detail.requests == 1)
        #expect(detail.timestamp == timestamp)
        #expect(decoded.entries.first?.cursorRequestRange?.start == timestamp)
        #expect(decoded.entries.first?.cursorRequestRange?.end == timestamp.addingTimeInterval(3600))
    }

    @Test
    func `widget snapshot round trip preserves session cost text override`() throws {
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .cursor,
            updatedAt: Date(),
            primary: nil,
            secondary: nil,
            tertiary: nil,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: WidgetSnapshot.TokenUsageSummary(
                sessionCostUSD: nil,
                sessionCostText: "Approx. $6.00-$30.00",
                sessionTokens: 2_000_000,
                last30DaysCostUSD: nil,
                last30DaysTokens: nil,
                sessionLabel: "Cycle",
                last30DaysLabel: nil),
            dailyUsage: [])

        let snapshot = WidgetSnapshot(
            entries: [entry],
            enabledProviders: [.cursor],
            generatedAt: Date())

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetSnapshot.self, from: data)

        #expect(decoded.entries.first?.tokenUsage?.sessionCostText == "Approx. $6.00-$30.00")
        #expect(decoded.entries.first?.tokenUsage?.sessionCostUSD == nil)
    }

    @Test
    func `widget snapshot decodes legacy payload without session cost text`() throws {
        let json = """
        {
          "entries": [
            {
              "provider": "cursor",
              "updatedAt": "2026-04-04T06:30:00Z",
              "primary": null,
              "secondary": null,
              "tertiary": null,
              "creditsRemaining": null,
              "codeReviewRemainingPercent": null,
              "tokenUsage": {
                "sessionCostUSD": 18,
                "sessionTokens": 2000000,
                "sessionLabel": "Cycle"
              },
              "dailyUsage": []
            }
          ],
          "enabledProviders": ["cursor"],
          "generatedAt": "2026-04-04T06:30:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetSnapshot.self, from: Data(json.utf8))

        #expect(decoded.entries.first?.tokenUsage?.sessionCostUSD == 18)
        #expect(decoded.entries.first?.tokenUsage?.sessionCostText == nil)
    }

    @Test
    func `widget snapshot decodes legacy payload without cursor request details`() throws {
        let json = """
        {
          "entries": [
            {
              "provider": "cursor",
              "updatedAt": "2026-04-04T06:30:00Z",
              "primary": null,
              "secondary": null,
              "tertiary": null,
              "creditsRemaining": null,
              "codeReviewRemainingPercent": null,
              "tokenUsage": {
                "sessionTokens": 100,
                "sessionLabel": "Cycle"
              },
              "dailyUsage": []
            }
          ],
          "enabledProviders": ["cursor"],
          "generatedAt": "2026-04-04T06:30:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetSnapshot.self, from: Data(json.utf8))

        #expect(decoded.entries.first?.cursorRequestDetails == nil)
    }

    @Test
    func `widget snapshot decodes legacy payload without usage rows`() throws {
        let json = """
        {
          "entries": [
            {
              "provider": "codex",
              "updatedAt": "2026-04-04T06:30:00Z",
              "primary": null,
              "secondary": {
                "usedPercent": 25,
                "windowMinutes": 10080,
                "resetsAt": null,
                "resetDescription": null
              },
              "tertiary": null,
              "creditsRemaining": null,
              "codeReviewRemainingPercent": null,
              "tokenUsage": null,
              "dailyUsage": []
            }
          ],
          "enabledProviders": ["codex"],
          "generatedAt": "2026-04-04T06:30:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetSnapshot.self, from: Data(json.utf8))

        #expect(decoded.entries.count == 1)
        #expect(decoded.entries.first?.usageRows == nil)
        #expect(decoded.entries.first?.secondary?.usedPercent == 25)
    }

    @Test
    func `widget snapshot round trip preserves cursor request compact details`() throws {
        let timestamp = Date(timeIntervalSince1970: 1_779_888_240)
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .cursor,
            updatedAt: Date(),
            primary: nil,
            secondary: nil,
            tertiary: nil,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            cursorRequestDetails: [
                WidgetSnapshot.CursorRequestDetail(
                    timestamp: timestamp,
                    model: "claude-opus-4-8-thinking-xhigh",
                    tokens: 34_972_000,
                    requests: 1,
                    compactModel: "Opus 4.8 · xhigh",
                    estimateText: "Est. $18.95"),
            ],
            dailyUsage: [])

        let snapshot = WidgetSnapshot(entries: [entry], enabledProviders: [.cursor], generatedAt: Date())

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetSnapshot.self, from: data)

        let detail = try #require(decoded.entries.first?.cursorRequestDetails?.first)
        #expect(detail.model == "claude-opus-4-8-thinking-xhigh")
        #expect(detail.tokens == 34_972_000)
        #expect(detail.requests == 1)
        #expect(detail.compactModel == "Opus 4.8 · xhigh")
        #expect(detail.estimateText == "Est. $18.95")
    }

    @Test
    func `widget snapshot decodes legacy cursor request detail without compact fields`() throws {
        let json = """
        {
          "entries": [
            {
              "provider": "cursor",
              "updatedAt": "2026-04-04T06:30:00Z",
              "primary": null,
              "secondary": null,
              "tertiary": null,
              "creditsRemaining": null,
              "codeReviewRemainingPercent": null,
              "tokenUsage": null,
              "cursorRequestDetails": [
                {
                  "timestamp": "2026-02-04T13:42:00Z",
                  "model": "claude-opus-4-7-thinking-xhigh",
                  "tokens": 1000,
                  "requests": 1
                }
              ],
              "dailyUsage": []
            }
          ],
          "enabledProviders": ["cursor"],
          "generatedAt": "2026-04-04T06:30:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetSnapshot.self, from: Data(json.utf8))

        let detail = try #require(decoded.entries.first?.cursorRequestDetails?.first)
        #expect(detail.tokens == 1000)
        #expect(detail.requests == 1)
        #expect(detail.compactModel == nil)
        #expect(detail.estimateText == nil)
    }
}
