import Foundation
import Testing
@testable import CodexBarCore
@testable import CodexBarWidget

struct CodexBarWidgetProviderTests {
    @Test
    func `provider choice supports alibaba`() {
        #expect(ProviderChoice(provider: .alibaba) == .alibaba)
        #expect(ProviderChoice.alibaba.provider == .alibaba)
    }

    @Test
    func `provider choice supports cursor`() {
        #expect(ProviderChoice(provider: .cursor) == .cursor)
        #expect(ProviderChoice.cursor.provider == .cursor)
    }

    @Test
    func `provider choice supports opencode go`() {
        #expect(ProviderChoice(provider: .opencodego) == .opencodego)
        #expect(ProviderChoice.opencodego.provider == .opencodego)
    }

    @Test
    func `provider cost period line includes renewal when available`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let resetAt = now.addingTimeInterval(6 * 24 * 60 * 60)
        let cost = WidgetSnapshot.ProviderCostSummary(
            used: 12,
            limit: 200,
            currencyCode: "USD",
            period: "Monthly",
            resetsAt: resetAt)

        #expect(WidgetFormat.providerCostPeriodLine(cost, now: now) == "Monthly · renews in 6 days")
    }

    @Test
    func `supported providers keep alibaba when it is the only enabled provider`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .alibaba,
            updatedAt: now,
            primary: nil,
            secondary: nil,
            tertiary: nil,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])
        let snapshot = WidgetSnapshot(entries: [entry], enabledProviders: [.alibaba], generatedAt: now)

        #expect(CodexBarSwitcherTimelineProvider.supportedProviders(from: snapshot) == [.alibaba])
    }

    @Test
    func `codex weekly only widget rows omit session`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .codex,
            updatedAt: now,
            primary: nil,
            secondary: RateWindow(usedPercent: 25, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
            tertiary: nil,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])

        let rows = WidgetUsageRow.rows(for: entry)

        #expect(rows.count == 1)
        #expect(rows.first?.title == "Weekly")
        #expect(rows.first?.percentLeft == 75)
    }

    @Test
    func `codex widget usage rows keep code review separate from rate rows`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .codex,
            updatedAt: now,
            primary: RateWindow(usedPercent: 10, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 25, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
            tertiary: nil,
            creditsRemaining: nil,
            codeReviewRemainingPercent: 60,
            tokenUsage: nil,
            dailyUsage: [])

        let rows = WidgetUsageRow.rows(for: entry)

        #expect(rows.map(\.title) == ["Session", "Weekly"])
        #expect(rows.count == 2)
        #expect(!rows.contains { $0.title == "Code review" })
    }

    @Test
    func `widget usage rows prefer projected rows over legacy slots`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .codex,
            updatedAt: now,
            primary: RateWindow(usedPercent: 10, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 25, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
            tertiary: nil,
            usageRows: [
                WidgetSnapshot.WidgetUsageRowSnapshot(
                    id: "weekly",
                    title: "Weekly",
                    percentLeft: 75,
                    detailText: "7 days window"),
            ],
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])

        let rows = WidgetUsageRow.rows(for: entry)

        #expect(rows == [WidgetUsageRow(id: "weekly", title: "Weekly", percentLeft: 75, detailText: "7 days window")])
    }

    @Test
    func `cursor request presentation limits medium widget rows`() {
        let details = (0..<10).map { index in
            WidgetSnapshot.CursorRequestDetail(
                timestamp: Date(timeIntervalSince1970: Double(index)),
                model: "model-\(index)",
                tokens: 100,
                requests: 1)
        }

        let selection = CursorWidgetRequestPresentation.selection(
            provider: .cursor,
            details: details,
            range: WidgetSnapshot.CursorRequestRange(
                start: Date(timeIntervalSince1970: 0),
                end: Date(timeIntervalSince1970: 60)),
            size: .medium)

        #expect(selection?.visible.count == 3)
        #expect(selection?.visible.map(\.model) == ["model-0", "model-1", "model-2"])
        #expect(selection?.hiddenCount == 7)
        #expect(selection?.range?.start == Date(timeIntervalSince1970: 0))
    }

    @Test
    func `cursor request presentation limits large widget rows`() {
        let details = (0..<10).map { index in
            WidgetSnapshot.CursorRequestDetail(
                timestamp: Date(timeIntervalSince1970: Double(index)),
                model: "model-\(index)",
                tokens: 100,
                requests: 1)
        }

        let selection = CursorWidgetRequestPresentation.selection(
            provider: .cursor,
            details: details,
            size: .large)

        #expect(selection?.visible.count == 5)
        #expect(selection?.hiddenCount == 5)
    }

    @Test
    func `cursor request presentation returns nil for non cursor providers`() {
        let details = [
            WidgetSnapshot.CursorRequestDetail(
                timestamp: Date(),
                model: "composer-2",
                tokens: 100,
                requests: 1),
        ]

        #expect(
            CursorWidgetRequestPresentation.selection(
                provider: .codex,
                details: details,
                size: .large) == nil)
    }

    @Test
    func `cursor request rows use compact model text not raw model`() throws {
        let details = [
            WidgetSnapshot.CursorRequestDetail(
                timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                model: "claude-opus-4-8-thinking-xhigh",
                tokens: 35_000_000,
                requests: 1,
                requestCost: 2,
                compactModel: "Opus 4.8 · xhigh",
                estimateText: "Est. $12.34"),
        ]

        let selection = try #require(CursorWidgetRequestPresentation.selection(
            provider: .cursor,
            details: details,
            size: .medium))
        let row = try #require(selection.rows.first)
        #expect(row.modelText == "Opus 4.8 · xhigh")
        #expect(!row.modelText.contains("claude-opus"))
        #expect(row.tokenText == "35M")
        #expect(row.metaText.contains("Req 2"))
        #expect(row.metaText.contains(WidgetFormat.requestDateTime(details[0].timestamp)))
        #expect(row.estimateText == "Est. $12.34")
    }

    @Test
    func `cursor request rows keep request count for zero token rows`() throws {
        let details = [
            WidgetSnapshot.CursorRequestDetail(
                timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                model: "claude-opus-4-8-thinking-xhigh",
                tokens: 0,
                requests: 1,
                compactModel: "Opus 4.8 · xhigh",
                estimateText: nil),
        ]

        let selection = try #require(CursorWidgetRequestPresentation.selection(
            provider: .cursor,
            details: details,
            size: .medium))
        let row = try #require(selection.rows.first)
        #expect(row.metaText.contains("Req 1"))
        #expect(row.estimateText == nil)
    }

    @Test
    func `cursor request rows fall back to raw model for legacy snapshots`() throws {
        let details = [
            WidgetSnapshot.CursorRequestDetail(
                timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                model: "composer-2.5",
                tokens: 100,
                requests: 1),
        ]

        let selection = try #require(CursorWidgetRequestPresentation.selection(
            provider: .cursor,
            details: details,
            size: .large))
        let row = try #require(selection.rows.first)
        #expect(row.modelText == "composer-2.5")
        #expect(row.estimateText == nil)
    }

    @Test
    func `widget selection store preserves opencode workspace account selection`() {
        let bundleID = "com.steipete.codexbar.tests.widget-selection-\(UUID().uuidString)"
        let accountID = UUID()

        WidgetSelectionStore.saveSelectedProvider(.opencode, bundleID: bundleID)
        WidgetSelectionStore.saveSelectedAccountID(accountID, for: .opencode, bundleID: bundleID)
        WidgetSelectionStore.saveSelectedProvider(.codex, bundleID: bundleID)

        #expect(WidgetSelectionStore.loadSelectedProvider(bundleID: bundleID) == .codex)
        #expect(WidgetSelectionStore.loadSelectedAccountID(for: .opencode, bundleID: bundleID) == accountID)
    }
}
