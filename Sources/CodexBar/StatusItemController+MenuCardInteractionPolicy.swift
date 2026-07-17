import Foundation

extension StatusItemController {
    struct MenuCardInteractionPolicy: Equatable {
        let allowsHighlight: Bool
        let forwardsScrollToEmbeddedScrollView: Bool

        static let `default` = Self(allowsHighlight: true, forwardsScrollToEmbeddedScrollView: false)
        static let scrollableContent = Self(allowsHighlight: false, forwardsScrollToEmbeddedScrollView: true)
    }

    static func menuCardInteractionPolicy(for model: UsageMenuCardView.Model) -> MenuCardInteractionPolicy {
        guard model.provider == .cursor,
              let tokenUsage = model.tokenUsage
        else {
            return .default
        }
        let requestCount = max(
            tokenUsage.cursorRequestDetails.count,
            tokenUsage.cursorRangePresentations.values.map(\.cursorRequestDetails.count).max() ?? 0)
        guard requestCount > CursorMenuRequestDetailPresentation.maxVisibleRequestRows else {
            return .default
        }
        return .scrollableContent
    }
}
