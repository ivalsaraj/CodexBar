import Foundation

/// Best-effort, local-only model-cost estimate for a single Cursor request row.
///
/// This is diagnostic only. Cursor legacy plans bill by request count, so every explanation carries
/// a disclaimer to that effect. An exact token breakdown can still yield a partial/unavailable cost
/// when the provider distinguishes a pricing tier (e.g. Claude cache-write duration) that Cursor does
/// not expose.
public struct CursorRequestCostEstimate: Equatable, Sendable {
    public let usd: Decimal?
    public let confidence: Confidence
    public let pricingKey: String?
    public let pricingSource: String?
    public let explanation: String

    public enum Confidence: String, Equatable, Sendable {
        case exactBreakdown
        case partialMissingCacheWriteTier
        case totalOnlyUnavailable
        case partialBreakdownUnavailable
        case unknownModel
        case missingPricing
        case missingBreakdown
    }

    public init(
        usd: Decimal?,
        confidence: Confidence,
        pricingKey: String?,
        pricingSource: String?,
        explanation: String)
    {
        self.usd = usd
        self.confidence = confidence
        self.pricingKey = pricingKey
        self.pricingSource = pricingSource
        self.explanation = explanation
    }
}

public enum CursorRequestCostEstimator {
    /// Stable disclaimer reused in hover/help so the UI never implies Cursor bills the legacy plan by dollars.
    public static let legacyDisclaimer = "Model-cost estimate only. Cursor legacy quota is request-based."
    private static let pricingSourceLabel = "CostUsagePricing local catalog (verified 2026-06-06)"

    public static func estimate(for request: CursorRecentRequest) -> CursorRequestCostEstimate {
        self.estimate(model: request.model, breakdown: request.tokenBreakdown)
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
            return self.unavailable(
                .totalOnlyUnavailable,
                pricingKey: pricingKey,
                reason: "Only a total token count was available, so no breakdown-based estimate is possible.")
        case .partialBreakdown:
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
            let tiersAmbiguous = CostUsagePricing
                .claudePricingCapabilities(model: pricingKey)?
                .distinguishesCacheWriteTiers ?? false

            if cacheWrite > 0, tiersAmbiguous {
                // Cursor does not expose the cache-write duration/tier, so exclude cache writes and
                // label the result as an incomplete lower bound rather than fake precision.
                guard let cost = CostUsagePricing.claudeCostUSD(
                    model: pricingKey,
                    inputTokens: input,
                    cacheReadInputTokens: cacheRead,
                    cacheCreationInputTokens: 0,
                    outputTokens: output)
                else {
                    return self.missingPricing(pricingKey: pricingKey)
                }
                let explanation = self.legacyDisclaimer
                    + " Cursor did not expose the cache-write tier, so cache writes are excluded"
                    + " and this estimate is incomplete."
                return CursorRequestCostEstimate(
                    usd: self.decimalUSD(cost),
                    confidence: .partialMissingCacheWriteTier,
                    pricingKey: pricingKey,
                    pricingSource: self.pricingSourceLabel,
                    explanation: explanation)
            }

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
                explanation: self.legacyDisclaimer)

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

        case .google, .cursor, .unknown:
            return self.unavailable(
                .unknownModel,
                pricingKey: pricingKey,
                reason: "This model has no known local pricing, so cost is unavailable.")
        }
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
