import CodexBarCore
import Foundation

extension UsageStore {
    func detectVersions() {
        let implementations = ProviderCatalog.all
        let browserDetection = self.browserDetection
        Task { @MainActor [weak self] in
            let resolved = await Task.detached { () -> [UsageProvider: String] in
                var resolved: [UsageProvider: String] = [:]
                await withTaskGroup(of: (UsageProvider, String?).self) { group in
                    for implementation in implementations {
                        let context = ProviderVersionContext(
                            provider: implementation.id,
                            browserDetection: browserDetection)
                        group.addTask {
                            await (implementation.id, implementation.detectVersion(context: context))
                        }
                    }
                    for await (provider, version) in group {
                        guard let version, !version.isEmpty else { continue }
                        resolved[provider] = version
                    }
                }
                return resolved
            }.value
            self?.versions = resolved
        }
    }
}
