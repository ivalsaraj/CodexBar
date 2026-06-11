import Foundation

/// Aggregated cycle-level cost summary across priced Cursor request rows.
public struct CursorRequestCostSummary: Equatable, Sendable {
    public let exactUSD: Decimal?
    public let lowerBoundUSD: Decimal?
    public let upperBoundUSD: Decimal?
    public let containsApproximation: Bool

    public init(
        exactUSD: Decimal?,
        lowerBoundUSD: Decimal?,
        upperBoundUSD: Decimal?,
        containsApproximation: Bool)
    {
        self.exactUSD = exactUSD
        self.lowerBoundUSD = lowerBoundUSD
        self.upperBoundUSD = upperBoundUSD
        self.containsApproximation = containsApproximation
    }
}

/// Best-effort, local-only model-cost estimate for a single Cursor request row.
///
/// This is diagnostic only. Cursor legacy plans bill by request count, so every explanation carries
/// a disclaimer to that effect.
public struct CursorRequestCostEstimate: Equatable, Sendable {
    public let usd: Decimal?
    public let lowerBoundUSD: Decimal?
    public let upperBoundUSD: Decimal?
    public let confidence: Confidence
    public let pricingKey: String?
    public let pricingSource: String?
    public let explanation: String

    public enum Confidence: String, Equatable, Sendable {
        case exactBreakdown
        case approximateTotalOnly
        case partialMissingCacheWriteTier
        case totalOnlyUnavailable
        case partialBreakdownUnavailable
        case unknownModel
        case missingPricing
        case missingBreakdown
    }

    public init(
        usd: Decimal?,
        lowerBoundUSD: Decimal? = nil,
        upperBoundUSD: Decimal? = nil,
        confidence: Confidence,
        pricingKey: String?,
        pricingSource: String?,
        explanation: String)
    {
        self.usd = usd
        self.lowerBoundUSD = lowerBoundUSD
        self.upperBoundUSD = upperBoundUSD
        self.confidence = confidence
        self.pricingKey = pricingKey
        self.pricingSource = pricingSource
        self.explanation = explanation
    }
}

public enum CursorRequestCostEstimator {
    /// Stable disclaimer reused in hover/help so the UI never implies Cursor bills the legacy plan by dollars.
    public static let legacyDisclaimer = "Model-cost estimate only. Cursor legacy quota is request-based."
    public static let claudeCacheAssumption = "Assumes Anthropic 5-minute cache-write pricing."
    public static let composerCacheCaveat =
        "Composer cache tokens count as input-equivalent; no separate Composer cache billing published."
    private static let pricingSourceLabel = "CostUsagePricing local catalog (verified 2026-06-11)"

    private struct CursorModelPricing: Equatable, Sendable {
        let inputUSDPerToken: Double
        let outputUSDPerToken: Double
        let label: String
        let source: String
    }

    private static let cursorPricing: [String: CursorModelPricing] = [
        "composer-2.5-fast": .init(
            inputUSDPerToken: 3.0 / 1_000_000,
            outputUSDPerToken: 15.0 / 1_000_000,
            label: "Composer 2.5 Fast",
            source: "Cursor Composer 2.5 changelog, checked 2026-06-08"),
        "composer-2.5-standard": .init(
            inputUSDPerToken: 0.5 / 1_000_000,
            outputUSDPerToken: 2.5 / 1_000_000,
            label: "Composer 2.5 Standard",
            source: "Cursor Composer 2.5 changelog, checked 2026-06-08"),
    ]

    public static func estimate(for request: CursorRecentRequest) -> CursorRequestCostEstimate {
        if let breakdown = request.tokenBreakdown {
            if breakdown.confidence == .empty,
               let estimate = self.anthropicTotalOnlyFallbackEstimate(model: request.model, tokens: request.tokens)
            {
                return estimate
            }
            return self.estimate(model: request.model, breakdown: breakdown)
        }

        if let estimate = self.anthropicTotalOnlyFallbackEstimate(model: request.model, tokens: request.tokens) {
            return estimate
        }

        return self.estimate(model: request.model, breakdown: nil)
    }

    private static func anthropicTotalOnlyFallbackEstimate(model: String, tokens: Int) -> CursorRequestCostEstimate? {
        let normalized = CursorModelNormalizer.normalize(model)
        guard normalized.provider == .anthropic,
              let pricingKey = normalized.pricingKey,
              CostUsagePricing.claudePricingCapabilities(model: pricingKey) != nil,
              tokens > 0
        else {
            return nil
        }

        return self.estimate(
            model: model,
            breakdown: CursorRecentRequestTokenBreakdown(
                inputTokens: nil,
                outputTokens: nil,
                cacheReadTokens: nil,
                cacheWriteTokens: nil,
                totalTokens: tokens,
                confidence: .totalOnly))
    }

    public static func summedUSD(for requests: [CursorRecentRequest]) -> Decimal? {
        self.summarizedEstimate(for: requests)?.exactUSD
    }

    public static func summarizedEstimate(for requests: [CursorRecentRequest]) -> CursorRequestCostSummary? {
        var exactUSD: Decimal = 0
        var lowerBoundUSD: Decimal = 0
        var upperBoundUSD: Decimal = 0
        var hasContribution = false
        var containsApproximation = false

        for request in requests {
            let estimate = self.estimate(for: request)
            switch estimate.confidence {
            case .exactBreakdown:
                guard let usd = estimate.usd else { continue }
                exactUSD += usd
                lowerBoundUSD += usd
                upperBoundUSD += usd
                hasContribution = true
            case .approximateTotalOnly:
                guard let lower = estimate.lowerBoundUSD, let upper = estimate.upperBoundUSD else { continue }
                lowerBoundUSD += lower
                upperBoundUSD += upper
                containsApproximation = true
                hasContribution = true
            default:
                continue
            }
        }

        guard hasContribution else { return nil }

        return CursorRequestCostSummary(
            exactUSD: containsApproximation ? nil : exactUSD,
            lowerBoundUSD: lowerBoundUSD,
            upperBoundUSD: upperBoundUSD,
            containsApproximation: containsApproximation)
    }

    public static func estimate(
        model rawModel: String,
        breakdown: CursorRecentRequestTokenBreakdown?) -> CursorRequestCostEstimate
    {
        let normalized = CursorModelNormalizer.normalize(rawModel)

        guard let breakdown else {
            return self.unavailable(
                .missingBreakdown,
                pricingKey: normalized.pricingKey,
                reason: "No token breakdown was available, so no estimate is possible.")
        }
        guard let pricingKey = normalized.pricingKey else {
            return self.unavailable(
                .unknownModel,
                pricingKey: nil,
                reason: "This model has no known local pricing, so cost is unavailable.")
        }

        switch breakdown.confidence {
        case .empty:
            return self.unavailable(
                .missingBreakdown,
                pricingKey: pricingKey,
                reason: "No token breakdown was available, so no estimate is possible.")
        case .totalOnly:
            if normalized.provider == .cursor, self.cursorPricing[pricingKey] != nil {
                return self.pricedCursorTotalOnly(pricingKey: pricingKey, breakdown: breakdown)
            }
            if normalized.provider == .anthropic,
               CostUsagePricing.claudePricingCapabilities(model: pricingKey) != nil
            {
                return self.pricedAnthropicTotalOnly(pricingKey: pricingKey, breakdown: breakdown)
            }
            return self.unavailable(
                .totalOnlyUnavailable,
                pricingKey: pricingKey,
                reason: "Only a total token count was available, so no breakdown-based estimate is possible.")
        case .partialBreakdown:
            if normalized.provider == .cursor,
               self.cursorPricing[pricingKey] != nil,
               self.composerHasPricedInputOutput(breakdown)
            {
                return self.pricedCursorExact(pricingKey: pricingKey, breakdown: breakdown)
            }
            return self.unavailable(
                .partialBreakdownUnavailable,
                pricingKey: pricingKey,
                reason: "The token breakdown was incomplete, so no estimate is possible.")
        case .exactBreakdown:
            return self.priced(provider: normalized.provider, pricingKey: pricingKey, breakdown: breakdown)
        }
    }

    private static func priced(
        provider: CursorModelProvider,
        pricingKey: String,
        breakdown: CursorRecentRequestTokenBreakdown) -> CursorRequestCostEstimate
    {
        let input = breakdown.inputTokens ?? 0
        let output = breakdown.outputTokens ?? 0
        let cacheRead = breakdown.cacheReadTokens ?? 0
        let cacheWrite = breakdown.cacheWriteTokens ?? 0

        switch provider {
        case .anthropic:
            guard let cost = CostUsagePricing.claudeCostUSD(
                model: pricingKey,
                inputTokens: input,
                cacheReadInputTokens: cacheRead,
                cacheCreationInputTokens: cacheWrite,
                outputTokens: output)
            else {
                return self.missingPricing(pricingKey: pricingKey)
            }
            return CursorRequestCostEstimate(
                usd: self.decimalUSD(cost),
                confidence: .exactBreakdown,
                pricingKey: pricingKey,
                pricingSource: self.pricingSourceLabel,
                explanation: [
                    self.legacyDisclaimer,
                    "\(CursorModelNormalizer.normalize(pricingKey).displayName) pricing.",
                    self.pricingSourceLabel,
                    self.claudeCacheAssumption,
                ].joined(separator: " "))

        case .openai:
            // OpenAI prices cache writes at zero and discounts cache reads as cached input.
            guard let cost = CostUsagePricing.codexCostUSD(
                model: pricingKey,
                inputTokens: input + cacheRead,
                cachedInputTokens: cacheRead,
                outputTokens: output)
            else {
                return self.missingPricing(pricingKey: pricingKey)
            }
            return CursorRequestCostEstimate(
                usd: self.decimalUSD(cost),
                confidence: .exactBreakdown,
                pricingKey: pricingKey,
                pricingSource: self.pricingSourceLabel,
                explanation: self.legacyDisclaimer)

        case .cursor:
            return self.pricedCursorExact(pricingKey: pricingKey, breakdown: breakdown)

        case .google, .unknown:
            return self.unavailable(
                .unknownModel,
                pricingKey: pricingKey,
                reason: "This model has no known local pricing, so cost is unavailable.")
        }
    }

    /// Composer can price when input and output are known; cache fields are optional and count as input-equivalent.
    private static func composerHasPricedInputOutput(_ breakdown: CursorRecentRequestTokenBreakdown) -> Bool {
        breakdown.inputTokens != nil && breakdown.outputTokens != nil
    }

    private static func pricedCursorExact(
        pricingKey: String,
        breakdown: CursorRecentRequestTokenBreakdown) -> CursorRequestCostEstimate
    {
        guard let pricing = self.cursorPricing[pricingKey] else {
            return self.unavailable(
                .unknownModel,
                pricingKey: pricingKey,
                reason: "This model has no known local pricing, so cost is unavailable.")
        }

        let billableInput = (breakdown.inputTokens ?? 0)
            + (breakdown.cacheReadTokens ?? 0)
            + (breakdown.cacheWriteTokens ?? 0)
        let billableOutput = breakdown.outputTokens ?? 0
        let cost = Double(billableInput) * pricing.inputUSDPerToken
            + Double(billableOutput) * pricing.outputUSDPerToken

        var explanationParts = [
            self.legacyDisclaimer,
            "\(pricing.label) pricing.",
            pricing.source,
        ]
        if (breakdown.cacheReadTokens ?? 0) > 0 || (breakdown.cacheWriteTokens ?? 0) > 0 {
            explanationParts.append(self.composerCacheCaveat)
        }

        return CursorRequestCostEstimate(
            usd: self.decimalUSD(cost),
            confidence: .exactBreakdown,
            pricingKey: pricingKey,
            pricingSource: pricing.source,
            explanation: explanationParts.joined(separator: " "))
    }

    private static func pricedCursorTotalOnly(
        pricingKey: String,
        breakdown: CursorRecentRequestTokenBreakdown) -> CursorRequestCostEstimate
    {
        guard let pricing = self.cursorPricing[pricingKey] else {
            return self.unavailable(
                .totalOnlyUnavailable,
                pricingKey: pricingKey,
                reason: "Only a total token count was available, so no breakdown-based estimate is possible.")
        }

        let total = breakdown.totalTokens
        let lower = Double(total) * pricing.inputUSDPerToken
        let upper = Double(total) * pricing.outputUSDPerToken

        return CursorRequestCostEstimate(
            usd: nil,
            lowerBoundUSD: self.decimalUSD(lower),
            upperBoundUSD: self.decimalUSD(upper),
            confidence: .approximateTotalOnly,
            pricingKey: pricingKey,
            pricingSource: pricing.source,
            explanation: [
                self.legacyDisclaimer,
                "Approximate range from total tokens only.",
                "\(pricing.label) pricing.",
                pricing.source,
            ].joined(separator: " "))
    }

    private static func pricedAnthropicTotalOnly(
        pricingKey: String,
        breakdown: CursorRecentRequestTokenBreakdown) -> CursorRequestCostEstimate
    {
        guard let pricing = CostUsagePricing.claudePricingCapabilities(model: pricingKey) else {
            return self.missingPricing(pricingKey: pricingKey)
        }

        let total = max(0, breakdown.totalTokens)
        let scenarioCosts = [
            self.claudeTotalOnlyCost(
                tokens: total,
                base: pricing.cacheReadInputCostPerToken,
                above: pricing.cacheReadInputCostPerTokenAboveThreshold,
                threshold: pricing.thresholdTokens),
            self.claudeTotalOnlyCost(
                tokens: total,
                base: pricing.inputCostPerToken,
                above: pricing.inputCostPerTokenAboveThreshold,
                threshold: pricing.thresholdTokens),
            self.claudeTotalOnlyCost(
                tokens: total,
                base: pricing.cacheCreationInputCostPerToken,
                above: pricing.cacheCreationInputCostPerTokenAboveThreshold,
                threshold: pricing.thresholdTokens),
            self.claudeTotalOnlyCost(
                tokens: total,
                base: pricing.outputCostPerToken,
                above: pricing.outputCostPerTokenAboveThreshold,
                threshold: pricing.thresholdTokens),
        ]
        let lower = scenarioCosts.min()
        let upper = scenarioCosts.max()

        guard let lower, let upper else {
            return self.missingPricing(pricingKey: pricingKey)
        }

        return CursorRequestCostEstimate(
            usd: nil,
            lowerBoundUSD: self.decimalUSD(lower),
            upperBoundUSD: self.decimalUSD(upper),
            confidence: .approximateTotalOnly,
            pricingKey: pricingKey,
            pricingSource: self.pricingSourceLabel,
            explanation: [
                self.legacyDisclaimer,
                "Approximate range from total tokens only.",
                "\(CursorModelNormalizer.normalize(pricingKey).displayName) pricing.",
                self.pricingSourceLabel,
                "Unknown input/output/cache split; Cursor exposed only a total token count here.",
                self.claudeCacheAssumption,
            ].joined(separator: " "))
    }

    private static func claudeTotalOnlyCost(
        tokens: Int,
        base: Double,
        above: Double?,
        threshold: Int?) -> Double
    {
        guard let threshold, let above else {
            return Double(tokens) * base
        }
        let below = min(tokens, threshold)
        let over = max(tokens - threshold, 0)
        return Double(below) * base + Double(over) * above
    }

    private static func missingPricing(pricingKey: String) -> CursorRequestCostEstimate {
        self.unavailable(
            .missingPricing,
            pricingKey: pricingKey,
            reason: "No local pricing rule covers this model, so cost is unavailable.")
    }

    private static func unavailable(
        _ confidence: CursorRequestCostEstimate.Confidence,
        pricingKey: String?,
        reason: String) -> CursorRequestCostEstimate
    {
        CursorRequestCostEstimate(
            usd: nil,
            confidence: confidence,
            pricingKey: pricingKey,
            pricingSource: nil,
            explanation: self.legacyDisclaimer + " " + reason)
    }

    private static func decimalUSD(_ value: Double) -> Decimal {
        Decimal(string: String(format: "%.6f", max(0, value))) ?? Decimal(max(0, value))
    }
}
