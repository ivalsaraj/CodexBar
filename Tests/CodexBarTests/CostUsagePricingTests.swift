import Testing
@testable import CodexBarCore

struct CostUsagePricingTests {
    @Test
    func `normalizes codex model variants exactly`() {
        #expect(CostUsagePricing.normalizeCodexModel("openai/gpt-5-codex") == "gpt-5-codex")
        #expect(CostUsagePricing.normalizeCodexModel("gpt-5.2-codex") == "gpt-5.2-codex")
        #expect(CostUsagePricing.normalizeCodexModel("gpt-5.1-codex-max") == "gpt-5.1-codex-max")
        #expect(CostUsagePricing.normalizeCodexModel("gpt-5.4-pro-2026-03-05") == "gpt-5.4-pro")
        #expect(CostUsagePricing.normalizeCodexModel("gpt-5.4-mini-2026-03-17") == "gpt-5.4-mini")
        #expect(CostUsagePricing.normalizeCodexModel("gpt-5.4-nano-2026-03-17") == "gpt-5.4-nano")
        #expect(CostUsagePricing.normalizeCodexModel("gpt-5.3-codex-2026-03-05") == "gpt-5.3-codex")
        #expect(CostUsagePricing.normalizeCodexModel("gpt-5.3-codex-spark") == "gpt-5.3-codex-spark")
    }

    @Test
    func `codex cost supports gpt51 codex max`() {
        let cost = CostUsagePricing.codexCostUSD(
            model: "gpt-5.1-codex-max",
            inputTokens: 100,
            cachedInputTokens: 10,
            outputTokens: 5)
        #expect(cost != nil)
    }

    @Test
    func `codex cost supports gpt53 codex`() {
        let cost = CostUsagePricing.codexCostUSD(
            model: "gpt-5.3-codex",
            inputTokens: 100,
            cachedInputTokens: 10,
            outputTokens: 5)
        #expect(cost != nil)
    }

    @Test
    func codexCostSupportsGpt54BaseVariant() {
        let direct = CostUsagePricing.codexCostUSD(
            model: "gpt-5.4",
            inputTokens: 100,
            cachedInputTokens: 10,
            outputTokens: 5)
        let expected = Double(90) * 2.5e-6 + Double(10) * 2.5e-7 + Double(5) * 1.5e-5
        #expect(abs((direct ?? 0) - expected) < 0.000_000_000_001)
    }

    @Test
    func `codex cost supports gpt55 three tier pricing`() {
        let direct = CostUsagePricing.codexCostUSD(
            model: "gpt-5.5",
            inputTokens: 100,
            cachedInputTokens: 10,
            outputTokens: 5)
        let expected = Double(90) * 5e-6 + Double(10) * 5e-7 + Double(5) * 3e-5
        #expect(abs((direct ?? 0) - expected) < 0.000_000_000_001)

        let capabilities = CostUsagePricing.codexPricingCapabilities(model: "gpt-5.5")
        #expect(capabilities?.inputCostPerToken == 5e-6)
        #expect(capabilities?.cacheReadInputCostPerToken == 5e-7)
        #expect(capabilities?.outputCostPerToken == 3e-5)
    }

    @Test
    func codexCostGpt54ProHasItsOwnPricing() {
        let cost = CostUsagePricing.codexCostUSD(
            model: "gpt-5.4-pro",
            inputTokens: 100,
            cachedInputTokens: 10,
            outputTokens: 5)
        // gpt-5.4-pro has a dedicated entry in the pricing dict
        #expect(cost != nil)
    }

    @Test
    func `codex cost supports gpt54 mini and nano`() {
        let mini = CostUsagePricing.codexCostUSD(
            model: "gpt-5.4-mini-2026-03-17",
            inputTokens: 100,
            cachedInputTokens: 10,
            outputTokens: 5)
        let nano = CostUsagePricing.codexCostUSD(
            model: "gpt-5.4-nano",
            inputTokens: 100,
            cachedInputTokens: 10,
            outputTokens: 5)

        #expect(mini != nil)
        #expect(nano != nil)
    }

    @Test
    func `codex cost returns zero for research preview model`() {
        let cost = CostUsagePricing.codexCostUSD(
            model: "gpt-5.3-codex-spark",
            inputTokens: 100,
            cachedInputTokens: 10,
            outputTokens: 5)
        #expect(cost == 0)
        #expect(CostUsagePricing.codexDisplayLabel(model: "gpt-5.3-codex-spark") == "Research Preview")
        #expect(CostUsagePricing.codexDisplayLabel(model: "gpt-5.2-codex") == nil)
    }

    @Test
    func `normalizes claude opus41 dated variants`() {
        #expect(CostUsagePricing.normalizeClaudeModel("claude-opus-4-1-20250805") == "claude-opus-4-1")
    }

    @Test
    func `claude cost supports opus41 dated variant`() {
        let cost = CostUsagePricing.claudeCostUSD(
            model: "claude-opus-4-1-20250805",
            inputTokens: 10,
            cacheReadInputTokens: 0,
            cacheCreationInputTokens: 0,
            outputTokens: 5)
        #expect(cost != nil)
    }

    @Test
    func `claude cost supports opus46 dated variant`() {
        let cost = CostUsagePricing.claudeCostUSD(
            model: "claude-opus-4-6-20260205",
            inputTokens: 10,
            cacheReadInputTokens: 0,
            cacheCreationInputTokens: 0,
            outputTokens: 5)
        #expect(cost != nil)
    }

    @Test
    func `claude cost returns nil for unknown models`() {
        let cost = CostUsagePricing.claudeCostUSD(
            model: "glm-4.6",
            inputTokens: 100,
            cacheReadInputTokens: 500,
            cacheCreationInputTokens: 0,
            outputTokens: 40)
        #expect(cost == nil)
    }

    @Test
    func `claude opus 4-8 normalizes and prices flat`() {
        #expect(CostUsagePricing.normalizeClaudeModel("claude-opus-4-8") == "claude-opus-4-8")
        let cost = CostUsagePricing.claudeCostUSD(
            model: "claude-opus-4-8",
            inputTokens: 1_000_000,
            cacheReadInputTokens: 0,
            cacheCreationInputTokens: 0,
            outputTokens: 1_000_000)
        let expected = Double(1_000_000) * 5e-6 + Double(1_000_000) * 2.5e-5
        #expect(cost != nil)
        #expect(abs((cost ?? 0) - expected) < 1e-9)
    }

    @Test
    func `claude opus 4-7 normalizes and prices flat`() {
        #expect(CostUsagePricing.normalizeClaudeModel("claude-opus-4-7") == "claude-opus-4-7")
        let cost = CostUsagePricing.claudeCostUSD(
            model: "claude-opus-4-7",
            inputTokens: 500_000,
            cacheReadInputTokens: 0,
            cacheCreationInputTokens: 0,
            outputTokens: 0)
        let expected = Double(500_000) * 5e-6
        #expect(abs((cost ?? 0) - expected) < 1e-9)
    }

    @Test
    func `claude fable 5 normalizes and prices official rates`() {
        #expect(CostUsagePricing.normalizeClaudeModel("claude-fable-5") == "claude-fable-5")
        let cost = CostUsagePricing.claudeCostUSD(
            model: "claude-fable-5",
            inputTokens: 1_000_000,
            cacheReadInputTokens: 1_000_000,
            cacheCreationInputTokens: 1_000_000,
            outputTokens: 1_000_000)
        let expected = 10 + 1 + 12.5 + 50
        #expect(abs((cost ?? 0) - expected) < 1e-9)
    }

    @Test
    func `claude opus cache read uses discounted rate`() {
        let cost = CostUsagePricing.claudeCostUSD(
            model: "claude-opus-4-8",
            inputTokens: 0,
            cacheReadInputTokens: 1_000_000,
            cacheCreationInputTokens: 0,
            outputTokens: 0)
        let expected = Double(1_000_000) * 5e-7
        #expect(abs((cost ?? 0) - expected) < 1e-9)
    }

    @Test
    func `claude opus stays flat above large context`() {
        // Opus has no long-context surcharge: 2M input priced at the flat input rate.
        let cost = CostUsagePricing.claudeCostUSD(
            model: "claude-opus-4-8",
            inputTokens: 2_000_000,
            cacheReadInputTokens: 0,
            cacheCreationInputTokens: 0,
            outputTokens: 0)
        let expected = Double(2_000_000) * 5e-6
        #expect(abs((cost ?? 0) - expected) < 1e-9)
    }

    @Test
    func `claude sonnet applies long context threshold surcharge`() {
        let cost = CostUsagePricing.claudeCostUSD(
            model: "claude-sonnet-4-6",
            inputTokens: 300_000,
            cacheReadInputTokens: 0,
            cacheCreationInputTokens: 0,
            outputTokens: 0)
        let below = Double(200_000) * 3e-6
        let above = Double(100_000) * 6e-6
        #expect(abs((cost ?? 0) - (below + above)) < 1e-9)
    }

    @Test
    func `shared pricing coverage helpers gate on catalog presence`() {
        #expect(CostUsagePricing.supportedClaudePricingKey("claude-opus-4-8") == "claude-opus-4-8")
        #expect(CostUsagePricing.supportedClaudePricingKey("claude-opus-4-7") == "claude-opus-4-7")
        #expect(CostUsagePricing.supportedClaudePricingKey("glm-4.6") == nil)
        #expect(CostUsagePricing.supportedCodexPricingKey("gpt-5.4") == "gpt-5.4")
        #expect(CostUsagePricing.supportedCodexPricingKey("composer-2.5") == nil)
    }

    @Test
    func `openai pricing key prices through shared codex catalog`() {
        let cost = CostUsagePricing.codexCostUSD(
            model: "gpt-5.4",
            inputTokens: 1_000_000,
            cachedInputTokens: 0,
            outputTokens: 0)
        let expected = Double(1_000_000) * 2.5e-6
        #expect(abs((cost ?? 0) - expected) < 1e-9)
    }

    @Test
    func `claude pricing capabilities expose official rates`() throws {
        let fable = try #require(CostUsagePricing.claudePricingCapabilities(model: "claude-fable-5"))
        #expect(fable.distinguishesCacheWriteTiers == true)
        #expect(fable.inputCostPerToken == 1.0e-5)
        #expect(fable.outputCostPerToken == 5.0e-5)
        #expect(fable.cacheCreationInputCostPerToken == 1.25e-5)
        #expect(fable.cacheReadInputCostPerToken == 1.0e-6)
        #expect(fable.thresholdTokens == nil)
        #expect(fable.inputCostPerTokenAboveThreshold == nil)

        let opus = try #require(CostUsagePricing.claudePricingCapabilities(model: "claude-opus-4-8"))
        #expect(opus.distinguishesCacheWriteTiers == true)
        #expect(opus.inputCostPerToken == 5.0e-6)
        #expect(opus.outputCostPerToken == 2.5e-5)
        #expect(opus.cacheCreationInputCostPerToken == 6.25e-6)
        #expect(opus.cacheReadInputCostPerToken == 5.0e-7)
        #expect(opus.thresholdTokens == nil)

        #expect(CostUsagePricing.claudePricingCapabilities(model: "glm-4.6") == nil)
    }
}
