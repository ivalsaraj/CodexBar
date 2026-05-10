import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum OpenCodeUsageError: LocalizedError {
    case invalidCredentials
    case networkError(String)
    case apiError(String)
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            "OpenCode session cookie is invalid or expired."
        case let .networkError(message):
            "OpenCode network error: \(message)"
        case let .apiError(message):
            "OpenCode API error: \(message)"
        case let .parseFailed(message):
            "OpenCode parse error: \(message)"
        }
    }
}

public struct OpenCodeUsageFetcher: Sendable {
    private static let log = CodexBarLog.logger(LogCategories.opencodeUsage)
    private static let baseURL = URL(string: "https://opencode.ai")!
    private static let rollingWindowSeconds = 5 * 60 * 60
    private static let weeklyWindowSeconds = 7 * 24 * 60 * 60

    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36"

    private struct UsageRecord {
        let createdAt: Date
        let cost: Double
    }

    public static func fetchUsage(
        cookieHeader: String,
        timeout: TimeInterval,
        now: Date = Date(),
        workspaceIDOverride: String? = nil,
        session: URLSession = .shared) async throws -> OpenCodeUsageSnapshot
    {
        guard let requestCookieHeader = OpenCodeWebCookieSupport.requestCookieHeader(from: cookieHeader) else {
            throw OpenCodeUsageError.invalidCredentials
        }
        let workspaceID: String = if let override = OpenCodeWorkspaceDiscovery
            .normalizeWorkspaceID(workspaceIDOverride)
        {
            override
        } else {
            try await OpenCodeWorkspaceDiscovery.fetchWorkspaceID(
                cookieHeader: requestCookieHeader,
                timeout: timeout,
                session: session)
        }

        if let goSnapshot = try await self.fetchGoSnapshot(
            workspaceID: workspaceID,
            cookieHeader: requestCookieHeader,
            timeout: timeout,
            now: now,
            session: session)
        {
            return goSnapshot
        }

        let usagePage = try await self.fetchUsagePage(
            workspaceID: workspaceID,
            cookieHeader: requestCookieHeader,
            timeout: timeout,
            session: session)
        let billingPage = try await self.fetchBillingPage(
            workspaceID: workspaceID,
            cookieHeader: requestCookieHeader,
            timeout: timeout,
            session: session)

        return try self.parseUsage(
            usagePageText: usagePage,
            billingPageText: billingPage,
            now: now)
    }

    private static func fetchGoSnapshot(
        workspaceID: String,
        cookieHeader: String,
        timeout: TimeInterval,
        now: Date,
        session: URLSession) async throws -> OpenCodeUsageSnapshot?
    {
        let url = URL(string: "https://opencode.ai/workspace/\(workspaceID)/go") ?? self.baseURL
        do {
            let text = try await self.fetchPageText(
                url: url,
                cookieHeader: cookieHeader,
                timeout: timeout,
                session: session)
            if self.looksSignedOut(text: text) {
                throw OpenCodeUsageError.invalidCredentials
            }
            do {
                let snapshot = try OpenCodeGoUsageFetcher.parseSubscription(text: text, now: now)
                return self.snapshot(from: snapshot)
            } catch let error as OpenCodeGoUsageError {
                switch error {
                case let .parseFailed(message) where message.contains("Missing usage fields"):
                    Self.log.info("OpenCode Go dashboard missing usage fields; falling back to usage history parser.")
                    return nil
                default:
                    throw self.mapGoError(error)
                }
            }
        } catch let error as OpenCodeUsageError {
            switch error {
            case .invalidCredentials:
                Self.log.info("OpenCode Go dashboard rejected this workspace; falling back to usage history parser.")
                return nil
            case let .apiError(message) where message.contains("HTTP 404"):
                Self.log.info("OpenCode Go dashboard returned 404; falling back to usage history parser.")
                return nil
            default:
                throw error
            }
        }
    }

    private static func fetchUsagePage(
        workspaceID: String,
        cookieHeader: String,
        timeout: TimeInterval,
        session: URLSession) async throws -> String
    {
        let url = URL(string: "https://opencode.ai/workspace/\(workspaceID)/usage") ?? self.baseURL
        let text = try await self.fetchPageText(
            url: url,
            cookieHeader: cookieHeader,
            timeout: timeout,
            session: session)
        if self.looksSignedOut(text: text) {
            throw OpenCodeUsageError.invalidCredentials
        }
        guard self.containsLoader(named: "usage.list", in: text) || self.looksLikeEmptyUsagePage(text) else {
            Self.log.error("OpenCode usage page missing usage.list loader.")
            throw OpenCodeUsageError.parseFailed("Missing usage records.")
        }
        return text
    }

    private static func fetchBillingPage(
        workspaceID: String,
        cookieHeader: String,
        timeout: TimeInterval,
        session: URLSession) async throws -> String
    {
        let url = URL(string: "https://opencode.ai/workspace/\(workspaceID)/billing") ?? self.baseURL
        let text = try await self.fetchPageText(
            url: url,
            cookieHeader: cookieHeader,
            timeout: timeout,
            session: session)
        if self.looksSignedOut(text: text) {
            throw OpenCodeUsageError.invalidCredentials
        }
        guard self.containsLoader(named: "billing.get", in: text) else {
            Self.log.error("OpenCode billing page missing billing.get loader.")
            throw OpenCodeUsageError.parseFailed("Missing billing balance.")
        }
        return text
    }

    static func parseUsage(
        usagePageText: String,
        billingPageText: String,
        now: Date) throws -> OpenCodeUsageSnapshot
    {
        let records = try self.parseUsageRecords(from: usagePageText)
        let balance = self.parseNumericField(named: "balance", text: billingPageText)
        let monthlyLimit = self.parseNumericField(named: "monthlyLimit", text: billingPageText)

        let listedCostTotal = records.reduce(0) { $0 + $1.cost }
        let budget: Double? = if let monthlyLimit, monthlyLimit > 0 {
            monthlyLimit
        } else if let balance, balance >= 0 {
            balance + listedCostTotal
        } else {
            nil
        }

        guard let budget, budget > 0 else {
            Self.log.error("OpenCode billing page missing usable balance or monthly limit.")
            throw OpenCodeUsageError.parseFailed("Missing billing balance.")
        }

        let rollingWindow = self.trailingWindow(
            records: records,
            budget: budget,
            duration: self.rollingWindowSeconds,
            now: now)
        let weeklyWindow = self.trailingWindow(
            records: records,
            budget: budget,
            duration: self.weeklyWindowSeconds,
            now: now)

        return OpenCodeUsageSnapshot(
            hasMonthlyUsage: false,
            rollingUsagePercent: rollingWindow.percent,
            weeklyUsagePercent: weeklyWindow.percent,
            monthlyUsagePercent: 0,
            rollingResetInSec: rollingWindow.resetInSec,
            weeklyResetInSec: weeklyWindow.resetInSec,
            monthlyResetInSec: 0,
            updatedAt: now)
    }

    private static func snapshot(from goSnapshot: OpenCodeGoUsageSnapshot) -> OpenCodeUsageSnapshot {
        OpenCodeUsageSnapshot(
            hasMonthlyUsage: goSnapshot.hasMonthlyUsage,
            rollingUsagePercent: goSnapshot.rollingUsagePercent,
            weeklyUsagePercent: goSnapshot.weeklyUsagePercent,
            monthlyUsagePercent: goSnapshot.monthlyUsagePercent,
            rollingResetInSec: goSnapshot.rollingResetInSec,
            weeklyResetInSec: goSnapshot.weeklyResetInSec,
            monthlyResetInSec: goSnapshot.monthlyResetInSec,
            updatedAt: goSnapshot.updatedAt)
    }

    private static func mapGoError(_ error: OpenCodeGoUsageError) -> OpenCodeUsageError {
        switch error {
        case .invalidCredentials:
            .invalidCredentials
        case let .networkError(message):
            .networkError(message)
        case let .apiError(message):
            .apiError(message)
        case let .parseFailed(message):
            .parseFailed(message)
        }
    }

    private static func parseUsageRecords(from text: String) throws -> [UsageRecord] {
        let pattern =
            #"timeCreated:\$R\[\d+\]=new Date\("([^"]+)"\),"# +
            #"timeUpdated:\$R\[\d+\]=new Date\("[^"]+"\),"# +
            #"timeDeleted:null,.*?cost:([0-9]+),keyID:"[^"]*","#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            throw OpenCodeUsageError.parseFailed("Invalid usage record matcher.")
        }

        let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)
        let formatter = self.makeISO8601Formatter()
        return regex.matches(in: text, options: [], range: nsrange).compactMap { match in
            guard let dateRange = Range(match.range(at: 1), in: text),
                  let costRange = Range(match.range(at: 2), in: text),
                  let createdAt = formatter.date(from: String(text[dateRange])),
                  let cost = Double(String(text[costRange]))
            else {
                return nil
            }
            return UsageRecord(createdAt: createdAt, cost: cost)
        }
    }

    private static func looksLikeEmptyUsagePage(_ text: String) -> Bool {
        let markers = [
            "No usage data available for the selected period.",
            "Make your first API call to get started.",
        ]
        return markers.contains { text.contains($0) }
    }

    private static func containsLoader(named loaderName: String, in text: String) -> Bool {
        let escapedName = NSRegularExpression.escapedPattern(for: loaderName)
        let pattern = #"\#(escapedName)\s*\["#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return false
        }
        let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: nsrange) != nil
    }

    private static func parseNumericField(named field: String, text: String) -> Double? {
        let escapedField = NSRegularExpression.escapedPattern(for: field)
        let pattern = #"\#(escapedField)\s*:\s*(null|[0-9]+(?:\.[0-9]+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: nsrange),
              let range = Range(match.range(at: 1), in: text)
        else {
            return nil
        }

        let value = String(text[range])
        guard value != "null" else { return nil }
        return Double(value)
    }

    private static func trailingWindow(
        records: [UsageRecord],
        budget: Double,
        duration: Int,
        now: Date) -> (percent: Double, resetInSec: Int)
    {
        let lowerBound = now.addingTimeInterval(TimeInterval(-duration))
        let filtered = records.filter { record in
            record.createdAt >= lowerBound && record.createdAt <= now
        }

        let spent = filtered.reduce(0) { $0 + $1.cost }
        let percent = if budget > 0 {
            max(0.0, min(100.0, (spent / budget) * 100.0))
        } else {
            0.0
        }

        guard let earliestRecord = filtered.map(\.createdAt).min() else {
            return (percent, 0)
        }

        let resetAt = earliestRecord.addingTimeInterval(TimeInterval(duration))
        let resetInSec = max(0, Int(resetAt.timeIntervalSince(now)))
        return (percent, resetInSec)
    }

    private static func fetchPageText(
        url: URL,
        cookieHeader: String,
        timeout: TimeInterval,
        session: URLSession) async throws -> String
    {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue(self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(
            "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            forHTTPHeaderField: "Accept")
        request.setValue(self.baseURL.absoluteString, forHTTPHeaderField: "Origin")
        request.setValue(url.absoluteString, forHTTPHeaderField: "Referer")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenCodeUsageError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown"
            Self.log
                .error("OpenCode page returned \(httpResponse.statusCode) (type=\(contentType) length=\(data.count))")
            if self.looksSignedOut(text: bodyText) {
                throw OpenCodeUsageError.invalidCredentials
            }
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw OpenCodeUsageError.invalidCredentials
            }
            if let message = self.extractServerErrorMessage(from: bodyText) {
                throw OpenCodeUsageError.apiError("HTTP \(httpResponse.statusCode): \(message)")
            }
            throw OpenCodeUsageError.apiError("HTTP \(httpResponse.statusCode)")
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw OpenCodeUsageError.parseFailed("Response was not UTF-8.")
        }
        return text
    }

    private static func looksSignedOut(text: String) -> Bool {
        let lower = text.lowercased()
        if lower.contains("login") ||
            lower.contains("sign in") ||
            lower.contains("auth/authorize") ||
            lower.contains("not associated with an account") ||
            lower.contains("actor of type \"public\"")
        {
            return true
        }
        return false
    }

    private static func extractServerErrorMessage(from text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [])
        else {
            if let match = text.range(of: #"(?i)<title>([^<]+)</title>"#, options: .regularExpression) {
                return String(text[match].dropFirst(7).dropLast(8)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return nil
        }

        guard let dict = object as? [String: Any] else { return nil }

        if let message = dict["message"] as? String, !message.isEmpty {
            return message
        }
        if let error = dict["error"] as? String, !error.isEmpty {
            return error
        }
        if let detail = dict["detail"] as? String, !detail.isEmpty {
            return detail
        }
        return nil
    }

    private static func makeISO8601Formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}
