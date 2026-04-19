import CodexBarCore
import Foundation
import Testing

struct CodexUsageFetcherFallbackTests {
    @Test
    func `CLI usage recovers from RPC decode mismatch body payload`() {
        let snapshot = UsageFetcher._recoverCodexRPCUsageFromErrorForTesting(
            Self.decodeMismatchBodyMessage)

        #expect(snapshot?.primary?.usedPercent == 4)
        #expect(snapshot?.primary?.windowMinutes == 300)
        #expect(snapshot?.secondary?.usedPercent == 19)
        #expect(snapshot?.secondary?.windowMinutes == 10080)
        #expect(snapshot?.accountEmail(for: UsageProvider.codex) == "prolite-test@example.com")
        #expect(snapshot?.loginMethod(for: UsageProvider.codex) == "prolite")
    }

    @Test
    func `CLI credits recover from RPC decode mismatch body payload`() {
        let credits = UsageFetcher._recoverCodexRPCCreditsFromErrorForTesting(Self.decodeMismatchBodyMessage)

        #expect(credits?.remaining == 0)
    }

    @Test
    func `CLI usage does not partially recover malformed RPC body without session lane`() {
        let snapshot = UsageFetcher._recoverCodexRPCUsageFromErrorForTesting(
            Self.partialDecodeBodyMessage)

        #expect(snapshot == nil)
    }

    private static let decodeMismatchBodyMessage = """
    failed to fetch codex rate limits: Decode error for https://chatgpt.com/backend-api/wham/usage:
    unknown variant `prolite`, expected one of `guest`, `free`, `go`, `plus`, `pro`;
    content-type=application/json; body={
      "user_id": "user-TEST",
      "account_id": "account-TEST",
      "email": "prolite-test@example.com",
      "plan_type": "prolite",
      "rate_limit": {
        "allowed": true,
        "limit_reached": false,
        "primary_window": {
          "used_percent": 4,
          "limit_window_seconds": 18000,
          "reset_after_seconds": 8657,
          "reset_at": 1776216359
        },
        "secondary_window": {
          "used_percent": 19,
          "limit_window_seconds": 604800,
          "reset_after_seconds": 187681,
          "reset_at": 1776395384
        }
      },
      "credits": {
        "has_credits": false,
        "unlimited": false,
        "overage_limit_reached": false,
        "balance": "0E-10"
      }
    }
    """

    private static let partialDecodeBodyMessage = """
    failed to fetch codex rate limits: Decode error for https://chatgpt.com/backend-api/wham/usage:
    unknown variant `prolite`, expected one of `guest`, `free`, `go`, `plus`, `pro`;
    content-type=application/json; body={
      "email": "prolite-test@example.com",
      "plan_type": "prolite",
      "rate_limit": {
        "allowed": true,
        "limit_reached": false,
        "primary_window": {
          "used_percent": "oops",
          "limit_window_seconds": 18000,
          "reset_at": 1776216359
        },
        "secondary_window": {
          "used_percent": 19,
          "limit_window_seconds": 604800,
          "reset_after_seconds": 187681,
          "reset_at": 1776395384
        }
      }
    }
    """
}
