import CodexBarCore
import Foundation

struct ProviderSpec {
    let style: IconStyle
    let isEnabled: @MainActor () -> Bool
    let descriptor: ProviderDescriptor
    let makeFetchContext: @MainActor () -> ProviderFetchContext
}

struct ProviderRegistry {
    let metadata: [UsageProvider: ProviderMetadata]

    static let shared: ProviderRegistry = .init()

    init(metadata: [UsageProvider: ProviderMetadata] = ProviderDescriptorRegistry.metadata) {
        self.metadata = metadata
    }

    @MainActor
    func specs(
        settings: SettingsStore,
        metadata: [UsageProvider: ProviderMetadata],
        codexFetcher: UsageFetcher,
        claudeFetcher: any ClaudeUsageFetching,
        browserDetection: BrowserDetection) -> [UsageProvider: ProviderSpec]
    {
        var specs: [UsageProvider: ProviderSpec] = [:]
        specs.reserveCapacity(UsageProvider.allCases.count)

        for provider in UsageProvider.allCases {
            let descriptor = ProviderDescriptorRegistry.descriptor(for: provider)
            let meta = metadata[provider]!
            let spec = ProviderSpec(
                style: descriptor.branding.iconStyle,
                isEnabled: { settings.isProviderEnabled(provider: provider, metadata: meta) },
                descriptor: descriptor,
                makeFetchContext: {
                    let sourceMode = ProviderCatalog.implementation(for: provider)?
                        .sourceMode(context: ProviderSourceModeContext(provider: provider, settings: settings))
                        ?? .auto
                    let snapshot = Self.makeSettingsSnapshot(settings: settings, tokenOverride: nil)
                    let env = Self.makeEnvironment(
                        base: ProcessInfo.processInfo.environment,
                        provider: provider,
                        settings: settings,
                        tokenOverride: nil)
                    let verbose = settings.isVerboseLoggingEnabled
                    return ProviderFetchContext(
                        runtime: .app,
                        sourceMode: sourceMode,
                        includeCredits: false,
                        webTimeout: 60,
                        webDebugDumpHTML: false,
                        verbose: verbose,
                        env: env,
                        settings: snapshot,
                        fetcher: codexFetcher,
                        claudeFetcher: claudeFetcher,
                        browserDetection: browserDetection)
                })
            specs[provider] = spec
        }

        return specs
    }

    @MainActor
    static func makeSettingsSnapshot(
        settings: SettingsStore,
        tokenOverride: TokenAccountOverride?) -> ProviderSettingsSnapshot
    {
        settings.ensureTokenAccountsLoaded()
        var builder = ProviderSettingsSnapshotBuilder(
            debugMenuEnabled: settings.debugMenuEnabled,
            debugKeepCLISessionsAlive: settings.debugKeepCLISessionsAlive)
        let context = ProviderSettingsSnapshotContext(settings: settings, tokenOverride: tokenOverride)
        for implementation in ProviderCatalog.all {
            if let contribution = implementation.settingsSnapshot(context: context) {
                builder.apply(contribution)
            }
        }
        return builder.build()
    }

    @MainActor
    static func makeEnvironment(
        base: [String: String],
        provider: UsageProvider,
        settings: SettingsStore,
        tokenOverride: TokenAccountOverride?) -> [String: String]
    {
        let account = ProviderTokenAccountSelection.selectedAccount(
            provider: provider,
            settings: settings,
            override: tokenOverride)
        var env = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: base,
            provider: provider,
            config: settings.providerConfig(for: provider))
        guard let account else { return env }
        let support = TokenAccountSupportCatalog.support(for: provider)

        switch support?.injection {
        case .codexOAuth:
            // For active account, auth.json has already been written at switch time.
            // For per-account fetch override, isolate auth.json via temp CODEX_HOME.
            if tokenOverride != nil {
                let tempBase = CodexAccountEnvironment.tempBase
                if let tempHome = try? CodexOAuthTempHome.make(jsonString: account.token, under: tempBase) {
                    env["CODEX_HOME"] = tempHome.path
                    CodexAccountEnvironment.registerTempHome(tempHome)
                }
            }
        default:
            if let override = TokenAccountSupportCatalog.envOverride(for: provider, token: account.token) {
                for (key, value) in override {
                    env[key] = value
                }
            }
        }
        return env
    }
}
