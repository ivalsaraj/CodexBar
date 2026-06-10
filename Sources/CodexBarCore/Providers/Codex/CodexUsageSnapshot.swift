import Foundation

public struct CodexUsageSnapshot: Codable, Equatable, Sendable {
    public let sparkLimit: RateWindow?
    public let subscriptionRenewalAt: Date?

    public init(sparkLimit: RateWindow? = nil, subscriptionRenewalAt: Date? = nil) {
        self.sparkLimit = sparkLimit
        self.subscriptionRenewalAt = subscriptionRenewalAt
    }
}
