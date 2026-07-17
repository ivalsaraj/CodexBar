import Foundation

/// Per-request token breakdown preserved from a Cursor usage event.
///
/// `confidence` records how complete the decoded token parts are so downstream cost
/// estimation can decide whether an exact, partial, or unavailable estimate is honest.
public struct CursorRecentRequestTokenBreakdown: Codable, Equatable, Sendable {
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let cacheReadTokens: Int?
    public let cacheWriteTokens: Int?
    public let totalTokens: Int
    public let confidence: Confidence

    public enum Confidence: String, Codable, Equatable, Sendable {
        /// Every pricing-relevant part field (input/output/cache read/cache write) is present.
        case exactBreakdown
        /// At least one part field is present, but one or more pricing-relevant parts are missing.
        case partialBreakdown
        /// Only an explicit `totalTokens` value is present; no part fields exist.
        case totalOnly
        /// Token usage exists for the event but no field carried a value.
        case empty
    }

    public init(
        inputTokens: Int?,
        outputTokens: Int?,
        cacheReadTokens: Int?,
        cacheWriteTokens: Int?,
        totalTokens: Int,
        confidence: Confidence)
    {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.totalTokens = totalTokens
        self.confidence = confidence
    }
}

public struct CursorRecentRequest: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let model: String
    public let tokens: Int
    public let requests: Int
    public let requestCost: Double?
    public let tokenBreakdown: CursorRecentRequestTokenBreakdown?

    public init(
        timestamp: Date,
        model: String,
        tokens: Int,
        requests: Int,
        requestCost: Double? = nil,
        tokenBreakdown: CursorRecentRequestTokenBreakdown? = nil)
    {
        self.timestamp = timestamp
        self.model = model
        self.tokens = tokens
        self.requests = requests
        self.requestCost = requestCost
        self.tokenBreakdown = tokenBreakdown
    }
}

public struct CursorRecentRequestRange: Codable, Equatable, Sendable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
}
