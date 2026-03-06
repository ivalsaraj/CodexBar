import CodexBarCore
import SwiftUI

@MainActor
struct ProviderUtilizationCompositeHistoryMenuView: View {
    let provider: UsageProvider
    let historyStore: ProviderUtilizationHistoryStore
    let daily: [CostUsageDailyReport.Entry]
    let totalCostUSD: Double?
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProviderUtilizationChartMenuView(
                provider: self.provider,
                historyStore: self.historyStore,
                width: self.width)
            Divider()
                .padding(.horizontal, 16)
            CostHistoryChartMenuView(
                provider: self.provider,
                daily: self.daily,
                totalCostUSD: self.totalCostUSD,
                width: self.width)
        }
        .frame(minWidth: self.width, maxWidth: .infinity, alignment: .leading)
    }
}
