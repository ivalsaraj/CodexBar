import CodexBarCore
import Foundation

extension UsageStore {
    func recordUtilizationHistoryIfNeeded(
        provider: UsageProvider,
        snapshot: UsageSnapshot,
        recordedAt: Date = Date())
    {
        guard ProviderUtilizationHistoryStore.supports(provider: provider) else { return }
        guard let primary = snapshot.primary else { return }
        self.utilizationHistoryStore.recordPoint(
            provider: provider,
            timestamp: recordedAt,
            primaryUsedPercent: primary.usedPercent,
            secondaryUsedPercent: snapshot.secondary?.usedPercent)
    }
}
