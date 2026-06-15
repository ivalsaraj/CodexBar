import Foundation

public struct CursorTokenUsage: Codable, Sendable {
    public let billingCycleTokensUsed: Int
    public let requestCostSummary: CursorRequestCostSummary?

    public init(
        billingCycleTokensUsed: Int,
        requestCostSummary: CursorRequestCostSummary? = nil)
    {
        self.billingCycleTokensUsed = billingCycleTokensUsed
        self.requestCostSummary = requestCostSummary
    }
}
