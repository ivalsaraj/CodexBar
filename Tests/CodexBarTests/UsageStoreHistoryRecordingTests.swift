import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
@Suite
struct UsageStoreHistoryRecordingTests {
    private func makeStore(
        suite: String = "UsageStoreHistoryRecordingTests-\(UUID().uuidString)",
        historyStore: ProviderUtilizationHistoryStore)
    -> UsageStore {
        let settings = SettingsStore(
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        return UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            utilizationHistoryStore: historyStore,
            settings: settings)
    }

    @Test
    func recordsClaudeSnapshotHistory() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let historyStore = ProviderUtilizationHistoryStore(
            cacheDirectory: tempDirectory,
            now: { now })
        let store = self.makeStore(historyStore: historyStore)

        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 12, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 34, windowMinutes: 7 * 24 * 60, resetsAt: nil, resetDescription: nil),
            updatedAt: now)

        store.recordUtilizationHistoryIfNeeded(provider: .claude, snapshot: snapshot, recordedAt: now)

        let point = try #require(historyStore.points(for: .claude).first)
        #expect(point.primaryUsedPercent == 12)
        #expect(point.secondaryUsedPercent == 34)
    }

    @Test
    func recordsCodexSnapshotHistory() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let historyStore = ProviderUtilizationHistoryStore(
            cacheDirectory: tempDirectory,
            now: { now })
        let store = self.makeStore(historyStore: historyStore)

        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 45, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 67, windowMinutes: 7 * 24 * 60, resetsAt: nil, resetDescription: nil),
            updatedAt: now)

        store.recordUtilizationHistoryIfNeeded(provider: .codex, snapshot: snapshot, recordedAt: now)

        let point = try #require(historyStore.points(for: .codex).first)
        #expect(point.primaryUsedPercent == 45)
        #expect(point.secondaryUsedPercent == 67)
    }

    @Test
    func ignoresUnsupportedProviders() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let historyStore = ProviderUtilizationHistoryStore(
            cacheDirectory: tempDirectory,
            now: { now })
        let store = self.makeStore(historyStore: historyStore)

        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 9, windowMinutes: 60, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 20, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            updatedAt: now)

        store.recordUtilizationHistoryIfNeeded(provider: .cursor, snapshot: snapshot, recordedAt: now)

        #expect(historyStore.points(for: .cursor).isEmpty)
    }

    @Test
    func ignoresSnapshotsWithoutPrimaryWindow() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let historyStore = ProviderUtilizationHistoryStore(
            cacheDirectory: tempDirectory,
            now: { now })
        let store = self.makeStore(historyStore: historyStore)

        let snapshot = UsageSnapshot(
            primary: nil,
            secondary: RateWindow(usedPercent: 34, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            updatedAt: now)

        store.recordUtilizationHistoryIfNeeded(provider: .claude, snapshot: snapshot, recordedAt: now)

        #expect(historyStore.points(for: .claude).isEmpty)
    }

    @Test
    func recordsUsingCollectionTimeInsteadOfSnapshotTimestamp() throws {
        let snapshotTime = Date(timeIntervalSince1970: 1_700_000_000)
        let recordedAt = snapshotTime.addingTimeInterval(300)
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let historyStore = ProviderUtilizationHistoryStore(
            cacheDirectory: tempDirectory,
            now: { recordedAt })
        let store = self.makeStore(historyStore: historyStore)

        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 12, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 34, windowMinutes: 7 * 24 * 60, resetsAt: nil, resetDescription: nil),
            updatedAt: snapshotTime)

        store.recordUtilizationHistoryIfNeeded(provider: .claude, snapshot: snapshot, recordedAt: recordedAt)

        let point = try #require(historyStore.points(for: .claude).first)
        #expect(point.timestamp == recordedAt)
    }

    @Test
    func failedRefreshDoesNotRecordHistory() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let historyStore = ProviderUtilizationHistoryStore(
            cacheDirectory: tempDirectory,
            now: { now })
        let store = self.makeStore(historyStore: historyStore)
        let existingSpec = try #require(store.providerSpecs[.codex])
        let baseDescriptor = ProviderDescriptorRegistry.descriptor(for: .codex)
        let failingDescriptor = ProviderDescriptor(
            id: .codex,
            metadata: baseDescriptor.metadata,
            branding: baseDescriptor.branding,
            tokenCost: baseDescriptor.tokenCost,
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto],
                pipeline: ProviderFetchPipeline(resolveStrategies: { _ in [AlwaysFailingCodexFetchStrategy()] })),
            cli: baseDescriptor.cli)

        store.providerSpecs[.codex] = ProviderSpec(
            style: failingDescriptor.branding.iconStyle,
            isEnabled: { true },
            descriptor: failingDescriptor,
            makeFetchContext: existingSpec.makeFetchContext)

        await store.refreshProvider(.codex, allowDisabled: true)

        #expect(historyStore.points(for: .codex).isEmpty)
    }
}

private struct AlwaysFailingCodexFetchStrategy: ProviderFetchStrategy {
    let id: String = "tests.codex.failure"
    let kind: ProviderFetchKind = .cli

    func isAvailable(_: ProviderFetchContext) async -> Bool {
        true
    }

    func fetch(_: ProviderFetchContext) async throws -> ProviderFetchResult {
        throw AlwaysFailingCodexFetchError.failed
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }
}

private enum AlwaysFailingCodexFetchError: LocalizedError {
    case failed

    var errorDescription: String? {
        "Intentional test failure"
    }
}
