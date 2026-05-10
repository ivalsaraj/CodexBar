import Foundation

public struct OpenCodeWorkspaceAccount: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let tokenAccountID: UUID
    public let label: String
    public let workspaceID: String
    public let workspaceLabel: String
    public let discoveredOwnerLabel: String?
    public let addedAt: TimeInterval
    public let lastValidatedAt: TimeInterval?

    public init(
        id: UUID,
        tokenAccountID: UUID,
        label: String,
        workspaceID: String,
        workspaceLabel: String,
        discoveredOwnerLabel: String?,
        addedAt: TimeInterval,
        lastValidatedAt: TimeInterval?)
    {
        self.id = id
        self.tokenAccountID = tokenAccountID
        self.label = label
        self.workspaceID = workspaceID
        self.workspaceLabel = workspaceLabel
        self.discoveredOwnerLabel = discoveredOwnerLabel
        self.addedAt = addedAt
        self.lastValidatedAt = lastValidatedAt
    }
}

public struct OpenCodeWorkspaceAccountData: Codable, Sendable, Equatable {
    public let version: Int
    public let activeAccountID: UUID?
    public let accounts: [OpenCodeWorkspaceAccount]

    public init(version: Int, activeAccountID: UUID?, accounts: [OpenCodeWorkspaceAccount]) {
        self.version = version
        self.activeAccountID = activeAccountID
        self.accounts = accounts
    }

    public func account(id: UUID) -> OpenCodeWorkspaceAccount? {
        self.accounts.first(where: { $0.id == id })
    }

    public var activeAccount: OpenCodeWorkspaceAccount? {
        if let activeAccountID, let account = self.account(id: activeAccountID) {
            return account
        }
        return self.accounts.first
    }

    public func pruned(validTokenAccountIDs: Set<UUID>) -> OpenCodeWorkspaceAccountData {
        let filtered = self.accounts.filter { validTokenAccountIDs.contains($0.tokenAccountID) }
        let nextActiveAccountID = filtered.contains(where: { $0.id == self.activeAccountID }) ?
            self.activeAccountID : filtered.first?.id
        return OpenCodeWorkspaceAccountData(
            version: self.version,
            activeAccountID: nextActiveAccountID,
            accounts: filtered)
    }
}
