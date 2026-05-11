import Foundation
import Testing
@testable import CodexBarCore

struct OpenCodeWidgetSnapshotTests {
    @Test
    func `widget snapshot round trip preserves opencode workspace identity`() throws {
        let accountID = UUID()
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .opencode,
            accountID: accountID,
            accountLabel: "Alpha Workspace",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            primary: RateWindow(usedPercent: 20, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            usageRows: [
                WidgetSnapshot.WidgetUsageRowSnapshot(
                    id: "primary",
                    title: "Session",
                    percentLeft: 80),
            ],
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])
        let snapshot = WidgetSnapshot(entries: [entry], enabledProviders: [.opencode], generatedAt: Date())

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetSnapshot.self, from: data)

        #expect(decoded.entries.first?.accountID == accountID)
        #expect(decoded.entries.first?.accountLabel == "Alpha Workspace")
        #expect(decoded.entry(for: .opencode, accountID: accountID)?.accountLabel == "Alpha Workspace")
    }

    @Test
    func `widget snapshot filters multiple opencode entries by account id`() {
        let alphaID = UUID()
        let betaID = UUID()
        let snapshot = WidgetSnapshot(
            entries: [
                WidgetSnapshot.ProviderEntry(
                    provider: .opencode,
                    accountID: alphaID,
                    accountLabel: "Alpha",
                    updatedAt: Date(),
                    primary: nil,
                    secondary: nil,
                    tertiary: nil,
                    creditsRemaining: nil,
                    codeReviewRemainingPercent: nil,
                    tokenUsage: nil,
                    dailyUsage: []),
                WidgetSnapshot.ProviderEntry(
                    provider: .opencode,
                    accountID: betaID,
                    accountLabel: "Beta",
                    updatedAt: Date(),
                    primary: nil,
                    secondary: nil,
                    tertiary: nil,
                    creditsRemaining: nil,
                    codeReviewRemainingPercent: nil,
                    tokenUsage: nil,
                    dailyUsage: []),
            ],
            enabledProviders: [.opencode],
            generatedAt: Date())

        #expect(snapshot.entries(for: .opencode).map(\.accountLabel) == ["Alpha", "Beta"])
        #expect(snapshot.entry(for: .opencode, accountID: betaID)?.accountLabel == "Beta")
    }
}
