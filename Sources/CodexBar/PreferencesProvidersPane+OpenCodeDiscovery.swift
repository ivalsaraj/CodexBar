import CodexBarCore

extension ProvidersPane {
    func discoverAndSaveOpenCodeWorkspaces(
        tokenAccount: ProviderTokenAccount,
        successAction: String,
        selectsImportedWorkspace: Bool = false,
        discoveredWorkspaces: [OpenCodeDiscoveredWorkspace]? = nil) async -> OpenCodeAccountSaveResult
    {
        do {
            let discovered: [OpenCodeDiscoveredWorkspace] = if let discoveredWorkspaces {
                discoveredWorkspaces
            } else {
                try await self.openCodeWorkspaceFlow.discoverWorkspaces(cookieHeader: tokenAccount.token)
            }
            guard !discovered.isEmpty else {
                return self.finishOpenCodeAccountAction(.failure(
                    "No OpenCode workspaces were discovered for this login."))
            }
            guard let summary = self.settings.bulkSaveOpenCodeWorkspaceAccounts(
                tokenAccountID: tokenAccount.id,
                discoveredWorkspaces: discovered)
            else {
                return self.finishOpenCodeAccountAction(.failure(
                    "CodexBar could not save the discovered OpenCode workspaces."))
            }
            if selectsImportedWorkspace,
               let importedAccountID = summary.accountIDs.first
            {
                _ = self.settings.setActiveOpenCodeWorkspaceAccount(id: importedAccountID)
            } else if let selectedAccountID = self.settings.selectedOpenCodeWorkspaceAccount?.id {
                _ = self.settings.setActiveOpenCodeWorkspaceAccount(id: selectedAccountID)
            } else if let firstAccountID = summary.accountIDs.first {
                _ = self.settings.setActiveOpenCodeWorkspaceAccount(id: firstAccountID)
            }
            await self.refreshOpenCodeProvider()
            if summary.addedCount == 0 {
                return self.finishOpenCodeAccountAction(.noChange("All discovered workspaces are already saved."))
            }
            let importedCount = summary.accountIDs.count
            let noun = importedCount == 1 ? "workspace" : "workspaces"
            return self.finishOpenCodeAccountAction(.success("\(importedCount) \(noun) \(successAction)."))
        } catch {
            return self.finishOpenCodeAccountAction(.failure(error.localizedDescription))
        }
    }
}
