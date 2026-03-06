import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
@Suite
struct ProviderUtilizationHistoryStoreTests {
    @Test
    func recordsPointsForSupportedProvidersOnly() {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = ProviderUtilizationHistoryStore(
            cacheDirectory: tempDirectory,
            now: { now })

        store.recordPoint(provider: .claude, timestamp: now, primaryUsedPercent: 25, secondaryUsedPercent: 50)
        store.recordPoint(provider: .codex, timestamp: now, primaryUsedPercent: 40, secondaryUsedPercent: 60)
        store.recordPoint(provider: .cursor, timestamp: now, primaryUsedPercent: 75, secondaryUsedPercent: 10)

        #expect(store.points(for: .claude).count == 1)
        #expect(store.points(for: .codex).count == 1)
        #expect(store.points(for: .cursor).isEmpty)
    }

    @Test
    func preservesMissingSecondaryValues() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = ProviderUtilizationHistoryStore(
            cacheDirectory: tempDirectory,
            now: { now })

        store.recordPoint(provider: .claude, timestamp: now, primaryUsedPercent: 15, secondaryUsedPercent: nil)

        let point = try #require(store.points(for: .claude).first)
        #expect(point.primaryUsedPercent == 15)
        #expect(point.secondaryUsedPercent == nil)
    }

    @Test
    func prunesPointsOlderThanThirtyDays() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let old = now.addingTimeInterval(-(31 * 24 * 60 * 60))
        let recent = now.addingTimeInterval(-(2 * 24 * 60 * 60))
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ProviderUtilizationHistoryStore(
            cacheDirectory: tempDirectory,
            now: { now })

        store.recordPoint(provider: .codex, timestamp: old, primaryUsedPercent: 5, secondaryUsedPercent: 10)
        store.recordPoint(provider: .codex, timestamp: recent, primaryUsedPercent: 15, secondaryUsedPercent: 20)

        let points = store.points(for: .codex)
        #expect(points.count == 1)
        #expect(points.first?.timestamp == recent)
    }

    @Test
    func skipsDuplicatePointsWithinDedupWindow() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ProviderUtilizationHistoryStore(
            cacheDirectory: tempDirectory,
            now: { base })

        store.recordPoint(provider: .claude, timestamp: base, primaryUsedPercent: 10, secondaryUsedPercent: 25)
        store.recordPoint(
            provider: .claude,
            timestamp: base.addingTimeInterval(30),
            primaryUsedPercent: 10,
            secondaryUsedPercent: 25)
        store.recordPoint(
            provider: .claude,
            timestamp: base.addingTimeInterval(61),
            primaryUsedPercent: 10,
            secondaryUsedPercent: 25)

        #expect(store.points(for: .claude).count == 2)
    }

    @Test
    func recordsChangedPointWithinDedupWindow() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ProviderUtilizationHistoryStore(
            cacheDirectory: tempDirectory,
            now: { base })

        store.recordPoint(provider: .claude, timestamp: base, primaryUsedPercent: 10, secondaryUsedPercent: 25)
        store.recordPoint(
            provider: .claude,
            timestamp: base.addingTimeInterval(30),
            primaryUsedPercent: 11,
            secondaryUsedPercent: 25)

        #expect(store.points(for: .claude).count == 2)
    }

    @Test
    func downsampledPointsExcludeDataOutsideSelectedRange() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ProviderUtilizationHistoryStore(
            cacheDirectory: tempDirectory,
            now: { now })

        store.recordPoint(
            provider: .claude,
            timestamp: now.addingTimeInterval(-(8 * 24 * 60 * 60)),
            primaryUsedPercent: 20,
            secondaryUsedPercent: 30)
        store.recordPoint(
            provider: .claude,
            timestamp: now.addingTimeInterval(-(2 * 60 * 60)),
            primaryUsedPercent: 40,
            secondaryUsedPercent: 50)

        let points = store.downsampledPoints(for: .claude, range: .day1)
        #expect(points.count == 1)
        #expect(points.first?.primaryUsedPercent == 40)
    }

    @Test
    func loadsPersistedHistoryFromDisk() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let writer = ProviderUtilizationHistoryStore(
            cacheDirectory: tempDirectory,
            now: { now })

        writer.recordPoint(provider: .codex, timestamp: now, primaryUsedPercent: 22, secondaryUsedPercent: 44)
        writer.flushToDisk()

        let reader = ProviderUtilizationHistoryStore(
            cacheDirectory: tempDirectory,
            now: { now })

        let point = try #require(reader.points(for: .codex).first)
        #expect(point.primaryUsedPercent == 22)
        #expect(point.secondaryUsedPercent == 44)
    }

    @Test
    func movesCorruptHistoryAsideAndStartsFresh() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let corruptFile = tempDirectory.appendingPathComponent("claude.json")
        try Data("not-json".utf8).write(to: corruptFile, options: .atomic)

        let store = ProviderUtilizationHistoryStore(
            cacheDirectory: tempDirectory,
            now: { now })

        #expect(store.points(for: .claude).isEmpty)
        #expect(FileManager.default.fileExists(
            atPath: tempDirectory.appendingPathComponent("claude.corrupt.json").path))
    }

    @Test
    func autoFlushesDirtyHistoryAfterDelay() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ProviderUtilizationHistoryStore(
            cacheDirectory: tempDirectory,
            flushDelay: .milliseconds(10),
            now: { now })

        store.recordPoint(provider: .codex, timestamp: now, primaryUsedPercent: 22, secondaryUsedPercent: 44)
        try await Task.sleep(for: .milliseconds(50))

        let reader = ProviderUtilizationHistoryStore(
            cacheDirectory: tempDirectory,
            flushDelay: .seconds(5),
            now: { now })
        #expect(reader.points(for: .codex).count == 1)
    }
}
