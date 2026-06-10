import CodexBarCore
import Foundation
import Testing

struct OpenCodeUsageParserTests {
    private struct UsageRecord {
        let timeCreated: String
        let cost: Int
    }

    private struct UsageWindow {
        let percent: Double
        let resetInSec: Int
    }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OpenCodeParserStubURLProtocol.self]
        return URLSession(configuration: config)
    }

    @Test
    func `derives trailing usage windows from usage and billing pages`() async throws {
        defer {
            OpenCodeParserStubURLProtocol.handler = nil
        }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let formatter = Self.makeFormatter()
        OpenCodeParserStubURLProtocol.handler = { request in
            guard let url = request.url else { throw URLError(.badURL) }

            switch url.path {
            case "/workspace/wrk_TEST123/usage":
                return Self.makeResponse(
                    url: url,
                    body: Self.usagePageHTML(
                        workspaceID: "wrk_TEST123",
                        records: [
                            UsageRecord(
                                timeCreated: formatter.string(from: now.addingTimeInterval(-(60 * 60))),
                                cost: 2_000_000),
                            UsageRecord(
                                timeCreated: formatter.string(from: now.addingTimeInterval(-(4 * 60 * 60))),
                                cost: 2_000_000),
                            UsageRecord(
                                timeCreated: formatter.string(from: now.addingTimeInterval(-(3 * 24 * 60 * 60))),
                                cost: 6_000_000),
                            UsageRecord(
                                timeCreated: formatter.string(from: now.addingTimeInterval(-(9 * 24 * 60 * 60))),
                                cost: 10_000_000),
                        ]),
                    statusCode: 200,
                    contentType: "text/html")
            case "/workspace/wrk_TEST123/billing":
                return Self.makeResponse(
                    url: url,
                    body: Self.billingPageHTML(
                        workspaceID: "wrk_TEST123",
                        balance: 80_000_000,
                        monthlyLimit: nil),
                    statusCode: 200,
                    contentType: "text/html")
            default:
                throw URLError(.badServerResponse)
            }
        }

        let snapshot = try await OpenCodeUsageFetcher.fetchUsage(
            cookieHeader: "auth=test",
            timeout: 2,
            now: now,
            workspaceIDOverride: "wrk_TEST123",
            session: self.makeSession())

        let expectedWeeklyReset = 4 * 24 * 60 * 60
        #expect(snapshot.rollingUsagePercent == 4)
        #expect(snapshot.weeklyUsagePercent == 10)
        #expect(snapshot.rollingResetInSec == 3600)
        #expect(snapshot.weeklyResetInSec == expectedWeeklyReset)
    }

    @Test
    func `go dashboard metrics take precedence and expose monthly usage`() async throws {
        defer {
            OpenCodeParserStubURLProtocol.handler = nil
        }

        var paths: [String] = []
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        OpenCodeParserStubURLProtocol.handler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            paths.append(url.path)

            switch url.path {
            case "/workspace/wrk_GO123/go":
                return Self.makeResponse(
                    url: url,
                    body: Self.goUsagePageHTML(
                        workspaceID: "wrk_GO123",
                        rolling: UsageWindow(percent: 9, resetInSec: 5655),
                        weekly: UsageWindow(percent: 21, resetInSec: 214_596),
                        monthly: UsageWindow(percent: 10, resetInSec: 2_552_819)),
                    statusCode: 200,
                    contentType: "text/html")
            default:
                Issue.record("Unexpected path: \(url.path)")
                return Self.makeResponse(url: url, body: "unexpected", statusCode: 404, contentType: "text/plain")
            }
        }

        let snapshot = try await OpenCodeUsageFetcher.fetchUsage(
            cookieHeader: "auth=test",
            timeout: 2,
            now: now,
            workspaceIDOverride: "wrk_GO123",
            session: self.makeSession())
        let usage = snapshot.toUsageSnapshot()

        #expect(snapshot.rollingUsagePercent == 9)
        #expect(snapshot.weeklyUsagePercent == 21)
        #expect(usage.tertiary?.usedPercent == 10)
        #expect(paths == ["/workspace/wrk_GO123/go"])
    }

    @Test
    func `monthly limit wins over balance when both exist`() async throws {
        defer {
            OpenCodeParserStubURLProtocol.handler = nil
        }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let formatter = Self.makeFormatter()
        OpenCodeParserStubURLProtocol.handler = { request in
            guard let url = request.url else { throw URLError(.badURL) }

            switch url.path {
            case "/workspace/wrk_LIMIT123/usage":
                return Self.makeResponse(
                    url: url,
                    body: Self.usagePageHTML(
                        workspaceID: "wrk_LIMIT123",
                        records: [
                            UsageRecord(
                                timeCreated: formatter.string(from: now.addingTimeInterval(-(30 * 60))),
                                cost: 2_500_000),
                        ]),
                    statusCode: 200,
                    contentType: "text/html")
            case "/workspace/wrk_LIMIT123/billing":
                return Self.makeResponse(
                    url: url,
                    body: Self.billingPageHTML(
                        workspaceID: "wrk_LIMIT123",
                        balance: 99_000_000,
                        monthlyLimit: 10_000_000),
                    statusCode: 200,
                    contentType: "text/html")
            default:
                throw URLError(.badServerResponse)
            }
        }

        let snapshot = try await OpenCodeUsageFetcher.fetchUsage(
            cookieHeader: "auth=test",
            timeout: 2,
            now: now,
            workspaceIDOverride: "wrk_LIMIT123",
            session: self.makeSession())

        #expect(snapshot.rollingUsagePercent == 25)
        #expect(snapshot.weeklyUsagePercent == 25)
    }

    @Test
    func `parse usage throws when billing budget missing`() async throws {
        defer {
            OpenCodeParserStubURLProtocol.handler = nil
        }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let formatter = Self.makeFormatter()
        OpenCodeParserStubURLProtocol.handler = { request in
            guard let url = request.url else { throw URLError(.badURL) }

            switch url.path {
            case "/workspace/wrk_FAIL123/usage":
                return Self.makeResponse(
                    url: url,
                    body: Self.usagePageHTML(
                        workspaceID: "wrk_FAIL123",
                        records: [
                            UsageRecord(
                                timeCreated: formatter.string(from: now.addingTimeInterval(-(30 * 60))),
                                cost: 1_000_000),
                        ]),
                    statusCode: 200,
                    contentType: "text/html")
            case "/workspace/wrk_FAIL123/billing":
                return Self.makeResponse(
                    url: url,
                    body: Self.billingPageHTML(
                        workspaceID: "wrk_FAIL123",
                        balance: nil,
                        monthlyLimit: nil),
                    statusCode: 200,
                    contentType: "text/html")
            default:
                throw URLError(.badServerResponse)
            }
        }

        await #expect(throws: OpenCodeUsageError.self) {
            _ = try await OpenCodeUsageFetcher.fetchUsage(
                cookieHeader: "auth=test",
                timeout: 2,
                now: now,
                workspaceIDOverride: "wrk_FAIL123",
                session: self.makeSession())
        }
    }

    private static func usagePageHTML(workspaceID: String, records: [UsageRecord]) -> String {
        let recordText = records.enumerated().map { index, record in
            self.usageRecordHTML(index: index, workspaceID: workspaceID, record: record)
        }.joined(separator: ",")

        return """
        <!DOCTYPE html>
        <html>
        <body>
        <script>
        window._$HY = window._$HY || { r: {} };
        self.$R = self.$R || [];
        _$HY.r["usage.list[\\"\(workspaceID)\\",0]"] = $R[22] = ($R[2] = r => (
            r.p = new Promise((s, f) => { r.s = s, r.f = f })
        ))($R[23] = { p: 0, s: 0, f: 0 });
        ($R[16] = (r, d) => { r.s(d), r.p.s = 1, r.p.v = d })($R[23], $R[26] = [\(recordText)]);
        </script>
        </body>
        </html>
        """
    }

    private static func billingPageHTML(workspaceID: String, balance: Int?, monthlyLimit: Int?) -> String {
        let balanceLiteral = balance.map(String.init) ?? "null"
        let limitLiteral = monthlyLimit.map(String.init) ?? "null"
        return """
        <!DOCTYPE html>
        <html>
        <body>
        <script>
        window._$HY = window._$HY || { r: {} };
        self.$R = self.$R || [];
        _$HY.r["billing.get[\\"\(workspaceID)\\"]"] = $R[15] = ($R[2] = r => (
            r.p = new Promise((s, f) => { r.s = s, r.f = f })
        ))($R[16] = { p: 0, s: 0, f: 0 });
        ($R[22] = (r, d) => { r.s(d), r.p.s = 1, r.p.v = d })(
            $R[16],
            $R[23] = {
                balance:\(balanceLiteral),
                monthlyLimit:\(limitLiteral),
                monthlyUsage:0,
                subscription:null,
                lite:$R[25] = {},
                liteSubscriptionID:"sub_redacted"
            }
        );
        </script>
        </body>
        </html>
        """
    }

    private static func goUsagePageHTML(
        workspaceID: String,
        rolling: UsageWindow,
        weekly: UsageWindow,
        monthly: UsageWindow?) -> String
    {
        let monthlyField: String? = if let monthly {
            #"monthlyUsage:{status:"ok",resetInSec:\#(monthly.resetInSec),usagePercent:\#(monthly.percent)}"#
        } else {
            nil
        }
        let usageFields = [
            #"rollingUsage:{status:"ok",resetInSec:\#(rolling.resetInSec),usagePercent:\#(rolling.percent)}"#,
            #"weeklyUsage:{status:"ok",resetInSec:\#(weekly.resetInSec),usagePercent:\#(weekly.percent)}"#,
            monthlyField,
        ].compactMap(\.self).joined(separator: ",")

        return """
        <!DOCTYPE html>
        <html>
        <body>
        <script>
        window._$HY = window._$HY || { r: {} };
        self.$R = self.$R || [];
        _$HY.r["lite.subscription.get[\\"\(workspaceID)\\"]"] = $R[17] = $R[2]($R[18] = { p: 0, s: 0, f: 0 });
        ($R[24] = (r, d) => { r.s(d), r.p.s = 1, r.p.v = d })(
            $R[18],
            $R[27] = { mine: !0, useBalance: !1, \(usageFields) }
        );
        </script>
        </body>
        </html>
        """
    }

    private static func usageRecordHTML(index: Int, workspaceID: String, record: UsageRecord) -> String {
        let base = index * 5
        return [
            #"{id:"usg_\#(index)",workspaceID:"\#(workspaceID)","#,
            #"timeCreated:$R[\#(base + 28)]=new Date("\#(record.timeCreated)"),"#,
            #"timeUpdated:$R[\#(base + 29)]=new Date("\#(record.timeCreated)"),timeDeleted:null,"#,
            #"model:"glm-5.1",provider:"deepinfra",inputTokens:1,outputTokens:1,reasoningTokens:null,"#,
            #"cacheReadTokens:0,cacheWrite5mTokens:null,cacheWrite1hTokens:null,cost:\#(record.cost),"#,
            #"keyID:"key_redacted",sessionID:"",enrichment:$R[\#(base + 30)]={plan:"lite"}}"#,
        ].joined()
    }

    private static func makeFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static func makeResponse(
        url: URL,
        body: String,
        statusCode: Int,
        contentType: String) -> (HTTPURLResponse, Data)
    {
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": contentType])!
        return (response, Data(body.utf8))
    }
}

final class OpenCodeParserStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "opencode.ai"
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            self.client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(self.request)
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)
        } catch {
            self.client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
