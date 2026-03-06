import CodexBarCore
import Foundation

struct ProviderUtilizationHistoryPoint: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let timestamp: Date
    let primaryUsedPercent: Double
    let secondaryUsedPercent: Double?

    init(
        id: UUID = UUID(),
        timestamp: Date,
        primaryUsedPercent: Double,
        secondaryUsedPercent: Double?)
    {
        self.id = id
        self.timestamp = timestamp
        self.primaryUsedPercent = primaryUsedPercent
        self.secondaryUsedPercent = secondaryUsedPercent
    }
}

enum ProviderUtilizationTimeRange: String, CaseIterable, Identifiable {
    case hour1 = "1h"
    case hour6 = "6h"
    case day1 = "1d"
    case day7 = "7d"
    case day30 = "30d"

    var id: String {
        self.rawValue
    }

    var interval: TimeInterval {
        switch self {
        case .hour1: 60 * 60
        case .hour6: 6 * 60 * 60
        case .day1: 24 * 60 * 60
        case .day7: 7 * 24 * 60 * 60
        case .day30: 30 * 24 * 60 * 60
        }
    }

    var targetPointCount: Int {
        switch self {
        case .hour1: 120
        case .hour6: 180
        case .day1, .day7, .day30: 200
        }
    }
}
