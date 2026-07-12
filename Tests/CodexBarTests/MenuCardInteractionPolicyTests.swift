import CodexBarCore
import Foundation
import SwiftUI
import Testing
@testable import CodexBar

@MainActor
struct MenuCardInteractionPolicyTests {
    @Test
    func `cursor overflow menu card policy disables full card highlight and forwards scroll`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let model = self.menuCardModel(
            provider: .cursor,
            tokenUsage: .init(
                title: "Tokens",
                sessionLine: "Cycle: 10M tokens",
                monthLine: "Requests: 30 / 500",
                cursorRequestDetails: self.cursorRequests(
                    count: CursorMenuRequestDetailPresentation.maxVisibleRequestRows + 1,
                    now: now),
                cursorRequestNow: now,
                renewalLine: nil,
                hintLine: nil,
                errorLine: nil,
                errorCopyText: nil))

        let policy = StatusItemController.menuCardInteractionPolicy(for: model)

        #expect(policy.allowsHighlight == false)
        #expect(policy.forwardsScrollToEmbeddedScrollView)
    }

    @Test
    func `non overflow menu cards keep default interaction policy`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let cursorModel = self.menuCardModel(
            provider: .cursor,
            tokenUsage: .init(
                title: "Tokens",
                sessionLine: "Cycle: 10M tokens",
                monthLine: "Requests: 6 / 500",
                cursorRequestDetails: [],
                cursorRequestNow: now,
                renewalLine: nil,
                hintLine: nil,
                errorLine: nil,
                errorCopyText: nil))
        let codexModel = self.menuCardModel(
            provider: .codex,
            tokenUsage: .init(
                title: "Tokens",
                sessionLine: "Today: $1.00",
                monthLine: nil,
                detailLines: ["Last 30 days: $3.00"],
                renewalLine: nil,
                hintLine: nil,
                errorLine: nil,
                errorCopyText: nil))

        #expect(StatusItemController.menuCardInteractionPolicy(for: cursorModel) == .default)
        #expect(StatusItemController.menuCardInteractionPolicy(for: codexModel) == .default)
    }

    @Test
    func `one expanded cursor request remains scrollable`() {
        let model = self.menuCardModel(
            provider: .cursor,
            tokenUsage: .init(
                title: "Tokens",
                sessionLine: "Cycle: 10M tokens",
                monthLine: "Requests: 1 / 500",
                cursorRequestDetails: self.cursorRequests(count: 1, now: Date(timeIntervalSince1970: 1_700_000_000)),
                cursorRequestNow: Date(timeIntervalSince1970: 1_700_000_000),
                renewalLine: nil,
                hintLine: nil,
                errorLine: nil,
                errorCopyText: nil))

        let policy = StatusItemController.menuCardInteractionPolicy(for: model)

        #expect(policy.allowsHighlight == false)
        #expect(policy.forwardsScrollToEmbeddedScrollView)
    }

    private func cursorRequests(count: Int, now: Date) -> [CursorRecentRequest] {
        (0..<count).map { index in
            CursorRecentRequest(
                timestamp: now.addingTimeInterval(Double(-index * 60)),
                model: "model-\(index)",
                tokens: 100_000 + index,
                requests: 1)
        }
    }

    private func menuCardModel(
        provider: UsageProvider,
        tokenUsage: UsageMenuCardView.Model.TokenUsageSection) -> UsageMenuCardView.Model
    {
        UsageMenuCardView.Model(
            provider: provider,
            providerName: provider.rawValue,
            email: "",
            subtitleText: "",
            subtitleStyle: .info,
            planText: nil,
            metrics: [],
            usageNotes: [],
            creditsText: nil,
            creditsRemaining: nil,
            creditsHintText: nil,
            creditsHintCopyText: nil,
            providerCost: nil,
            tokenUsage: tokenUsage,
            placeholder: nil,
            progressColor: .blue)
    }
}
