import Foundation

/// Legacy Cursor quota usage snapshot.
public struct CursorRequestUsage: Codable, Sendable {
    public enum Metric: String, Codable, Sendable {
        case requests
        case tokens

        public var displayName: String {
            switch self {
            case .requests:
                "Requests"
            case .tokens:
                "Tokens"
            }
        }
    }

    /// Usage consumed this billing cycle.
    public let used: Int
    /// Usage limit for the active legacy quota.
    public let limit: Int
    public let metric: Metric

    public init(used: Int, limit: Int, metric: Metric = .requests) {
        self.used = used
        self.limit = limit
        self.metric = metric
    }

    public var usedPercent: Double {
        guard self.limit > 0 else { return 0 }
        return (Double(self.used) / Double(self.limit)) * 100
    }

    public var remainingPercent: Double {
        max(0, 100 - self.usedPercent)
    }

    public var summaryText: String {
        "\(self.metric.displayName): \(self.formatted(self.used)) / \(self.formatted(self.limit))"
    }

    private func formatted(_ value: Int) -> String {
        switch self.metric {
        case .tokens:
            return UsageFormatter.tokenCountString(value)
        case .requests:
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.locale = Locale(identifier: "en_US_POSIX")
            return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        }
    }
}
