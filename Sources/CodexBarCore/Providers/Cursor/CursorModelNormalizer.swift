import Foundation

/// Origin provider inferred from a raw Cursor model string.
public enum CursorModelProvider: String, Codable, Equatable, Sendable {
    case anthropic
    case openai
    case google
    case cursor
    case unknown
}

/// A raw Cursor model string parsed into compact display parts plus an optional shared pricing key.
///
/// The pricing key is never decided here independently: it is delegated to `CostUsagePricing`
/// coverage helpers so display normalization cannot drift from actual pricing-catalog coverage.
public struct CursorNormalizedModel: Equatable, Sendable {
    public let rawName: String
    public let displayName: String
    public let provider: CursorModelProvider
    public let family: String?
    public let version: String?
    public let mode: String?
    public let effort: String?
    public let pricingKey: String?

    public init(
        rawName: String,
        displayName: String,
        provider: CursorModelProvider,
        family: String?,
        version: String?,
        mode: String?,
        effort: String?,
        pricingKey: String?)
    {
        self.rawName = rawName
        self.displayName = displayName
        self.provider = provider
        self.family = family
        self.version = version
        self.mode = mode
        self.effort = effort
        self.pricingKey = pricingKey
    }
}

/// Tolerant normalizer for Cursor usage-event model strings.
///
/// Keeps the raw name intact, produces a compact display label, and exposes a pricing key only when
/// the shared `CostUsagePricing` catalog actually covers the normalized model. Thinking effort never
/// changes the pricing key.
public enum CursorModelNormalizer {
    private static let effortTokens: Set<String> = ["minimal", "low", "medium", "high", "xhigh", "max"]
    private static let modeTokens: Set<String> = ["thinking"]
    private static let strippablePrefixes = ["openai/", "anthropic/", "google/", "anthropic."]

    public static func normalize(_ raw: String) -> CursorNormalizedModel {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return CursorNormalizedModel(
                rawName: raw,
                displayName: raw,
                provider: .unknown,
                family: nil,
                version: nil,
                mode: nil,
                effort: nil,
                pricingKey: nil)
        }

        var working = trimmed.lowercased()
        for prefix in self.strippablePrefixes where working.hasPrefix(prefix) {
            working = String(working.dropFirst(prefix.count))
        }
        let tokens = working.split(separator: "-").map(String.init)
        let head = tokens.first ?? ""

        if head == "claude" {
            return self.normalizeAnthropic(rawName: raw, tokens: tokens)
        }
        if head.hasPrefix("gpt") || head == "o1" || head == "o3" || head == "o4" {
            return self.normalizeOpenAI(rawName: raw, candidate: working, tokens: tokens)
        }
        if head == "gemini" {
            return self.normalizeGeneric(rawName: raw, tokens: tokens, provider: .google)
        }
        if head == "composer" || head == "cursor" || working == "auto" {
            return self.normalizeGeneric(rawName: raw, tokens: tokens, provider: .cursor)
        }
        return self.normalizeGeneric(rawName: raw, tokens: tokens, provider: .unknown)
    }

    private static func normalizeAnthropic(rawName: String, tokens: [String]) -> CursorNormalizedModel {
        var rest = Array(tokens.dropFirst())
        var mode: String?
        var effort: String?
        rest.removeAll { token in
            if self.modeTokens.contains(token) {
                mode = token
                return true
            }
            if self.effortTokens.contains(token) {
                effort = token
                return true
            }
            return false
        }

        let family = rest.first
        var versionTokens: [String] = []
        for token in rest.dropFirst() {
            guard !token.isEmpty, token.allSatisfy(\.isNumber) else { break }
            versionTokens.append(token)
        }
        let version = versionTokens.isEmpty ? nil : versionTokens.joined(separator: ".")

        let displayName: String = if let family {
            version.map { "\(family.capitalized) \($0)" } ?? family.capitalized
        } else {
            rawName
        }

        var pricingKey: String?
        if let family, !versionTokens.isEmpty {
            let candidate = (["claude", family] + versionTokens).joined(separator: "-")
            pricingKey = CostUsagePricing.supportedClaudePricingKey(candidate)
        }

        return CursorNormalizedModel(
            rawName: rawName,
            displayName: displayName,
            provider: .anthropic,
            family: family,
            version: version,
            mode: mode,
            effort: effort,
            pricingKey: pricingKey)
    }

    private static func normalizeOpenAI(rawName: String, candidate: String, tokens: [String]) -> CursorNormalizedModel {
        let head = tokens.first ?? ""
        let displayName: String
        if head.hasPrefix("gpt") {
            var name = "GPT"
            if tokens.count > 1 {
                name += "-\(tokens[1])"
            }
            let extras = tokens.dropFirst(2).map(\.capitalized)
            if !extras.isEmpty {
                name += " " + extras.joined(separator: " ")
            }
            displayName = name
        } else {
            displayName = tokens.map(\.capitalized).joined(separator: " ")
        }

        return CursorNormalizedModel(
            rawName: rawName,
            displayName: displayName.isEmpty ? rawName : displayName,
            provider: .openai,
            family: tokens.first,
            version: tokens.count > 1 ? tokens[1] : nil,
            mode: nil,
            effort: nil,
            pricingKey: CostUsagePricing.supportedCodexPricingKey(candidate))
    }

    private static func normalizeGeneric(
        rawName: String,
        tokens: [String],
        provider: CursorModelProvider) -> CursorNormalizedModel
    {
        let displayName = tokens.map(\.capitalized).joined(separator: " ")
        return CursorNormalizedModel(
            rawName: rawName,
            displayName: displayName.isEmpty ? rawName : displayName,
            provider: provider,
            family: tokens.first,
            version: tokens.count > 1 ? tokens[1] : nil,
            mode: nil,
            effort: nil,
            pricingKey: nil)
    }
}
