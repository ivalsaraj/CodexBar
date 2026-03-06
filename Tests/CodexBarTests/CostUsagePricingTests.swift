import Testing
@testable import CodexBarCore

@Suite
struct CostUsagePricingTests {
    @Test
    func normalizesCodexModelVariants() {
        #expect(CostUsagePricing.normalizeCodexModel("openai/gpt-5-codex") == "gpt-5")
        #expect(CostUsagePricing.normalizeCodexModel("gpt-5.2-codex") == "gpt-5.2")
        #expect(CostUsagePricing.normalizeCodexModel("gpt-5.1-codex-max") == "gpt-5.1")
        #expect(CostUsagePricing.normalizeCodexModel("gpt-5.3-codex-max") == "gpt-5.3")
        #expect(CostUsagePricing.normalizeCodexModel("gpt-5.4-codex") == "gpt-5.4")
        #expect(CostUsagePricing.normalizeCodexModel("gpt-5.4-codex-max") == "gpt-5.4")
        #expect(CostUsagePricing.normalizeCodexModel("gpt-5.4-pro") == "gpt-5.4-pro")
    }

    @Test
    func codexCostSupportsGpt51CodexMax() {
        let cost = CostUsagePricing.codexCostUSD(
            model: "gpt-5.1-codex-max",
            inputTokens: 100,
            cachedInputTokens: 10,
            outputTokens: 5)
        #expect(cost != nil)
    }

    @Test
    func codexCostSupportsGpt53CodexMax() {
        let cost = CostUsagePricing.codexCostUSD(
            model: "gpt-5.3-codex-max",
            inputTokens: 100,
            cachedInputTokens: 10,
            outputTokens: 5)
        #expect(cost != nil)
    }

    @Test
    func codexCostSupportsGpt54CodexVariants() {
        let direct = CostUsagePricing.codexCostUSD(
            model: "gpt-5.4",
            inputTokens: 100,
            cachedInputTokens: 10,
            outputTokens: 5)
        let codex = CostUsagePricing.codexCostUSD(
            model: "gpt-5.4-codex-max",
            inputTokens: 100,
            cachedInputTokens: 10,
            outputTokens: 5)
        let expected = Double(90) * 2.5e-6 + Double(10) * 2.5e-7 + Double(5) * 1.5e-5
        #expect(abs((direct ?? 0) - expected) < 0.000_000_000_001)
        #expect(codex == direct)
    }

    @Test
    func codexCostDoesNotTreatGpt54ProAsBaseGpt54() {
        let cost = CostUsagePricing.codexCostUSD(
            model: "gpt-5.4-pro",
            inputTokens: 100,
            cachedInputTokens: 10,
            outputTokens: 5)
        #expect(cost == nil)
    }

    @Test
    func normalizesClaudeOpus41DatedVariants() {
        #expect(CostUsagePricing.normalizeClaudeModel("claude-opus-4-1-20250805") == "claude-opus-4-1")
    }

    @Test
    func claudeCostSupportsOpus41DatedVariant() {
        let cost = CostUsagePricing.claudeCostUSD(
            model: "claude-opus-4-1-20250805",
            inputTokens: 10,
            cacheReadInputTokens: 0,
            cacheCreationInputTokens: 0,
            outputTokens: 5)
        #expect(cost != nil)
    }

    @Test
    func claudeCostSupportsOpus46DatedVariant() {
        let cost = CostUsagePricing.claudeCostUSD(
            model: "claude-opus-4-6-20260205",
            inputTokens: 10,
            cacheReadInputTokens: 0,
            cacheCreationInputTokens: 0,
            outputTokens: 5)
        #expect(cost != nil)
    }

    @Test
    func claudeCostReturnsNilForUnknownModels() {
        let cost = CostUsagePricing.claudeCostUSD(
            model: "glm-4.6",
            inputTokens: 100,
            cacheReadInputTokens: 500,
            cacheCreationInputTokens: 0,
            outputTokens: 40)
        #expect(cost == nil)
    }
}
