import Foundation

public struct WidgetSnapshot: Codable, Sendable {
    public struct WidgetUsageRowSnapshot: Codable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let percentLeft: Double?
        public let detailText: String?

        public init(id: String, title: String, percentLeft: Double?, detailText: String? = nil) {
            self.id = id
            self.title = title
            self.percentLeft = percentLeft
            self.detailText = detailText
        }
    }

    public struct ProviderEntry: Codable, Sendable {
        public let provider: UsageProvider
        public let accountID: UUID?
        public let accountLabel: String?
        public let updatedAt: Date
        public let primary: RateWindow?
        public let secondary: RateWindow?
        public let tertiary: RateWindow?
        public let usageRows: [WidgetUsageRowSnapshot]?
        public let creditsRemaining: Double?
        public let codeReviewRemainingPercent: Double?
        public let providerCost: ProviderCostSummary?
        public let tokenUsage: TokenUsageSummary?
        public let dailyUsage: [DailyUsagePoint]

        public init(
            provider: UsageProvider,
            accountID: UUID? = nil,
            accountLabel: String? = nil,
            updatedAt: Date,
            primary: RateWindow?,
            secondary: RateWindow?,
            tertiary: RateWindow?,
            usageRows: [WidgetUsageRowSnapshot]? = nil,
            creditsRemaining: Double?,
            codeReviewRemainingPercent: Double?,
            providerCost: ProviderCostSummary? = nil,
            tokenUsage: TokenUsageSummary?,
            dailyUsage: [DailyUsagePoint])
        {
            self.provider = provider
            self.accountID = accountID
            self.accountLabel = accountLabel
            self.updatedAt = updatedAt
            self.primary = primary
            self.secondary = secondary
            self.tertiary = tertiary
            self.usageRows = usageRows
            self.creditsRemaining = creditsRemaining
            self.codeReviewRemainingPercent = codeReviewRemainingPercent
            self.providerCost = providerCost
            self.tokenUsage = tokenUsage
            self.dailyUsage = dailyUsage
        }
    }

    public struct ProviderCostSummary: Codable, Equatable, Sendable {
        public let used: Double
        public let limit: Double
        public let currencyCode: String
        public let period: String?
        public let resetsAt: Date?

        public init(
            used: Double,
            limit: Double,
            currencyCode: String,
            period: String?,
            resetsAt: Date?)
        {
            self.used = used
            self.limit = limit
            self.currencyCode = currencyCode
            self.period = period
            self.resetsAt = resetsAt
        }
    }

    public struct TokenUsageSummary: Codable, Sendable {
        public let sessionCostUSD: Double?
        public let sessionCostText: String?
        public let sessionTokens: Int?
        public let last30DaysCostUSD: Double?
        public let last30DaysTokens: Int?
        public let sessionLabel: String?
        public let last30DaysLabel: String?

        public init(
            sessionCostUSD: Double?,
            sessionCostText: String? = nil,
            sessionTokens: Int?,
            last30DaysCostUSD: Double?,
            last30DaysTokens: Int?,
            sessionLabel: String? = nil,
            last30DaysLabel: String? = nil)
        {
            self.sessionCostUSD = sessionCostUSD
            self.sessionCostText = sessionCostText
            self.sessionTokens = sessionTokens
            self.last30DaysCostUSD = last30DaysCostUSD
            self.last30DaysTokens = last30DaysTokens
            self.sessionLabel = sessionLabel
            self.last30DaysLabel = last30DaysLabel
        }
    }

    public struct DailyUsagePoint: Codable, Sendable {
        public let dayKey: String
        public let totalTokens: Int?
        public let costUSD: Double?

        public init(dayKey: String, totalTokens: Int?, costUSD: Double?) {
            self.dayKey = dayKey
            self.totalTokens = totalTokens
            self.costUSD = costUSD
        }
    }

    public let entries: [ProviderEntry]
    public let enabledProviders: [UsageProvider]
    public let generatedAt: Date

    public init(entries: [ProviderEntry], enabledProviders: [UsageProvider]? = nil, generatedAt: Date) {
        self.entries = entries
        self.enabledProviders = enabledProviders ?? entries.map(\.provider)
        self.generatedAt = generatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case entries
        case enabledProviders
        case generatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.entries = try container.decode([ProviderEntry].self, forKey: .entries)
        self.generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        self.enabledProviders = try container.decodeIfPresent([UsageProvider].self, forKey: .enabledProviders)
            ?? self.entries.map(\.provider)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.entries, forKey: .entries)
        try container.encode(self.enabledProviders, forKey: .enabledProviders)
        try container.encode(self.generatedAt, forKey: .generatedAt)
    }

    public func entries(for provider: UsageProvider) -> [ProviderEntry] {
        self.entries.filter { $0.provider == provider }
    }

    public func entry(for provider: UsageProvider, accountID: UUID? = nil) -> ProviderEntry? {
        if let accountID {
            return self.entries.first { entry in
                entry.provider == provider && entry.accountID == accountID
            }
        }
        return self.entries.first { $0.provider == provider }
    }
}

public enum WidgetSnapshotStore {
    private static let filename = AppGroupSupport.widgetSnapshotFilename

    public static func load(bundleID: String? = Bundle.main.bundleIdentifier) -> WidgetSnapshot? {
        let url = self.snapshotURL(bundleID: bundleID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? self.decoder.decode(WidgetSnapshot.self, from: data)
    }

    public static func save(_ snapshot: WidgetSnapshot, bundleID: String? = Bundle.main.bundleIdentifier) {
        let url = self.snapshotURL(bundleID: bundleID)
        do {
            let data = try self.encoder.encode(snapshot)
            try data.write(to: url, options: [.atomic])
        } catch {
            return
        }
    }

    private static func snapshotURL(bundleID: String?) -> URL {
        AppGroupSupport.snapshotURL(bundleID: bundleID)
    }

    public static func appGroupID(for bundleID: String?) -> String? {
        AppGroupSupport.currentGroupID(for: bundleID)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public enum WidgetSelectionStore {
    private static let selectedProviderKey = "widgetSelectedProvider"
    private static let selectedAccountIDPrefix = "widgetSelectedAccountID."

    public static func loadSelectedProvider(bundleID: String? = Bundle.main.bundleIdentifier) -> UsageProvider? {
        let defaults = self.sharedDefaults(bundleID: bundleID)
        guard let raw = defaults.string(forKey: self.selectedProviderKey) else { return nil }
        return UsageProvider(rawValue: raw)
    }

    public static func saveSelectedProvider(
        _ provider: UsageProvider,
        bundleID: String? = Bundle.main.bundleIdentifier)
    {
        let defaults = self.sharedDefaults(bundleID: bundleID)
        defaults.set(provider.rawValue, forKey: self.selectedProviderKey)
    }

    public static func loadSelectedAccountID(
        for provider: UsageProvider,
        bundleID: String? = Bundle.main.bundleIdentifier) -> UUID?
    {
        let defaults = self.sharedDefaults(bundleID: bundleID)
        guard let raw = defaults.string(forKey: self.selectedAccountIDKey(for: provider)) else { return nil }
        return UUID(uuidString: raw)
    }

    public static func saveSelectedAccountID(
        _ accountID: UUID?,
        for provider: UsageProvider,
        bundleID: String? = Bundle.main.bundleIdentifier)
    {
        let defaults = self.sharedDefaults(bundleID: bundleID)
        let key = self.selectedAccountIDKey(for: provider)
        if let accountID {
            defaults.set(accountID.uuidString, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private static func sharedDefaults(bundleID: String?) -> UserDefaults {
        AppGroupSupport.sharedDefaults(bundleID: bundleID) ?? .standard
    }

    private static func selectedAccountIDKey(for provider: UsageProvider) -> String {
        "\(self.selectedAccountIDPrefix)\(provider.rawValue)"
    }
}
