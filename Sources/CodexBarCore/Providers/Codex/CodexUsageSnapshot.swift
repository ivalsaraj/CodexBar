import Foundation

public struct CodexUsageSnapshot: Codable, Equatable, Sendable {
    public let sparkLimit: RateWindow?

    public init(sparkLimit: RateWindow?) {
        self.sparkLimit = sparkLimit
    }
}
