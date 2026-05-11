import CodexBarCore
import Foundation
import SwiftUI

struct OpenCodeAccountsSectionState {
    let accounts: [OpenCodeWorkspaceAccount]
    let activeAccountID: UUID?
    let hasReusableCredential: Bool
    let notice: String?

    var activeAccount: OpenCodeWorkspaceAccount? {
        if let activeAccountID,
           let account = self.accounts.first(where: { $0.id == activeAccountID })
        {
            return account
        }
        return self.accounts.first
    }

    var showsActivePicker: Bool {
        self.accounts.count > 1
    }
}

enum OpenCodeAccountSaveResult: Equatable {
    case success(String)
    case noChange(String)
    case failure(String)

    var notice: String {
        switch self {
        case let .success(message), let .noChange(message), let .failure(message):
            message
        }
    }

    var shouldResetForm: Bool {
        if case .success = self {
            return true
        }
        return false
    }
}

struct OpenCodeAccountDraft: Sendable {
    let workspaceID: String
    let workspaceLabel: String
}

@MainActor
struct OpenCodeAccountsSectionView: View {
    let state: OpenCodeAccountsSectionState
    let setActiveAccount: (UUID) -> Void
    let importCurrentLogin: @MainActor @Sendable () async -> OpenCodeAccountSaveResult
    let refreshAccounts: @MainActor @Sendable () async -> OpenCodeAccountSaveResult
    let saveAccount: @MainActor @Sendable (OpenCodeAccountDraft) async -> OpenCodeAccountSaveResult
    let removeAccount: (OpenCodeWorkspaceAccount) -> Void

    @State private var workspaceID = ""
    @State private var workspaceLabel = ""
    @State private var activeOperation: Operation?

    private enum Operation {
        case importing
        case refreshing
        case saving
    }

    var body: some View {
        ProviderSettingsSection(title: "Accounts") {
            if let selection = self.activeSelectionBinding {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Active")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: ProviderSettingsMetrics.pickerLabelWidth, alignment: .leading)

                    Picker("", selection: selection) {
                        ForEach(self.state.accounts, id: \.id) { account in
                            Text(self.accountDisplayName(account)).tag(account.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)

                    Spacer(minLength: 0)
                }

                Text("Choose which OpenCode workspace CodexBar should follow.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if let account = self.state.activeAccount {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Active")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: ProviderSettingsMetrics.pickerLabelWidth, alignment: .leading)

                    Text(self.accountDisplayName(account))
                        .font(.subheadline)

                    Spacer(minLength: 0)
                }
            } else {
                Text("No OpenCode workspace accounts saved yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !self.state.accounts.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(self.state.accounts, id: \.id) { account in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(self.accountDisplayName(account))
                                    .font(.subheadline.weight(.semibold))
                                Text(self.accountDetail(account))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 0)

                            Button("Remove") {
                                self.removeAccount(account)
                            }
                            .buttonStyle(.link)
                            .controlSize(.small)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Button("Import current login") {
                    self.runOperation(.importing, shouldResetOnSuccess: false) {
                        await self.importCurrentLogin()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(self.activeOperation != nil)

                Button("Refresh workspaces") {
                    self.runOperation(.refreshing, shouldResetOnSuccess: false) {
                        await self.refreshAccounts()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(self.activeOperation != nil || !self.state.hasReusableCredential)
            }

            Text(self.state.hasReusableCredential
                ? "CodexBar reuses your saved OpenCode login and keeps workspaces in sync."
                : "Import your current OpenCode login first to add workspaces without pasting cookies.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    Text("Workspace")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: ProviderSettingsMetrics.pickerLabelWidth, alignment: .leading)

                    TextField("wrk_… or https://opencode.ai/workspace/…", text: self.$workspaceID)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(alignment: .center, spacing: 10) {
                    Text("Name")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: ProviderSettingsMetrics.pickerLabelWidth, alignment: .leading)

                    TextField("Optional workspace name", text: self.$workspaceLabel)
                        .textFieldStyle(.roundedBorder)
                }

                Text("Paste a `wrk_…` ID or an OpenCode workspace URL. CodexBar reuses your current OpenCode login.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Add workspace") {
                    let draft = OpenCodeAccountDraft(
                        workspaceID: self.workspaceID,
                        workspaceLabel: self.workspaceLabel)
                    self.runOperation(.saving, shouldResetOnSuccess: true) {
                        await self.saveAccount(draft)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(self.activeOperation != nil)
            }

            if let notice = self.state.notice, !notice.isEmpty {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var activeSelectionBinding: Binding<UUID>? {
        guard self.state.showsActivePicker else { return nil }
        guard let fallbackID = self.state.activeAccount?.id else { return nil }
        return Binding(
            get: { self.state.activeAccountID ?? fallbackID },
            set: { self.setActiveAccount($0) })
    }

    private func accountDisplayName(_ account: OpenCodeWorkspaceAccount) -> String {
        let base = account.workspaceLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return base.isEmpty ? account.label : base
    }

    private func accountDetail(_ account: OpenCodeWorkspaceAccount) -> String {
        var pieces = [account.label, account.workspaceID]
        if let owner = account.discoveredOwnerLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !owner.isEmpty {
            pieces.append(owner)
        }
        return pieces.joined(separator: " • ")
    }

    private func resetForm() {
        self.workspaceID = ""
        self.workspaceLabel = ""
    }

    private func runOperation(
        _ operation: Operation,
        shouldResetOnSuccess: Bool,
        action: @escaping @Sendable () async -> OpenCodeAccountSaveResult)
    {
        self.activeOperation = operation
        Task {
            let result = await action()
            await MainActor.run {
                if shouldResetOnSuccess, result.shouldResetForm {
                    self.resetForm()
                }
                self.activeOperation = nil
            }
        }
    }
}
