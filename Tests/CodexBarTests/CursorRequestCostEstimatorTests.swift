import Foundation
import Testing
@testable import CodexBarCore

struct CursorRequestCostEstimatorTests {
    private typealias TokenParts = (input: Int?, output: Int?, cacheRead: Int?, cacheWrite: Int?)

    private func breakdown(
        _ parts: TokenParts,
        total: Int,
        confidence: CursorRecentRequestTokenBreakdown.Confidence) -> CursorRecentRequestTokenBreakdown
    {
        CursorRecentRequestTokenBreakdown(
            inputTokens: parts.input,
            outputTokens: parts.output,
            cacheReadTokens: parts.cacheRead,
            cacheWriteTokens: parts.cacheWrite,
            totalTokens: total,
            confidence: confidence)
    }

    private func usd(_ value: Double) -> Decimal? {
        Decimal(string: String(format: "%.6f", value))
    }

    @Test
    func `exact claude estimate prices full breakdown when no cache writes`() {
        let bd = self.breakdown(
            (input: 1_000_000, output: 1_000_000, cacheRead: 0, cacheWrite: 0),
            total: 2_000_000,
            confidence: .exactBreakdown)
        let estimate = CursorRequestCostEstimator.estimate(model: "claude-opus-4-8-thinking-xhigh", breakdown: bd)
        #expect(estimate.confidence == .exactBreakdown)
        #expect(estimate.pricingKey == "claude-opus-4-8")
        #expect(estimate.pricingSource != nil)
        #expect(estimate.usd == self.usd(Double(1_000_000) * 5e-6 + Double(1_000_000) * 2.5e-5))
        #expect(estimate.explanation.contains("request-based"))
    }

    @Test
    func `claude cache writes default to five minute cache pricing`() {
        let bd = self.breakdown(
            (input: 100, output: 200, cacheRead: 300, cacheWrite: 400),
            total: 1000,
            confidence: .exactBreakdown)
        let estimate = CursorRequestCostEstimator.estimate(model: "claude-opus-4-8-thinking-xhigh", breakdown: bd)
        #expect(estimate.confidence == .exactBreakdown)
        #expect(estimate.usd == self.usd(
            Double(100) * 5e-6
                + Double(300) * 5e-7
                + Double(400) * 6.25e-6
                + Double(200) * 2.5e-5))
        #expect(estimate.explanation.lowercased().contains("5-minute"))
        #expect(estimate.explanation.contains("request-based"))
    }

    @Test
    func `partial breakdown returns no estimate`() {
        let bd = self.breakdown(
            (input: 100, output: 200, cacheRead: nil, cacheWrite: nil),
            total: 300,
            confidence: .partialBreakdown)
        let estimate = CursorRequestCostEstimator.estimate(model: "claude-opus-4-8-thinking-xhigh", breakdown: bd)
        #expect(estimate.confidence == .partialBreakdownUnavailable)
        #expect(estimate.usd == nil)
        #expect(estimate.explanation.contains("request-based"))
    }

    @Test
    func `anthropic total only estimate returns approximate range`() {
        let bd = self.breakdown(
            (input: nil, output: nil, cacheRead: nil, cacheWrite: nil),
            total: 252_000,
            confidence: .totalOnly)
        let estimate = CursorRequestCostEstimator.estimate(model: "claude-opus-4-8-thinking-max", breakdown: bd)
        #expect(estimate.confidence == .approximateTotalOnly)
        #expect(estimate.pricingKey == "claude-opus-4-8")
        #expect(estimate.lowerBoundUSD == self.usd(0.126))
        #expect(estimate.upperBoundUSD == self.usd(6.30))
        #expect(estimate.explanation.lowercased().contains("total tokens only"))
        #expect(estimate.explanation.lowercased().contains("unknown input/output/cache split"))
        #expect(estimate.explanation.contains("request-based"))
    }

    @Test
    func `fable exact estimate prices official rates`() {
        let bd = self.breakdown(
            (input: 1_000_000, output: 1_000_000, cacheRead: 1_000_000, cacheWrite: 1_000_000),
            total: 4_000_000,
            confidence: .exactBreakdown)
        let estimate = CursorRequestCostEstimator.estimate(model: "claude-fable-5-thinking-max", breakdown: bd)
        #expect(estimate.confidence == .exactBreakdown)
        #expect(estimate.pricingKey == "claude-fable-5")
        #expect(estimate.usd == self.usd(73.5))
        #expect(estimate.explanation.lowercased().contains("5-minute"))
    }

    @Test
    func `fable total only estimate returns approximate range`() {
        let bd = self.breakdown(
            (input: nil, output: nil, cacheRead: nil, cacheWrite: nil),
            total: 252_000,
            confidence: .totalOnly)
        let estimate = CursorRequestCostEstimator.estimate(model: "claude-fable-5-thinking-max", breakdown: bd)
        #expect(estimate.confidence == .approximateTotalOnly)
        #expect(estimate.pricingKey == "claude-fable-5")
        #expect(estimate.lowerBoundUSD == self.usd(0.252))
        #expect(estimate.upperBoundUSD == self.usd(12.60))
        #expect(estimate.explanation.lowercased().contains("unknown input/output/cache split"))
    }

    @Test
    func `anthropic total only estimate applies tiered pricing above threshold`() {
        let bd = self.breakdown(
            (input: nil, output: nil, cacheRead: nil, cacheWrite: nil),
            total: 250_000,
            confidence: .totalOnly)
        let estimate = CursorRequestCostEstimator.estimate(model: "claude-sonnet-4-6-thinking-max", breakdown: bd)
        #expect(estimate.confidence == .approximateTotalOnly)
        #expect(estimate.pricingKey == "claude-sonnet-4-6")
        #expect(estimate.lowerBoundUSD == self.usd(0.09))
        #expect(estimate.upperBoundUSD == self.usd(4.125))
        #expect(estimate.explanation.contains("request-based"))
    }

    @Test
    func `unknown model returns no estimate`() {
        let bd = self.breakdown(
            (input: 100, output: 200, cacheRead: 0, cacheWrite: 0),
            total: 300,
            confidence: .exactBreakdown)
        let estimate = CursorRequestCostEstimator.estimate(model: "some-internal-model-x1", breakdown: bd)
        #expect(estimate.confidence == .unknownModel)
        #expect(estimate.usd == nil)
        #expect(estimate.pricingKey == nil)
        #expect(estimate.explanation.contains("request-based"))
    }

    @Test
    func `composer fast estimate prices exact input and output breakdown`() {
        let bd = self.breakdown(
            (input: 1_000_000, output: 1_000_000, cacheRead: 0, cacheWrite: 0),
            total: 2_000_000,
            confidence: .exactBreakdown)
        let estimate = CursorRequestCostEstimator.estimate(model: "composer-2.5", breakdown: bd)
        #expect(estimate.confidence == .exactBreakdown)
        #expect(estimate.pricingKey == "composer-2.5-fast")
        #expect(estimate.usd == self.usd(18))
        #expect(estimate.explanation.contains("Fast"))
        #expect(estimate.explanation.contains("request-based"))
    }

    @Test
    func `composer standard estimate prices exact input and output breakdown`() {
        let bd = self.breakdown(
            (input: 1_000_000, output: 1_000_000, cacheRead: 0, cacheWrite: 0),
            total: 2_000_000,
            confidence: .exactBreakdown)
        let estimate = CursorRequestCostEstimator.estimate(model: "composer-2.5-standard", breakdown: bd)
        #expect(estimate.confidence == .exactBreakdown)
        #expect(estimate.pricingKey == "composer-2.5-standard")
        #expect(estimate.usd == self.usd(3))
    }

    @Test
    func `composer partial breakdown with input output and cache read prices estimate`() {
        let bd = self.breakdown(
            (input: 393_000, output: 26000, cacheRead: 4_500_000, cacheWrite: nil),
            total: 4_919_000,
            confidence: .partialBreakdown)
        let estimate = CursorRequestCostEstimator.estimate(model: "composer-2.5-fast", breakdown: bd)
        #expect(estimate.confidence == .exactBreakdown)
        #expect(estimate.pricingKey == "composer-2.5-fast")
        #expect(estimate.usd == self.usd(
            Double(393_000 + 4_500_000) * 3.0 / 1_000_000 + Double(26000) * 15.0 / 1_000_000))
        #expect(estimate.explanation.contains(CursorRequestCostEstimator.composerCacheCaveat))
    }

    @Test
    func `composer total only estimate returns approximate range`() {
        let bd = self.breakdown(
            (input: nil, output: nil, cacheRead: nil, cacheWrite: nil),
            total: 2_000_000,
            confidence: .totalOnly)
        let estimate = CursorRequestCostEstimator.estimate(model: "composer-2.5", breakdown: bd)
        #expect(estimate.confidence == .approximateTotalOnly)
        #expect(estimate.lowerBoundUSD != nil)
        #expect(estimate.upperBoundUSD != nil)
        #expect(estimate.explanation.lowercased().contains("approx"))
    }

    @Test
    func `missing breakdown returns no estimate`() {
        let estimate = CursorRequestCostEstimator.estimate(
            model: "claude-opus-4-8-thinking-xhigh",
            breakdown: nil)
        #expect(estimate.confidence == .missingBreakdown)
        #expect(estimate.usd == nil)
        #expect(estimate.explanation.contains("request-based"))
    }

    @Test
    func `openai estimate treats cache reads as discounted input and cache writes as free`() {
        let bd = self.breakdown(
            (input: 1_000_000, output: 0, cacheRead: 0, cacheWrite: 500_000),
            total: 1_500_000,
            confidence: .exactBreakdown)
        let estimate = CursorRequestCostEstimator.estimate(model: "gpt-5.4", breakdown: bd)
        #expect(estimate.confidence == .exactBreakdown)
        #expect(estimate.usd == self.usd(Double(1_000_000) * 2.5e-6))
    }

    @Test
    func `estimate accepts recent request directly`() {
        let request = CursorRecentRequest(
            timestamp: Date(timeIntervalSince1970: 1_770_201_720),
            model: "claude-opus-4-8-thinking-xhigh",
            tokens: 2_000_000,
            requests: 1,
            tokenBreakdown: breakdown(
                (input: 1_000_000, output: 1_000_000, cacheRead: 0, cacheWrite: 0),
                total: 2_000_000,
                confidence: .exactBreakdown))
        let estimate = CursorRequestCostEstimator.estimate(for: request)
        #expect(estimate.confidence == .exactBreakdown)
        #expect(estimate.usd != nil)
    }
}
