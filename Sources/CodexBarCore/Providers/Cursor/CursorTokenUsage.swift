import Foundation

public struct CursorTokenUsage: Codable, Sendable {
    public let billingCycleTokensUsed: Int

    public init(billingCycleTokensUsed: Int) {
        self.billingCycleTokensUsed = billingCycleTokensUsed
    }
}
