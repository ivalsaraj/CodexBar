import Foundation

public struct CodexBarConfig: Codable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var providers: [ProviderConfig]

    public init(version: Int = Self.currentVersion, providers: [ProviderConfig]) {
        self.version = version
        self.providers = providers
    }

    public static func makeDefault(
        metadata: [UsageProvider: ProviderMetadata] = ProviderDescriptorRegistry.metadata) -> CodexBarConfig
    {
        let providers = UsageProvider.allCases.map { provider in
            ProviderConfig(
                id: provider,
                enabled: metadata[provider]?.defaultEnabled)
        }
        return CodexBarConfig(version: Self.currentVersion, providers: providers)
    }

    public func normalized(
        metadata: [UsageProvider: ProviderMetadata] = ProviderDescriptorRegistry.metadata) -> CodexBarConfig
    {
        var seen: Set<UsageProvider> = []
        var normalized: [ProviderConfig] = []
        normalized.reserveCapacity(max(self.providers.count, UsageProvider.allCases.count))

        for provider in self.providers {
            guard !seen.contains(provider.id) else { continue }
            seen.insert(provider.id)
            normalized.append(provider)
        }

        for provider in UsageProvider.allCases where !seen.contains(provider) {
            normalized.append(ProviderConfig(
                id: provider,
                enabled: metadata[provider]?.defaultEnabled))
        }

        return CodexBarConfig(
            version: Self.currentVersion,
            providers: normalized)
    }

    public func orderedProviders() -> [UsageProvider] {
        self.providers.map(\.id)
    }

    public func enabledProviders(
        metadata: [UsageProvider: ProviderMetadata] = ProviderDescriptorRegistry.metadata) -> [UsageProvider]
    {
        self.providers.compactMap { config in
            let enabled = config.enabled ?? metadata[config.id]?.defaultEnabled ?? false
            return enabled ? config.id : nil
        }
    }

    public func providerConfig(for id: UsageProvider) -> ProviderConfig? {
        self.providers.first(where: { $0.id == id })
    }

    public mutating func setProviderConfig(_ config: ProviderConfig) {
        if let index = self.providers.firstIndex(where: { $0.id == config.id }) {
            self.providers[index] = config
        } else {
            self.providers.append(config)
        }
    }
}

public struct ProviderConfig: Codable, Sendable, Identifiable {
    public let id: UsageProvider
    public var enabled: Bool?
    public var source: ProviderSourceMode?
    public var extrasEnabled: Bool?
    public var apiKey: String?
    public var cookieHeader: String?
    public var cookieSource: ProviderCookieSource?
    public var region: String?
    public var workspaceID: String?
    public var opencodeWorkspaceAccounts: OpenCodeWorkspaceAccounts?
    public var opencodeActiveWorkspaceAccountID: String?
    public var enterpriseHost: String?
    public var tokenAccounts: ProviderTokenAccountData?
    public var codexActiveSource: CodexActiveSource?

    public init(
        id: UsageProvider,
        enabled: Bool? = nil,
        source: ProviderSourceMode? = nil,
        extrasEnabled: Bool? = nil,
        apiKey: String? = nil,
        cookieHeader: String? = nil,
        cookieSource: ProviderCookieSource? = nil,
        region: String? = nil,
        workspaceID: String? = nil,
        opencodeWorkspaceAccounts: OpenCodeWorkspaceAccounts? = nil,
        opencodeActiveWorkspaceAccountID: String? = nil,
        enterpriseHost: String? = nil,
        tokenAccounts: ProviderTokenAccountData? = nil,
        codexActiveSource: CodexActiveSource? = nil)
    {
        self.id = id
        self.enabled = enabled
        self.source = source
        self.extrasEnabled = extrasEnabled
        self.apiKey = apiKey
        self.cookieHeader = cookieHeader
        self.cookieSource = cookieSource
        self.region = region
        self.workspaceID = workspaceID
        self.opencodeWorkspaceAccounts = opencodeWorkspaceAccounts
        self.opencodeActiveWorkspaceAccountID = opencodeActiveWorkspaceAccountID
        self.enterpriseHost = enterpriseHost
        self.tokenAccounts = tokenAccounts
        self.codexActiveSource = codexActiveSource
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case enabled
        case source
        case extrasEnabled
        case apiKey
        case cookieHeader
        case cookieSource
        case region
        case workspaceID
        case opencodeWorkspaceAccounts
        case openCodeWorkspaceAccounts
        case opencodeActiveWorkspaceAccountID
        case enterpriseHost
        case tokenAccounts
        case codexActiveSource
    }

    private struct LegacyOpenCodeWorkspaceAccountData: Decodable {
        let activeAccountID: UUID?
        let accounts: [LegacyOpenCodeWorkspaceAccount]
    }

    private struct LegacyOpenCodeWorkspaceAccount: Decodable {
        let id: UUID
        let tokenAccountID: UUID
        let label: String?
        let workspaceID: String
        let workspaceLabel: String?
        let discoveredOwnerLabel: String?
        let addedAt: TimeInterval?
        let lastValidatedAt: TimeInterval?
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let currentAccounts = try container.decodeIfPresent(
            OpenCodeWorkspaceAccounts.self,
            forKey: .opencodeWorkspaceAccounts)
        let accounts = try currentAccounts ?? Self.migrateLegacyOpenCodeWorkspaceAccounts(
            container.decodeIfPresent(
                LegacyOpenCodeWorkspaceAccountData.self,
                forKey: .openCodeWorkspaceAccounts))

        try self.init(
            id: container.decode(UsageProvider.self, forKey: .id),
            enabled: container.decodeIfPresent(Bool.self, forKey: .enabled),
            source: container.decodeIfPresent(ProviderSourceMode.self, forKey: .source),
            extrasEnabled: container.decodeIfPresent(Bool.self, forKey: .extrasEnabled),
            apiKey: container.decodeIfPresent(String.self, forKey: .apiKey),
            cookieHeader: container.decodeIfPresent(String.self, forKey: .cookieHeader),
            cookieSource: container.decodeIfPresent(ProviderCookieSource.self, forKey: .cookieSource),
            region: container.decodeIfPresent(String.self, forKey: .region),
            workspaceID: container.decodeIfPresent(String.self, forKey: .workspaceID),
            opencodeWorkspaceAccounts: accounts,
            opencodeActiveWorkspaceAccountID: container.decodeIfPresent(
                String.self,
                forKey: .opencodeActiveWorkspaceAccountID),
            enterpriseHost: container.decodeIfPresent(String.self, forKey: .enterpriseHost),
            tokenAccounts: container.decodeIfPresent(ProviderTokenAccountData.self, forKey: .tokenAccounts),
            codexActiveSource: container.decodeIfPresent(CodexActiveSource.self, forKey: .codexActiveSource))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.id, forKey: .id)
        try container.encodeIfPresent(self.enabled, forKey: .enabled)
        try container.encodeIfPresent(self.source, forKey: .source)
        try container.encodeIfPresent(self.extrasEnabled, forKey: .extrasEnabled)
        try container.encodeIfPresent(self.apiKey, forKey: .apiKey)
        try container.encodeIfPresent(self.cookieHeader, forKey: .cookieHeader)
        try container.encodeIfPresent(self.cookieSource, forKey: .cookieSource)
        try container.encodeIfPresent(self.region, forKey: .region)
        try container.encodeIfPresent(self.workspaceID, forKey: .workspaceID)
        try container.encodeIfPresent(self.opencodeWorkspaceAccounts, forKey: .opencodeWorkspaceAccounts)
        try container.encodeIfPresent(
            self.opencodeActiveWorkspaceAccountID,
            forKey: .opencodeActiveWorkspaceAccountID)
        try container.encodeIfPresent(self.enterpriseHost, forKey: .enterpriseHost)
        try container.encodeIfPresent(self.tokenAccounts, forKey: .tokenAccounts)
        try container.encodeIfPresent(self.codexActiveSource, forKey: .codexActiveSource)
    }

    private static func migrateLegacyOpenCodeWorkspaceAccounts(
        _ data: LegacyOpenCodeWorkspaceAccountData?) -> OpenCodeWorkspaceAccounts?
    {
        guard let data else { return nil }
        var accounts: [OpenCodeWorkspaceAccount] = []
        var activeID: String?
        for legacy in data.accounts {
            let label = legacy.workspaceLabel ?? legacy.label ?? legacy.workspaceID
            let createdAt = legacy.addedAt ?? 0
            let updatedAt = max(createdAt, legacy.lastValidatedAt ?? createdAt)
            guard let account = OpenCodeWorkspaceAccount(
                tokenAccountID: legacy.tokenAccountID,
                workspaceID: legacy.workspaceID,
                label: label,
                ownerLabel: legacy.discoveredOwnerLabel,
                createdAt: createdAt,
                updatedAt: updatedAt)
            else {
                continue
            }
            accounts.append(account)
            if legacy.id == data.activeAccountID {
                activeID = account.id
            }
        }
        return OpenCodeWorkspaceAccounts(accounts: accounts, activeID: activeID)
    }

    public var sanitizedAPIKey: String? {
        Self.clean(self.apiKey)
    }

    public var sanitizedCookieHeader: String? {
        Self.clean(self.cookieHeader)
    }

    public var sanitizedEnterpriseHost: String? {
        Self.clean(self.enterpriseHost)
    }

    private static func clean(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
            (value.hasPrefix("'") && value.hasSuffix("'"))
        {
            value.removeFirst()
            value.removeLast()
        }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
