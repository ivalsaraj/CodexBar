import CodexBarCore
import Foundation

@MainActor
final class ProviderUtilizationHistoryStore {
    private let fileManager: FileManager
    private let now: () -> Date
    private let cacheDirectory: URL
    private let flushDelay: Duration
    private var pointsByProvider: [UsageProvider: [ProviderUtilizationHistoryPoint]] = [:]
    private var flushTask: Task<Void, Never>?
    private var isDirty = false

    private let retentionInterval: TimeInterval = 30 * 24 * 60 * 60
    private let dedupInterval: TimeInterval = 60
    private let dedupEpsilon: Double = 0.001

    init(
        fileManager: FileManager = .default,
        cacheDirectory: URL? = nil,
        flushDelay: Duration = .seconds(5),
        now: @escaping () -> Date = Date.init)
    {
        self.fileManager = fileManager
        self.now = now
        self.cacheDirectory = cacheDirectory ?? Self.defaultCacheDirectory(fileManager: fileManager)
        self.flushDelay = flushDelay
        self.loadFromDisk()
    }

    func recordPoint(
        provider: UsageProvider,
        timestamp: Date,
        primaryUsedPercent: Double,
        secondaryUsedPercent: Double?)
    {
        guard Self.supports(provider: provider) else { return }
        var points = self.pruned(self.pointsByProvider[provider] ?? [])
        let candidate = ProviderUtilizationHistoryPoint(
            timestamp: timestamp,
            primaryUsedPercent: primaryUsedPercent,
            secondaryUsedPercent: secondaryUsedPercent)
        if let last = points.last, self.isDuplicate(last: last, candidate: candidate) {
            self.pointsByProvider[provider] = points
            return
        }
        points.append(candidate)
        points.sort { $0.timestamp < $1.timestamp }
        self.pointsByProvider[provider] = points
        self.isDirty = true
        self.scheduleFlush()
    }

    func points(for provider: UsageProvider) -> [ProviderUtilizationHistoryPoint] {
        self.pruned(self.pointsByProvider[provider] ?? [])
    }

    func downsampledPoints(
        for provider: UsageProvider,
        range: ProviderUtilizationTimeRange)
    -> [ProviderUtilizationHistoryPoint] {
        let cutoff = self.now().addingTimeInterval(-range.interval)
        let points = self.points(for: provider).filter { $0.timestamp >= cutoff }
        guard points.count > range.targetPointCount else { return points }

        let bucketCount = range.targetPointCount
        let bucketDuration = range.interval / Double(bucketCount)
        var buckets = Array(repeating: [ProviderUtilizationHistoryPoint](), count: bucketCount)

        for point in points {
            let offset = point.timestamp.timeIntervalSince(cutoff)
            var index = Int(offset / bucketDuration)
            if index < 0 { index = 0 }
            if index >= bucketCount { index = bucketCount - 1 }
            buckets[index].append(point)
        }

        return buckets.compactMap { bucket in
            guard !bucket.isEmpty else { return nil }
            let averageTimestamp = bucket.map(\.timestamp.timeIntervalSince1970).reduce(0, +) / Double(bucket.count)
            let averagePrimary = bucket.map(\.primaryUsedPercent).reduce(0, +) / Double(bucket.count)
            let secondaryValues = bucket.compactMap(\.secondaryUsedPercent)
            let averageSecondary = secondaryValues.isEmpty
                ? nil
                : secondaryValues.reduce(0, +) / Double(secondaryValues.count)
            return ProviderUtilizationHistoryPoint(
                timestamp: Date(timeIntervalSince1970: averageTimestamp),
                primaryUsedPercent: averagePrimary,
                secondaryUsedPercent: averageSecondary)
        }
    }

    func flushToDisk() {
        self.flushTask?.cancel()
        self.flushTask = nil
        guard self.isDirty else { return }
        try? self.fileManager.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
        for provider in Self.supportedProviders {
            let points = self.points(for: provider)
            let fileURL = self.fileURL(for: provider)
            guard let data = try? Self.encoder.encode(points) else { continue }
            try? data.write(to: fileURL, options: .atomic)
        }
        self.isDirty = false
    }

    private func loadFromDisk() {
        try? self.fileManager.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
        for provider in Self.supportedProviders {
            let fileURL = self.fileURL(for: provider)
            guard let data = try? Data(contentsOf: fileURL) else { continue }
            guard let decoded = try? Self.decoder.decode([ProviderUtilizationHistoryPoint].self, from: data) else {
                let corruptURL = self.cacheDirectory.appendingPathComponent("\(provider.rawValue).corrupt.json")
                try? self.fileManager.removeItem(at: corruptURL)
                try? self.fileManager.moveItem(at: fileURL, to: corruptURL)
                self.pointsByProvider[provider] = []
                continue
            }
            self.pointsByProvider[provider] = self.pruned(decoded)
        }
    }

    private func isDuplicate(
        last: ProviderUtilizationHistoryPoint,
        candidate: ProviderUtilizationHistoryPoint)
    -> Bool {
        guard candidate.timestamp.timeIntervalSince(last.timestamp) < self.dedupInterval else { return false }
        guard abs(candidate.primaryUsedPercent - last.primaryUsedPercent) <= self.dedupEpsilon else { return false }
        switch (last.secondaryUsedPercent, candidate.secondaryUsedPercent) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return abs(lhs - rhs) <= self.dedupEpsilon
        default:
            return false
        }
    }

    private func pruned(_ points: [ProviderUtilizationHistoryPoint]) -> [ProviderUtilizationHistoryPoint] {
        let cutoff = self.now().addingTimeInterval(-self.retentionInterval)
        return points
            .filter { $0.timestamp >= cutoff }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private func fileURL(for provider: UsageProvider) -> URL {
        self.cacheDirectory.appendingPathComponent("\(provider.rawValue).json")
    }

    private func scheduleFlush() {
        self.flushTask?.cancel()
        let delay = self.flushDelay
        self.flushTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            self?.flushToDisk()
        }
    }

    static func supports(provider: UsageProvider) -> Bool {
        self.supportedProviders.contains(provider)
    }

    private static let supportedProviders: Set<UsageProvider> = [.codex, .claude]

    private static func defaultCacheDirectory(fileManager: FileManager) -> URL {
        UsageStore.costUsageCacheDirectory(fileManager: fileManager)
            .deletingLastPathComponent()
            .appendingPathComponent("utilization-history", isDirectory: true)
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}
