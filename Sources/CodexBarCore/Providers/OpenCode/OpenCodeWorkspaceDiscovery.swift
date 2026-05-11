import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct OpenCodeDiscoveredWorkspace: Sendable, Equatable {
    public let workspaceID: String
    public let workspaceLabel: String
    public let ownerLabel: String?

    public init(workspaceID: String, workspaceLabel: String, ownerLabel: String?) {
        self.workspaceID = workspaceID
        self.workspaceLabel = workspaceLabel
        self.ownerLabel = ownerLabel
    }
}

public enum OpenCodeWorkspaceDiscovery {
    private static let log = CodexBarLog.logger(LogCategories.opencodeUsage)
    private static let baseURL = URL(string: "https://opencode.ai")!
    private static let serverURL = URL(string: "https://opencode.ai/_server")!
    private static let workspacesServerID = "def39973159c7f0483d8793a822b8dbb10d067e12c65455fcb4608459ba0234f"
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36"

    private struct ServerRequest {
        let serverID: String
        let args: [Any]?
        let method: String
        let referer: URL
    }

    public static func discoverWorkspaces(
        cookieHeader: String,
        timeout: TimeInterval,
        session: URLSession = .shared) async throws -> [OpenCodeDiscoveredWorkspace]
    {
        guard let requestCookieHeader = OpenCodeWebCookieSupport.requestCookieHeader(from: cookieHeader) else {
            throw OpenCodeUsageError.invalidCredentials
        }

        let initial = try await self.fetchServerText(
            request: ServerRequest(
                serverID: self.workspacesServerID,
                args: nil,
                method: "GET",
                referer: self.baseURL),
            cookieHeader: requestCookieHeader,
            timeout: timeout,
            session: session)
        if self.looksSignedOut(text: initial) {
            throw OpenCodeUsageError.invalidCredentials
        }

        let firstPass = self.parseWorkspaces(text: initial)
        if !firstPass.isEmpty {
            return firstPass
        }

        self.log.error("OpenCode workspace discovery returned no workspaces after GET; retrying with POST.")
        let fallback = try await self.fetchServerText(
            request: ServerRequest(
                serverID: self.workspacesServerID,
                args: [],
                method: "POST",
                referer: self.baseURL),
            cookieHeader: requestCookieHeader,
            timeout: timeout,
            session: session)
        if self.looksSignedOut(text: fallback) {
            throw OpenCodeUsageError.invalidCredentials
        }

        let secondPass = self.parseWorkspaces(text: fallback)
        guard !secondPass.isEmpty else {
            self.log.error("OpenCode workspace discovery returned no workspaces.")
            throw OpenCodeUsageError.parseFailed("Missing workspace id.")
        }
        return secondPass
    }

    static func fetchWorkspaceID(
        cookieHeader: String,
        timeout: TimeInterval,
        session: URLSession) async throws -> String
    {
        guard let workspaceID = try await self.discoverWorkspaces(
            cookieHeader: cookieHeader,
            timeout: timeout,
            session: session).first?.workspaceID
        else {
            throw OpenCodeUsageError.parseFailed("Missing workspace id.")
        }
        return workspaceID
    }

    public static func normalizeWorkspaceID(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("wrk_"), trimmed.count > 4 {
            return trimmed
        }
        if let url = URL(string: trimmed) {
            let parts = url.pathComponents
            if let index = parts.firstIndex(of: "workspace"),
               parts.count > index + 1
            {
                let candidate = parts[index + 1]
                if candidate.hasPrefix("wrk_"), candidate.count > 4 {
                    return candidate
                }
            }
        }
        if let match = trimmed.range(of: #"wrk_[A-Za-z0-9]+"#, options: .regularExpression) {
            return String(trimmed[match])
        }
        return nil
    }

    static func parseWorkspaces(text: String) -> [OpenCodeDiscoveredWorkspace] {
        var results: [OpenCodeDiscoveredWorkspace] = []
        var seenIDs: Set<String> = []

        self.parseSerovalWorkspaces(text: text, out: &results, seenIDs: &seenIDs)
        self.parseJSONWorkspaces(text: text, out: &results, seenIDs: &seenIDs)

        return results
    }

    private static func parseSerovalWorkspaces(
        text: String,
        out: inout [OpenCodeDiscoveredWorkspace],
        seenIDs: inout Set<String>)
    {
        let pattern =
            #"id\s*:\s*\"(wrk_[^\"]+)\"\s*,\s*name\s*:\s*\"([^\"]+)\"(?:\s*,\s*slug\s*:\s*[^,}\]]+)?"# +
            #"(?:\s*,\s*owner\s*:\s*\{[^}]*?name\s*:\s*\"([^\"]+)\"[^}]*\})?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return
        }
        let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in regex.matches(in: text, options: [], range: nsrange) {
            guard let idRange = Range(match.range(at: 1), in: text) else { continue }
            let workspaceID = String(text[idRange])
            let labelRange = Range(match.range(at: 2), in: text)
            let ownerRange = Range(match.range(at: 3), in: text)
            self.appendWorkspace(
                workspaceID: workspaceID,
                workspaceLabel: labelRange.map { String(text[$0]) },
                ownerLabel: ownerRange.map { String(text[$0]) },
                out: &out,
                seenIDs: &seenIDs)
        }
    }

    private static func parseJSONWorkspaces(
        text: String,
        out: inout [OpenCodeDiscoveredWorkspace],
        seenIDs: inout Set<String>)
    {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [])
        else {
            return
        }
        self.collectWorkspaces(object: object, out: &out, seenIDs: &seenIDs)
    }

    private static func collectWorkspaces(
        object: Any,
        out: inout [OpenCodeDiscoveredWorkspace],
        seenIDs: inout Set<String>)
    {
        if let dict = object as? [String: Any] {
            if let workspaceID = self.normalizeWorkspaceID(dict["id"] as? String) {
                let label = self.firstNonEmptyString(in: dict, keys: [
                    "name",
                    "workspaceName",
                    "workspaceLabel",
                    "label",
                    "title",
                    "slug",
                ])
                let ownerLabel = self.ownerLabel(from: dict)
                self.appendWorkspace(
                    workspaceID: workspaceID,
                    workspaceLabel: label,
                    ownerLabel: ownerLabel,
                    out: &out,
                    seenIDs: &seenIDs)
            }
            for value in dict.values {
                self.collectWorkspaces(object: value, out: &out, seenIDs: &seenIDs)
            }
            return
        }
        if let array = object as? [Any] {
            for value in array {
                self.collectWorkspaces(object: value, out: &out, seenIDs: &seenIDs)
            }
        }
    }

    private static func ownerLabel(from dict: [String: Any]) -> String? {
        if let owner = dict["owner"] as? [String: Any] {
            return self.firstNonEmptyString(in: owner, keys: ["name", "label", "title", "slug"])
        }
        return self.firstNonEmptyString(in: dict, keys: ["ownerName", "ownerLabel"])
    }

    private static func firstNonEmptyString(in dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key] as? String,
               let normalized = self.normalizeLabel(value)
            {
                return normalized
            }
        }
        return nil
    }

    private static func appendWorkspace(
        workspaceID: String,
        workspaceLabel rawWorkspaceLabel: String?,
        ownerLabel rawOwnerLabel: String?,
        out: inout [OpenCodeDiscoveredWorkspace],
        seenIDs: inout Set<String>)
    {
        guard !seenIDs.contains(workspaceID) else { return }
        seenIDs.insert(workspaceID)
        out.append(OpenCodeDiscoveredWorkspace(
            workspaceID: workspaceID,
            workspaceLabel: self.normalizeLabel(rawWorkspaceLabel) ?? workspaceID,
            ownerLabel: self.normalizeLabel(rawOwnerLabel)))
    }

    private static func normalizeLabel(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func fetchServerText(
        request serverRequest: ServerRequest,
        cookieHeader: String,
        timeout: TimeInterval,
        session: URLSession) async throws -> String
    {
        let url = self.serverRequestURL(
            serverID: serverRequest.serverID,
            args: serverRequest.args,
            method: serverRequest.method)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = serverRequest.method
        urlRequest.timeoutInterval = timeout
        urlRequest.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        urlRequest.setValue(serverRequest.serverID, forHTTPHeaderField: "X-Server-Id")
        urlRequest.setValue("server-fn:\(UUID().uuidString)", forHTTPHeaderField: "X-Server-Instance")
        urlRequest.setValue(self.userAgent, forHTTPHeaderField: "User-Agent")
        urlRequest.setValue(self.baseURL.absoluteString, forHTTPHeaderField: "Origin")
        urlRequest.setValue(serverRequest.referer.absoluteString, forHTTPHeaderField: "Referer")
        urlRequest.setValue("text/javascript, application/json;q=0.9, */*;q=0.8", forHTTPHeaderField: "Accept")
        if serverRequest.method.uppercased() != "GET",
           let args = serverRequest.args
        {
            let body = try JSONSerialization.data(withJSONObject: args, options: [])
            urlRequest.httpBody = body
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenCodeUsageError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown"
            self.log.error("OpenCode returned \(httpResponse.statusCode) (type=\(contentType) length=\(data.count))")
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

    private static func serverRequestURL(serverID: String, args: [Any]?, method: String) -> URL {
        guard method.uppercased() == "GET" else {
            return self.serverURL
        }

        var components = URLComponents(url: self.serverURL, resolvingAgainstBaseURL: false)
        var queryItems = [URLQueryItem(name: "id", value: serverID)]
        if let args, !args.isEmpty,
           let data = try? JSONSerialization.data(withJSONObject: args, options: []),
           let encodedArgs = String(data: data, encoding: .utf8)
        {
            queryItems.append(URLQueryItem(name: "args", value: encodedArgs))
        }
        components?.queryItems = queryItems
        return components?.url ?? self.serverURL
    }
}
