import AppKit
import CodexBarCore
import CodexBarMacroSupport
import Foundation
import SwiftUI

@ProviderImplementationRegistration
struct OpenCodeProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .opencode

    @MainActor
    func presentation(context _: ProviderPresentationContext) -> ProviderPresentation {
        ProviderPresentation { _ in "web" }
    }

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        settings.ensureOpenCodeWorkspaceAccountMigrationIfNeeded()
        _ = settings.opencodeCookieSource
        _ = settings.opencodeCookieHeader
        _ = settings.opencodeWorkspaceID
        _ = settings.openCodeWorkspaceAccounts
        _ = settings.selectedOpenCodeWorkspaceAccount
    }

    @MainActor
    func settingsSnapshot(context: ProviderSettingsSnapshotContext) -> ProviderSettingsSnapshotContribution? {
        .opencode(context.settings.opencodeSettingsSnapshot(tokenOverride: context.tokenOverride))
    }

    @MainActor
    func tokenAccountsVisibility(context _: ProviderSettingsContext, support _: TokenAccountSupport) -> Bool {
        false
    }

    @MainActor
    func applyTokenAccountCookieSource(settings: SettingsStore) {
        if settings.opencodeCookieSource != .manual {
            settings.opencodeCookieSource = .manual
        }
    }

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        let cookieBinding = Binding(
            get: { context.settings.opencodeCookieSource.rawValue },
            set: { raw in
                context.settings.opencodeCookieSource = ProviderCookieSource(rawValue: raw) ?? .auto
            })
        let cookieOptions = ProviderCookieSourceUI.options(
            allowsOff: false,
            keychainDisabled: context.settings.debugDisableKeychainAccess)

        let cookieSubtitle: () -> String? = {
            ProviderCookieSourceUI.subtitle(
                source: context.settings.opencodeCookieSource,
                keychainDisabled: context.settings.debugDisableKeychainAccess,
                auto: "Automatic imports browser cookies from opencode.ai.",
                manual: "Paste a Cookie header captured from an OpenCode workspace or Go dashboard page.",
                off: "OpenCode cookies are disabled.")
        }

        return [
            ProviderSettingsPickerDescriptor(
                id: "opencode-cookie-source",
                title: "Cookie source",
                subtitle: "Automatic imports browser cookies from opencode.ai.",
                dynamicSubtitle: cookieSubtitle,
                binding: cookieBinding,
                options: cookieOptions,
                isVisible: nil,
                onChange: nil,
                trailingText: {
                    OpenCodeProviderUI.cachedCookieTrailingText(
                        provider: .opencode,
                        cookieSource: context.settings.opencodeCookieSource)
                }),
        ]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "opencode-workspace-id",
                title: "Workspace ID",
                subtitle: "Optional override if workspace lookup fails.",
                kind: .plain,
                placeholder: "wrk_…",
                binding: context.stringBinding(\.opencodeWorkspaceID),
                actions: [],
                isVisible: nil,
                onActivate: nil),
        ]
    }
}
