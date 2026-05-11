import CodexBarCore
import Foundation
import Testing

struct OpenCodeWorkspaceAccountsTests {
    @Test
    func `active account resolves from active account id`() {
        let tokenAccountID = UUID()
        let firstID = UUID()
        let secondID = UUID()
        let data = OpenCodeWorkspaceAccountData(
            version: 1,
            activeAccountID: secondID,
            accounts: [
                OpenCodeWorkspaceAccount(
                    id: firstID,
                    tokenAccountID: tokenAccountID,
                    label: "Alpha",
                    workspaceID: "wrk_alpha",
                    workspaceLabel: "Alpha Workspace",
                    discoveredOwnerLabel: nil,
                    addedAt: 100,
                    lastValidatedAt: 150),
                OpenCodeWorkspaceAccount(
                    id: secondID,
                    tokenAccountID: tokenAccountID,
                    label: "Beta",
                    workspaceID: "wrk_beta",
                    workspaceLabel: "Beta Workspace",
                    discoveredOwnerLabel: "Team Beta",
                    addedAt: 200,
                    lastValidatedAt: 250),
            ])

        #expect(data.activeAccount?.id == secondID)
        #expect(data.account(id: firstID)?.workspaceID == "wrk_alpha")
    }

    @Test
    func `pruning invalid token references removes dangling accounts and repairs active selection`() {
        let validTokenID = UUID()
        let staleTokenID = UUID()
        let validAccountID = UUID()
        let staleAccountID = UUID()
        let data = OpenCodeWorkspaceAccountData(
            version: 1,
            activeAccountID: staleAccountID,
            accounts: [
                OpenCodeWorkspaceAccount(
                    id: validAccountID,
                    tokenAccountID: validTokenID,
                    label: "Valid",
                    workspaceID: "wrk_valid",
                    workspaceLabel: "Valid Workspace",
                    discoveredOwnerLabel: nil,
                    addedAt: 100,
                    lastValidatedAt: nil),
                OpenCodeWorkspaceAccount(
                    id: staleAccountID,
                    tokenAccountID: staleTokenID,
                    label: "Stale",
                    workspaceID: "wrk_stale",
                    workspaceLabel: "Stale Workspace",
                    discoveredOwnerLabel: nil,
                    addedAt: 200,
                    lastValidatedAt: nil),
            ])

        let pruned = data.pruned(validTokenAccountIDs: [validTokenID])

        #expect(pruned.accounts.map(\.id) == [validAccountID])
        #expect(pruned.activeAccountID == validAccountID)
        #expect(pruned.activeAccount?.workspaceID == "wrk_valid")
    }
}
