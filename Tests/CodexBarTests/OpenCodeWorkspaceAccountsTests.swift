import Foundation
import Testing
@testable import CodexBarCore

struct OpenCodeWorkspaceAccountsTests {
    @Test
    func `canonical I ds distinguish workspaces while remaining stable for same pair`() throws {
        let tokenAccountID = try #require(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"))
        let first = try #require(OpenCodeWorkspaceAccount(
            tokenAccountID: tokenAccountID,
            workspaceID: "https://opencode.ai/workspace/wrk_ALPHA/billing",
            label: "Alpha",
            now: Date(timeIntervalSince1970: 100)))
        let same = try #require(OpenCodeWorkspaceAccount(
            tokenAccountID: tokenAccountID,
            workspaceID: "wrk_ALPHA",
            label: "Renamed",
            now: Date(timeIntervalSince1970: 200)))
        let second = try #require(OpenCodeWorkspaceAccount(
            tokenAccountID: tokenAccountID,
            workspaceID: "wrk_BETA",
            label: "Beta",
            now: Date(timeIntervalSince1970: 100)))

        #expect(first.id == same.id)
        #expect(first.id != second.id)
        #expect(first.workspaceID == "wrk_ALPHA")
    }

    @Test
    func `deduplicates accounts and preserves active workspace`() throws {
        let tokenAccountID = try #require(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"))
        let alpha = try #require(OpenCodeWorkspaceAccount(
            tokenAccountID: tokenAccountID,
            workspaceID: "wrk_ALPHA",
            label: "Alpha",
            now: Date(timeIntervalSince1970: 100)))
        let beta = try #require(OpenCodeWorkspaceAccount(
            tokenAccountID: tokenAccountID,
            workspaceID: "wrk_BETA",
            label: "Beta",
            now: Date(timeIntervalSince1970: 200)))
        var accounts = OpenCodeWorkspaceAccounts(accounts: [alpha])

        #expect(accounts.upsert(alpha) == .duplicate)
        #expect(accounts.upsert(beta) == .saved)
        let selected = accounts.selectActive(id: beta.id)
        #expect(selected)
        #expect(accounts.active?.id == beta.id)
    }

    @Test
    func `pruning removes deleted token accounts and falls back deterministically`() throws {
        let firstToken = try #require(UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"))
        let secondToken = try #require(UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD"))
        let first = try #require(OpenCodeWorkspaceAccount(
            tokenAccountID: firstToken,
            workspaceID: "wrk_ALPHA",
            label: "Alpha",
            now: Date(timeIntervalSince1970: 100)))
        let second = try #require(OpenCodeWorkspaceAccount(
            tokenAccountID: secondToken,
            workspaceID: "wrk_BETA",
            label: "Beta",
            now: Date(timeIntervalSince1970: 200)))
        var accounts = OpenCodeWorkspaceAccounts(accounts: [first, second], activeID: second.id)

        accounts.prune(validTokenAccountIDs: [firstToken])

        #expect(accounts.accounts.map(\.id) == [first.id])
        #expect(accounts.active?.id == first.id)
    }

    @Test
    func `invalid and missing credentials have explicit mutation results`() {
        var accounts = OpenCodeWorkspaceAccounts()

        #expect(accounts.add(
            tokenAccountID: nil,
            workspaceID: "wrk_ALPHA",
            label: "Alpha") == .missingReusableCredential)
        #expect(accounts.add(
            tokenAccountID: UUID(),
            workspaceID: "not-a-workspace",
            label: "Invalid") == .invalidWorkspaceID)
        #expect(accounts.add(
            tokenAccountID: UUID(),
            workspaceID: "wrk_ALPHA?query=unexpected",
            label: "Invalid") == .invalidWorkspaceID)
        #expect(accounts.add(
            tokenAccountID: UUID(),
            workspaceID: "wrk_ALPHA/extra",
            label: "Invalid") == .invalidWorkspaceID)
    }

    @Test
    func `persisted account ID is recomputed from canonical fields`() throws {
        let json = """
        {
          "id": "stale-id",
          "tokenAccountID": "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
          "workspaceID": "wrk_ALPHA",
          "label": "Alpha",
          "createdAt": 100,
          "updatedAt": 200
        }
        """

        let account = try JSONDecoder().decode(OpenCodeWorkspaceAccount.self, from: Data(json.utf8))
        let tokenAccountID = try #require(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"))

        #expect(account.id == OpenCodeWorkspaceAccount.canonicalID(
            tokenAccountID: tokenAccountID,
            workspaceID: "wrk_ALPHA"))
    }

    @Test
    func `config store migrates legacy OpenCode workspace accounts`() throws {
        let firstID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let secondID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let tokenID = try #require(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-legacy-opencode-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let json = """
        {
          "version": 1,
          "providers": [{
            "id": "opencode",
            "openCodeWorkspaceAccounts": {
              "version": 1,
              "activeAccountID": "\(secondID.uuidString)",
              "accounts": [
                {
                  "id": "\(firstID.uuidString)",
                  "tokenAccountID": "\(tokenID.uuidString)",
                  "label": "Shared",
                  "workspaceID": "wrk_ALPHA",
                  "workspaceLabel": "Alpha",
                  "discoveredOwnerLabel": "Alice",
                  "addedAt": 100,
                  "lastValidatedAt": 200
                },
                {
                  "id": "\(secondID.uuidString)",
                  "tokenAccountID": "\(tokenID.uuidString)",
                  "label": "Shared",
                  "workspaceID": "wrk_BETA",
                  "workspaceLabel": "Beta",
                  "discoveredOwnerLabel": "Bob",
                  "addedAt": 300,
                  "lastValidatedAt": 400
                }
              ]
            }
          }]
        }
        """
        try json.write(to: url, atomically: true, encoding: .utf8)

        let config = try #require(try CodexBarConfigStore(fileURL: url).load())
        let accounts = try #require(config.providerConfig(for: .opencode)?.opencodeWorkspaceAccounts)

        #expect(accounts.accounts.map(\.workspaceID) == ["wrk_ALPHA", "wrk_BETA"])
        #expect(accounts.active?.workspaceID == "wrk_BETA")
        #expect(accounts.active?.ownerLabel == "Bob")
        #expect(accounts.accounts.first?.createdAt == 100)
        let migrated = try String(contentsOf: url)
        #expect(migrated.contains("opencodeWorkspaceAccounts"))
        #expect(!migrated.contains("openCodeWorkspaceAccounts"))
    }
}
