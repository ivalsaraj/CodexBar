import CodexBarCore
import Foundation
import SwiftUI

struct OpenCodeAccountsSectionState {
    let accounts: [OpenCodeWorkspaceAccount]
    let activeAccountID: UUID?
    let unboundTokenAccounts: [ProviderTokenAccount]
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

struct OpenCodeAccountDraft: Sendable {
    let existingTokenAccountID: UUID?
    let label: String
    let token: String
    let workspaceID: String
    let workspaceLabel: String
}

@MainActor
struct OpenCodeAccountsSectionView: View {
    let state: OpenCodeAccountsSectionState
    let setActiveAccount: (UUID) -> Void
    let saveAccount: (OpenCodeAccountDraft) async -> Void
    let removeAccount: (OpenCodeWorkspaceAccount) -> Void

    @State private var selectedCredentialID: String = Self.newCredentialID
    @State private var label = ""
    @State private var token = ""
    @State private var workspaceID = ""
    @State private var workspaceLabel = ""
    @State private var isSaving = false

    private static let newCredentialID = "new"

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

            if !self.state.unboundTokenAccounts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Unbound credentials")
                        .font(.subheadline.weight(.semibold))

                    ForEach(self.state.unboundTokenAccounts, id: \.id) { account in
                        Text(account.displayName)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Text("Bind one of these existing credentials to a workspace below, or add a new credential.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Credential")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: ProviderSettingsMetrics.pickerLabelWidth, alignment: .leading)

                    Picker("", selection: self.$selectedCredentialID) {
                        Text("New credential").tag(Self.newCredentialID)
                        ForEach(self.state.unboundTokenAccounts, id: \.id) { account in
                            Text(account.displayName).tag(account.id.uuidString)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                }

                HStack(alignment: .center, spacing: 10) {
                    Text("Label")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: ProviderSettingsMetrics.pickerLabelWidth, alignment: .leading)

                    TextField("Workspace Account", text: self.$label)
                        .textFieldStyle(.roundedBorder)
                }

                if self.selectedCredentialID == Self.newCredentialID {
                    HStack(alignment: .center, spacing: 10) {
                        Text("Cookie")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: ProviderSettingsMetrics.pickerLabelWidth, alignment: .leading)

                        SecureField("Cookie: …", text: self.$token)
                            .textFieldStyle(.roundedBorder)
                    }
                }

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

                Text("Leave Workspace empty to auto-discover when only one workspace is available for that credential.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button(self.selectedCredentialID == Self.newCredentialID ? "Add Account" : "Bind Workspace") {
                    let draft = OpenCodeAccountDraft(
                        existingTokenAccountID: self.selectedTokenAccountID,
                        label: self.label,
                        token: self.token,
                        workspaceID: self.workspaceID,
                        workspaceLabel: self.workspaceLabel)
                    self.isSaving = true
                    Task {
                        await self.saveAccount(draft)
                        await MainActor.run {
                            self.resetForm()
                            self.isSaving = false
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(self.isSaving)
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

    private var selectedTokenAccountID: UUID? {
        guard self.selectedCredentialID != Self.newCredentialID else { return nil }
        return UUID(uuidString: self.selectedCredentialID)
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
        self.label = ""
        self.token = ""
        self.workspaceID = ""
        self.workspaceLabel = ""
    }
}
