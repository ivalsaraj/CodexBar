import CodexBarCore
import SwiftUI

struct TokenUsageTitleRow: View {
    let tokenUsage: UsageMenuCardView.Model.TokenUsageSection
    let selectedCursorRangeKind: CursorUsageRangeKind?
    let selectCursorRange: ((CursorUsageRangeKind) -> Void)?

    init(
        tokenUsage: UsageMenuCardView.Model.TokenUsageSection,
        selectedCursorRangeKind: CursorUsageRangeKind? = nil,
        selectCursorRange: ((CursorUsageRangeKind) -> Void)? = nil)
    {
        self.tokenUsage = tokenUsage
        self.selectedCursorRangeKind = selectedCursorRangeKind
        self.selectCursorRange = selectCursorRange
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(self.tokenUsage.title)
                .font(.body)
                .fontWeight(.medium)
            Spacer(minLength: 8)
            if !self.tokenUsage.availableCursorRangeKinds.isEmpty,
               let selected = self.selectedCursorRangeKind ?? self.tokenUsage.selectedCursorRangeKind,
               let select = self.selectCursorRange ?? self.tokenUsage.selectCursorRange
            {
                Picker(
                    "",
                    selection: Binding(
                        get: { selected },
                        set: { select($0) }))
                {
                    ForEach(self.tokenUsage.availableCursorRangeKinds, id: \.self) { range in
                        Text(range.label).tag(range)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .fixedSize()
            }
        }
    }
}
