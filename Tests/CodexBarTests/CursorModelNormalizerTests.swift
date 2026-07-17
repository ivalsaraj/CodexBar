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
    func `normalizes claude fable 5 with pricing key`() {
        let model = CursorModelNormalizer.normalize("claude-fable-5-thinking-max")
        #expect(model.rawName == "claude-fable-5-thinking-max")
        #expect(model.displayName == "Fable 5")
        #expect(model.provider == .anthropic)
        #expect(model.family == "fable")
        #expect(model.version == "5")
        #expect(model.mode == "thinking")
        #expect(model.effort == "max")
        #expect(model.pricingKey == "claude-fable-5")
    }

    @Test
    func `normalizes bare anthropic opus family as claude model`() {
        let model = CursorModelNormalizer.normalize("opus-4-6-thinking-max")
        #expect(model.rawName == "opus-4-6-thinking-max")
        #expect(model.displayName == "Opus 4.6")
        #expect(model.provider == .anthropic)
        #expect(model.family == "opus")
        #expect(model.version == "4.6")
        #expect(model.mode == "thinking")
        #expect(model.effort == "max")
        #expect(model.pricingKey == "claude-opus-4-6")
        #expect(UsageFormatter.cursorCompactModelLabel(model) == "Opus 4.6 · max")
    }

    @Test
    func `normalizes bare anthropic sonnet family as claude model`() {
        let model = CursorModelNormalizer.normalize("sonnet-4-6-thinking")
        #expect(model.displayName == "Sonnet 4.6")
        #expect(model.provider == .anthropic)
        #expect(model.family == "sonnet")
        #expect(model.version == "4.6")
        #expect(model.mode == "thinking")
        #expect(model.effort == nil)
        #expect(model.pricingKey == "claude-sonnet-4-6")
    }

    @Test
    func `normalizes version first claude opus row as opus model`() {
        let model = CursorModelNormalizer.normalize("claude-4.6-opus-max-thinking")
        #expect(model.rawName == "claude-4.6-opus-max-thinking")
        #expect(model.displayName == "Opus 4.6")
        #expect(model.provider == .anthropic)
        #expect(model.family == "opus")
        #expect(model.version == "4.6")
        #expect(model.mode == "thinking")
        #expect(model.effort == "max")
        #expect(model.pricingKey == "claude-opus-4-6")
        #expect(UsageFormatter.cursorCompactModelLabel(model) == "Opus 4.6 · max")
    }

    @Test
    func `normalizes familyless claude opus decimal version as opus model`() {
        let model = CursorModelNormalizer.normalize("claude-4.6-thinking-max")
        #expect(model.rawName == "claude-4.6-thinking-max")
        #expect(model.displayName == "Opus 4.6")
        #expect(model.provider == .anthropic)
        #expect(model.family == "opus")
        #expect(model.version == "4.6")
        #expect(model.mode == "thinking")
        #expect(model.effort == "max")
        #expect(model.pricingKey == "claude-opus-4-6")
        #expect(UsageFormatter.cursorCompactModelLabel(model) == "Opus 4.6 · max")
    }

    @Test
    func `normalizes familyless claude opus hyphen version as opus model`() {
        let model = CursorModelNormalizer.normalize("claude-4-6-thinking-max")
        #expect(model.displayName == "Opus 4.6")
        #expect(model.provider == .anthropic)
        #expect(model.family == "opus")
        #expect(model.version == "4.6")
        #expect(model.effort == "max")
        #expect(model.pricingKey == "claude-opus-4-6")
        #expect(UsageFormatter.cursorCompactModelLabel(model) == "Opus 4.6 · max")
    }

    @Test
    func `normalizes familyless claude version without effort as claude model`() {
        let model = CursorModelNormalizer.normalize("claude-4.6-thinking")
        #expect(model.displayName == "Claude 4.6")
        #expect(model.provider == .anthropic)
        #expect(model.family == "claude")
        #expect(model.version == "4.6")
        #expect(model.mode == "thinking")
        #expect(model.effort == nil)
        #expect(model.pricingKey == nil)
    }

    @Test
    func `normalizes cursor composer model with fast pricing key by default`() {
        let model = CursorModelNormalizer.normalize("composer-2.5")
        #expect(model.displayName == "Composer 2.5")
        #expect(model.provider == .cursor)
        #expect(model.family == "composer")
        #expect(model.version == "2.5")
        #expect(model.mode == "fast")
        #expect(model.pricingKey == "composer-2.5-fast")
    }

    @Test
    func `normalizes cursor composer standard pricing key`() {
        let model = CursorModelNormalizer.normalize("composer-2.5-standard")
        #expect(model.displayName == "Composer 2.5")
        #expect(model.provider == .cursor)
        #expect(model.mode == "standard")
        #expect(model.pricingKey == "composer-2.5-standard")
    }

    @Test
    func `normalizes non 2 5 composer without pricing key`() {
        let model = CursorModelNormalizer.normalize("composer-2.4")
        #expect(model.displayName == "Composer 2.4")
        #expect(model.provider == .cursor)
        #expect(model.pricingKey == nil)
        #expect(model.mode == nil)
    }

    @Test
    func `normalizes openai gpt model only when shared pricing covers it`() {
        let model = CursorModelNormalizer.normalize("gpt-5.4")
        #expect(model.displayName == "GPT-5.4")
        #expect(model.provider == .openai)
        #expect(model.pricingKey == "gpt-5.4")
    }

    @Test
    func `normalizes openai gpt effort suffix to priced base`() {
        let model = CursorModelNormalizer.normalize("gpt-5.5-medium")
        #expect(model.displayName == "GPT-5.5")
        #expect(model.provider == .openai)
        #expect(model.effort == "medium")
        #expect(model.pricingKey == "gpt-5.5")
        #expect(UsageFormatter.cursorCompactModelLabel(model) == "GPT-5.5 · medium")
    }

    @Test
    func `normalizes openai gpt mini effort suffix to priced base`() {
        let model = CursorModelNormalizer.normalize("gpt-5.4-mini-high")
        #expect(model.displayName == "GPT-5.4 Mini")
        #expect(model.provider == .openai)
        #expect(model.effort == "high")
        #expect(model.pricingKey == "gpt-5.4-mini")
        #expect(UsageFormatter.cursorCompactModelLabel(model) == "GPT-5.4 Mini · high")
    }

    @Test
    func `normalizes openai gpt extra high effort suffix to priced base`() {
        let model = CursorModelNormalizer.normalize("gpt-5.5-extra-high")
        #expect(model.displayName == "GPT-5.5")
        #expect(model.provider == .openai)
        #expect(model.effort == "extra-high")
        #expect(model.pricingKey == "gpt-5.5")
        #expect(UsageFormatter.cursorCompactModelLabel(model) == "GPT-5.5 · extra-high")
    }

    @Test
    func `normalizes openai prefixed gpt mini extra high effort suffix to priced base`() {
        let model = CursorModelNormalizer.normalize("openai:gpt-5.4-mini-extra-high")
        #expect(model.displayName == "GPT-5.4 Mini")
        #expect(model.provider == .openai)
        #expect(model.effort == "extra-high")
        #expect(model.pricingKey == "gpt-5.4-mini")
        #expect(UsageFormatter.cursorCompactModelLabel(model) == "GPT-5.4 Mini · extra-high")
    }

    @Test
    func `normalizes openai prefixed and mixed case gpt aliases`() {
        let colon = CursorModelNormalizer.normalize("OpenAI:GPT-5.5-HIGH")
        let slash = CursorModelNormalizer.normalize("openai/gpt-5.4-mini-high")
        #expect(colon.provider == .openai)
        #expect(colon.pricingKey == "gpt-5.5")
        #expect(slash.provider == .openai)
        #expect(slash.pricingKey == "gpt-5.4-mini")
    }

    @Test
    func `normalizes openai gpt with repeated effort suffixes`() {
        let model = CursorModelNormalizer.normalize("gpt-5.4-mini-high-medium")
        #expect(model.provider == .openai)
        #expect(model.effort == "high")
        #expect(model.pricingKey == "gpt-5.4-mini")
    }

    @Test
    func `normalizes openai gpt with extra high followed by single effort suffix`() {
        let model = CursorModelNormalizer.normalize("gpt-5.4-mini-extra-high-medium")
        #expect(model.displayName == "GPT-5.4 Mini")
        #expect(model.provider == .openai)
        #expect(model.effort == "extra-high")
        #expect(model.pricingKey == "gpt-5.4-mini")
        #expect(UsageFormatter.cursorCompactModelLabel(model) == "GPT-5.4 Mini · extra-high")
    }

    @Test
    func `unsupported openai gpt variant stays unpriced`() {
        let model = CursorModelNormalizer.normalize("gpt-9.9-medium")
        #expect(model.provider == .openai)
        #expect(model.pricingKey == nil)
    }

    @Test
    func `unsupported openai gpt variant with priced base stays unpriced`() {
        let model = CursorModelNormalizer.normalize("gpt-5.5-ultra")
        #expect(model.provider == .openai)
        #expect(model.pricingKey == nil)
    }

    @Test
    func `supported openai gpt variant exact key stays priced`() {
        let model = CursorModelNormalizer.normalize("gpt-5.4-pro")
        #expect(model.provider == .openai)
        #expect(model.pricingKey == "gpt-5.4-pro")
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
        let fable = CursorModelNormalizer.normalize("claude-fable-5-thinking-xhigh")
        #expect(xhigh.pricingKey == "claude-opus-4-8")
        #expect(max.pricingKey == "claude-opus-4-8")
        #expect(plain.pricingKey == "claude-opus-4-8")
        #expect(fable.pricingKey == "claude-fable-5")
    }
}
