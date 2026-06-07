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
    func `claude cache writes drop confidence to partial missing tier and exclude write cost`() {
        let bd = self.breakdown(
            (input: 100, output: 200, cacheRead: 300, cacheWrite: 400),
            total: 1000,
            confidence: .exactBreakdown)
        let estimate = CursorRequestCostEstimator.estimate(model: "claude-opus-4-8-thinking-xhigh", breakdown: bd)
        #expect(estimate.confidence == .partialMissingCacheWriteTier)
        #expect(estimate.usd == self.usd(Double(100) * 5e-6 + Double(300) * 5e-7 + Double(200) * 2.5e-5))
        #expect(estimate.explanation.lowercased().contains("cache-write"))
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
    func `total only breakdown returns no estimate`() {
        let bd = self.breakdown(
            (input: nil, output: nil, cacheRead: nil, cacheWrite: nil),
            total: 35_000_000,
            confidence: .totalOnly)
        let estimate = CursorRequestCostEstimator.estimate(model: "claude-opus-4-8-thinking-xhigh", breakdown: bd)
        #expect(estimate.confidence == .totalOnlyUnavailable)
        #expect(estimate.usd == nil)
        #expect(estimate.explanation.contains("request-based"))
    }

    @Test
    func `unknown model returns no estimate`() {
        let bd = self.breakdown(
            (input: 100, output: 200, cacheRead: 0, cacheWrite: 0),
            total: 300,
            confidence: .exactBreakdown)
        let estimate = CursorRequestCostEstimator.estimate(model: "composer-2.5", breakdown: bd)
        #expect(estimate.confidence == .unknownModel)
        #expect(estimate.usd == nil)
        #expect(estimate.pricingKey == nil)
        #expect(estimate.explanation.contains("request-based"))
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
