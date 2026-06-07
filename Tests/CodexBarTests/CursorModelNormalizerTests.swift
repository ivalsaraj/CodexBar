import Testing
@testable import CodexBarCore

struct CursorModelNormalizerTests {
    @Test
    func `normalizes claude opus 4-8 thinking xhigh`() {
        let model = CursorModelNormalizer.normalize("claude-opus-4-8-thinking-xhigh")
        #expect(model.rawName == "claude-opus-4-8-thinking-xhigh")
        #expect(model.displayName == "Opus 4.8")
        #expect(model.provider == .anthropic)
        #expect(model.family == "opus")
        #expect(model.version == "4.8")
        #expect(model.mode == "thinking")
        #expect(model.effort == "xhigh")
        #expect(model.pricingKey == "claude-opus-4-8")
    }

    @Test
    func `normalizes claude opus 4-7 thinking max`() {
        let model = CursorModelNormalizer.normalize("claude-opus-4-7-thinking-max")
        #expect(model.displayName == "Opus 4.7")
        #expect(model.provider == .anthropic)
        #expect(model.effort == "max")
        #expect(model.pricingKey == "claude-opus-4-7")
    }

    @Test
    func `normalizes claude sonnet 4-6 thinking without effort`() {
        let model = CursorModelNormalizer.normalize("claude-sonnet-4-6-thinking")
        #expect(model.displayName == "Sonnet 4.6")
        #expect(model.provider == .anthropic)
        #expect(model.mode == "thinking")
        #expect(model.effort == nil)
        #expect(model.pricingKey == "claude-sonnet-4-6")
    }

    @Test
    func `normalizes cursor composer model with no pricing key`() {
        let model = CursorModelNormalizer.normalize("composer-2.5")
        #expect(model.displayName == "Composer 2.5")
        #expect(model.provider == .cursor)
        #expect(model.pricingKey == nil)
    }

    @Test
    func `normalizes openai gpt model only when shared pricing covers it`() {
        let model = CursorModelNormalizer.normalize("gpt-5.4")
        #expect(model.displayName == "GPT-5.4")
        #expect(model.provider == .openai)
        #expect(model.pricingKey == "gpt-5.4")
    }

    @Test
    func `normalizes gemini model with display name but no pricing key`() {
        let model = CursorModelNormalizer.normalize("gemini-3.1-pro-preview")
        #expect(model.displayName == "Gemini 3.1 Pro Preview")
        #expect(model.provider == .google)
        #expect(model.pricingKey == nil)
    }

    @Test
    func `unknown model humanizes display name and has no pricing key`() {
        let model = CursorModelNormalizer.normalize("some-internal-model-x1")
        #expect(model.rawName == "some-internal-model-x1")
        #expect(model.provider == .unknown)
        #expect(model.pricingKey == nil)
        #expect(!model.displayName.isEmpty)
    }

    @Test
    func `effort never changes pricing key`() {
        let xhigh = CursorModelNormalizer.normalize("claude-opus-4-8-thinking-xhigh")
        let max = CursorModelNormalizer.normalize("claude-opus-4-8-thinking-max")
        let plain = CursorModelNormalizer.normalize("claude-opus-4-8")
        #expect(xhigh.pricingKey == "claude-opus-4-8")
        #expect(max.pricingKey == "claude-opus-4-8")
        #expect(plain.pricingKey == "claude-opus-4-8")
    }
}
