import CodexBarCore
import Foundation
import Testing

@Suite(.serialized)
struct OpenCodeUsageFetcherErrorTests {
    private struct UsageRecord {
        let timeCreated: String
        let cost: Int
    }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OpenCodeStubURLProtocol.self]
        return URLSession(configuration: config)
    }

    @Test
    func `extracts api error from uppercase HTML title`() async throws {
        defer {
            OpenCodeStubURLProtocol.handler = nil
        }

        OpenCodeStubURLProtocol.handler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            let body = "<html><head><TITLE>403 Forbidden</TITLE></head><body>denied</body></html>"
            return Self.makeResponse(url: url, body: body, statusCode: 500, contentType: "text/html")
        }

        do {
            _ = try await OpenCodeUsageFetcher.fetchUsage(
                cookieHeader: "auth=test",
                timeout: 2,
                workspaceIDOverride: "wrk_TEST123",
                session: self.makeSession())
            Issue.record("Expected OpenCodeUsageError.apiError")
        } catch let error as OpenCodeUsageError {
            switch error {
            case let .apiError(message):
                #expect(message.contains("HTTP 500"))
                #expect(message.contains("403 Forbidden"))
            default:
                Issue.record("Expected apiError, got: \(error)")
            }
        }
    }

    @Test
    func `extracts api error from detail field`() async throws {
        defer {
            OpenCodeStubURLProtocol.handler = nil
        }

        OpenCodeStubURLProtocol.handler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            let body = #"{"detail":"Workspace missing"}"#
            return Self.makeResponse(url: url, body: body, statusCode: 500, contentType: "application/json")
        }

        do {
            _ = try await OpenCodeUsageFetcher.fetchUsage(
                cookieHeader: "auth=test",
                timeout: 2,
                workspaceIDOverride: "wrk_TEST123",
                session: self.makeSession())
            Issue.record("Expected OpenCodeUsageError.apiError")
        } catch let error as OpenCodeUsageError {
            switch error {
            case let .apiError(message):
                #expect(message.contains("HTTP 500"))
                #expect(message.contains("Workspace missing"))
            default:
                Issue.record("Expected apiError, got: \(error)")
            }
        }
    }

    @Test
    func `go dashboard api errors do not fall back to legacy usage parsing`() async throws {
        defer {
            OpenCodeStubURLProtocol.handler = nil
        }

        var paths: [String] = []
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        OpenCodeStubURLProtocol.handler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            paths.append(url.path)

            switch url.path {
            case "/workspace/wrk_TEST123/go":
                return Self.makeResponse(
                    url: url,
                    body: #"{"detail":"Go dashboard unavailable"}"#,
                    statusCode: 500,
                    contentType: "application/json")
            case "/workspace/wrk_TEST123/usage":
                return Self.makeResponse(
                    url: url,
                    body: Self.usagePageHTML(
                        workspaceID: "wrk_TEST123",
                        records: [
                            UsageRecord(
                                timeCreated: formatter.string(from: now.addingTimeInterval(-(60 * 60))),
                                cost: 2_000_000),
                        ]),
                    statusCode: 200,
                    contentType: "text/html")
            case "/workspace/wrk_TEST123/billing":
                return Self.makeResponse(
                    url: url,
                    body: Self.billingPageHTML(workspaceID: "wrk_TEST123", balance: 80_000_000),
                    statusCode: 200,
                    contentType: "text/html")
            default:
                Issue.record("Unexpected path: \(url.path)")
                return Self.makeResponse(url: url, body: "unexpected", statusCode: 404, contentType: "text/plain")
            }
        }

        do {
            _ = try await OpenCodeUsageFetcher.fetchUsage(
                cookieHeader: "auth=test",
                timeout: 2,
                now: now,
                workspaceIDOverride: "wrk_TEST123",
                session: self.makeSession())
            Issue.record("Expected OpenCodeUsageError.apiError")
        } catch let error as OpenCodeUsageError {
            switch error {
            case let .apiError(message):
                #expect(message.contains("HTTP 500"))
                #expect(message.contains("Go dashboard unavailable"))
            default:
                Issue.record("Expected apiError, got: \(error)")
            }
        }

        #expect(paths == ["/workspace/wrk_TEST123/go"])
    }

    @Test
    func `go dashboard invalid credentials fallback to legacy usage parsing for plain opencode`() async throws {
        defer {
            OpenCodeStubURLProtocol.handler = nil
        }

        var paths: [String] = []
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        OpenCodeStubURLProtocol.handler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            paths.append(url.path)

            switch url.path {
            case "/workspace/wrk_TEST123/go":
                return Self.makeResponse(
                    url: url,
                    body: "<html><head><title>403 Forbidden</title></head><body>denied</body></html>",
                    statusCode: 403,
                    contentType: "text/html")
            case "/workspace/wrk_TEST123/usage":
                return Self.makeResponse(
                    url: url,
                    body: Self.usagePageHTML(
                        workspaceID: "wrk_TEST123",
                        records: [
                            UsageRecord(
                                timeCreated: formatter.string(from: now.addingTimeInterval(-(60 * 60))),
                                cost: 2_000_000),
                        ]),
                    statusCode: 200,
                    contentType: "text/html")
            case "/workspace/wrk_TEST123/billing":
                return Self.makeResponse(
                    url: url,
                    body: Self.billingPageHTML(workspaceID: "wrk_TEST123", balance: 8_000_000),
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
            workspaceIDOverride: "wrk_TEST123",
            session: self.makeSession())

        #expect(snapshot.rollingUsagePercent == 20)
        #expect(snapshot.weeklyUsagePercent == 20)
        #expect(snapshot.rollingResetInSec == 4 * 60 * 60)
        #expect(snapshot.weeklyResetInSec == 6 * 24 * 60 * 60 + 23 * 60 * 60)
        #expect(paths == [
            "/workspace/wrk_TEST123/go",
            "/workspace/wrk_TEST123/usage",
            "/workspace/wrk_TEST123/billing",
        ])
    }

    @Test
    func `usage and billing pages derive trailing spend windows from live loader shape`() async throws {
        defer {
            OpenCodeStubURLProtocol.handler = nil
        }

        var methods: [String] = []
        var paths: [String] = []
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let records = [
            UsageRecord(timeCreated: formatter.string(from: now.addingTimeInterval(-(60 * 60))), cost: 2_000_000),
            UsageRecord(timeCreated: formatter.string(from: now.addingTimeInterval(-(4 * 60 * 60))), cost: 2_000_000),
            UsageRecord(
                timeCreated: formatter.string(from: now.addingTimeInterval(-(3 * 24 * 60 * 60))),
                cost: 6_000_000),
            UsageRecord(
                timeCreated: formatter.string(from: now.addingTimeInterval(-(9 * 24 * 60 * 60))),
                cost: 10_000_000),
        ]
        OpenCodeStubURLProtocol.handler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            methods.append(request.httpMethod ?? "GET")
            paths.append(url.path)

            switch url.path {
            case "/workspace/wrk_TEST123/usage":
                return Self.makeResponse(
                    url: url,
                    body: Self.usagePageHTML(workspaceID: "wrk_TEST123", records: records),
                    statusCode: 200,
                    contentType: "text/html")
            case "/workspace/wrk_TEST123/billing":
                return Self.makeResponse(
                    url: url,
                    body: Self.billingPageHTML(workspaceID: "wrk_TEST123", balance: 80_000_000),
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
            workspaceIDOverride: "wrk_TEST123",
            session: self.makeSession())

        #expect(snapshot.rollingUsagePercent == 4)
        #expect(snapshot.weeklyUsagePercent == 10)
        #expect(snapshot.rollingResetInSec == 3600)
        #expect(snapshot.weeklyResetInSec == 4 * 24 * 60 * 60)
        #expect(methods == ["GET", "GET"])
        #expect(paths == ["/workspace/wrk_TEST123/usage", "/workspace/wrk_TEST123/billing"])
    }

    @Test
    func `usage and billing pages allow spacing changes around loader payloads and numeric fields`() async throws {
        defer {
            OpenCodeStubURLProtocol.handler = nil
        }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var paths: [String] = []

        OpenCodeStubURLProtocol.handler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            paths.append(url.path)

            switch url.path {
            case "/workspace/wrk_TEST123/go":
                return Self.makeResponse(
                    url: url,
                    body: #"{"detail":"missing"}"#,
                    statusCode: 404,
                    contentType: "application/json")
            case "/workspace/wrk_TEST123/usage":
                let usagePage = """
                <!DOCTYPE html>
                <html>
                <body>
                <script>
                window._$HY = window._$HY || { r: {} };
                self.$R = self.$R || [];
                _$HY.r["usage.list    [\\"wrk_TEST123\\",0]"] = $R[22] = ($R[2] = r => (
                    r.p = new Promise((s, f) => { r.s = s, r.f = f })
                ))($R[23] = { p: 0, s: 0, f: 0 });
                ($R[16] = (r, d) => { r.s(d), r.p.s = 1, r.p.v = d })($R[23], $R[26] = [{
                    id:"usg_0",workspaceID:"wrk_TEST123",
                    timeCreated:$R[28]=new Date("\(formatter.string(from: now.addingTimeInterval(-(30 * 60))))"),
                    timeUpdated:$R[29]=new Date("\(formatter.string(from: now.addingTimeInterval(-(30 * 60))))"),
                    timeDeleted:null,model:"glm-5.1",provider:"deepinfra",inputTokens:1,outputTokens:1,
                    reasoningTokens:null,cacheReadTokens:0,cacheWrite5mTokens:null,cacheWrite1hTokens:null,
                    cost:1000000,keyID:"key_redacted",sessionID:"",enrichment:$R[30]={plan:"lite"}
                }]);
                </script>
                </body>
                </html>
                """
                return Self.makeResponse(
                    url: url,
                    body: usagePage,
                    statusCode: 200,
                    contentType: "text/html")
            case "/workspace/wrk_TEST123/billing":
                let billingPage = """
                <!DOCTYPE html>
                <html>
                <body>
                <script>
                window._$HY = window._$HY || { r: {} };
                self.$R = self.$R || [];
                _$HY.r["billing.get    [\\"wrk_TEST123\\"]"] = $R[15] = ($R[2] = r => (
                    r.p = new Promise((s, f) => { r.s = s, r.f = f })
                ))($R[16] = { p: 0, s: 0, f: 0 });
                ($R[22] = (r, d) => { r.s(d), r.p.s = 1, r.p.v = d })(
                    $R[16],
                    $R[23] = {
                        balance : 9000000,
                        monthlyLimit : null,
                        monthlyUsage : 0
                    }
                );
                </script>
                </body>
                </html>
                """
                return Self.makeResponse(
                    url: url,
                    body: billingPage,
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
            workspaceIDOverride: "wrk_TEST123",
            session: self.makeSession())

        #expect(snapshot.rollingUsagePercent == 10)
        #expect(snapshot.weeklyUsagePercent == 10)
        #expect(snapshot.rollingResetInSec == 4 * 60 * 60 + 30 * 60)
        #expect(snapshot.weeklyResetInSec == 6 * 24 * 60 * 60 + 23 * 60 * 60 + 30 * 60)
        #expect(paths == [
            "/workspace/wrk_TEST123/go",
            "/workspace/wrk_TEST123/usage",
            "/workspace/wrk_TEST123/billing",
        ])
    }

    @Test
    func `usage page missing loader payload returns parse failed without server fallback`() async throws {
        defer {
            OpenCodeStubURLProtocol.handler = nil
        }

        var methods: [String] = []
        var paths: [String] = []
        OpenCodeStubURLProtocol.handler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            methods.append(request.httpMethod ?? "GET")
            paths.append(url.path)

            return Self.makeResponse(
                url: url,
                body: "<html><body><p>Usage loader unavailable.</p></body></html>",
                statusCode: 200,
                contentType: "text/html")
        }

        do {
            _ = try await OpenCodeUsageFetcher.fetchUsage(
                cookieHeader: "auth=test",
                timeout: 2,
                workspaceIDOverride: "wrk_TEST123",
                session: self.makeSession())
            Issue.record("Expected OpenCodeUsageError.parseFailed")
        } catch let error as OpenCodeUsageError {
            switch error {
            case let .parseFailed(message):
                #expect(message.contains("Missing usage records"))
            default:
                Issue.record("Expected parseFailed, got: \(error)")
            }
        }

        #expect(methods == ["GET"])
        #expect(paths == ["/workspace/wrk_TEST123/usage"])
    }

    @Test
    func `empty usage page with billing data returns zero usage snapshot`() async throws {
        defer {
            OpenCodeStubURLProtocol.handler = nil
        }

        var paths: [String] = []
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        OpenCodeStubURLProtocol.handler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            paths.append(url.path)

            switch url.path {
            case "/workspace/wrk_TEST123/go":
                return Self.makeResponse(
                    url: url,
                    body: "<html><body><p>Not subscribed to Go.</p></body></html>",
                    statusCode: 404,
                    contentType: "text/html")
            case "/workspace/wrk_TEST123/usage":
                return Self.makeResponse(
                    url: url,
                    body: "<html><body><p>No usage data available for the selected period.</p></body></html>",
                    statusCode: 200,
                    contentType: "text/html")
            case "/workspace/wrk_TEST123/billing":
                return Self.makeResponse(
                    url: url,
                    body: Self.billingPageHTML(workspaceID: "wrk_TEST123", balance: 80_000_000),
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
            workspaceIDOverride: "wrk_TEST123",
            session: self.makeSession())

        #expect(snapshot.rollingUsagePercent == 0)
        #expect(snapshot.weeklyUsagePercent == 0)
        #expect(snapshot.rollingResetInSec == 0)
        #expect(snapshot.weeklyResetInSec == 0)
        #expect(paths == [
            "/workspace/wrk_TEST123/go",
            "/workspace/wrk_TEST123/usage",
            "/workspace/wrk_TEST123/billing",
        ])
    }

    @Test
    func `workspace get public actor error is treated as invalid credentials without post retry`() async throws {
        defer {
            OpenCodeStubURLProtocol.handler = nil
        }

        var methods: [String] = []
        OpenCodeStubURLProtocol.handler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            methods.append(request.httpMethod ?? "GET")
            let body = [
                #";0x00000263;((self.$R=self.$R||{})["server-fn:test"]=[],"#,
                #"($R=>$R[0]=Object.assign(new Error("actor of type \"public\" is not associated with an account"),"#,
                #"{stack:"Error: actor of type \"public\" is not associated with an account"}))"#,
                #"($R["server-fn:test"]))"#,
            ].joined()
            return Self.makeResponse(
                url: url,
                body: body,
                statusCode: 200,
                contentType: "text/javascript")
        }

        do {
            _ = try await OpenCodeUsageFetcher.fetchUsage(
                cookieHeader: "auth=test",
                timeout: 2,
                session: self.makeSession())
            Issue.record("Expected OpenCodeUsageError.invalidCredentials")
        } catch let error as OpenCodeUsageError {
            switch error {
            case .invalidCredentials:
                break
            default:
                Issue.record("Expected invalidCredentials, got: \(error)")
            }
        }

        #expect(methods == ["GET"])
    }

    @Test
    func `billing page missing balance data returns parse failed after usage succeeds`() async throws {
        defer {
            OpenCodeStubURLProtocol.handler = nil
        }

        var methods: [String] = []
        var paths: [String] = []
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        OpenCodeStubURLProtocol.handler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            methods.append(request.httpMethod ?? "GET")
            paths.append(url.path)

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
                        ]),
                    statusCode: 200,
                    contentType: "text/html")
            case "/workspace/wrk_TEST123/billing":
                return Self.makeResponse(
                    url: url,
                    body: Self.billingPageHTML(workspaceID: "wrk_TEST123", balance: nil),
                    statusCode: 200,
                    contentType: "text/html")
            default:
                Issue.record("Unexpected path: \(url.path)")
                return Self.makeResponse(url: url, body: "unexpected", statusCode: 404, contentType: "text/plain")
            }
        }

        do {
            _ = try await OpenCodeUsageFetcher.fetchUsage(
                cookieHeader: "auth=test",
                timeout: 2,
                now: now,
                workspaceIDOverride: "wrk_TEST123",
                session: self.makeSession())
            Issue.record("Expected OpenCodeUsageError.parseFailed")
        } catch let error as OpenCodeUsageError {
            switch error {
            case let .parseFailed(message):
                #expect(message.contains("Missing billing balance"))
            default:
                Issue.record("Expected parseFailed, got: \(error)")
            }
        }

        #expect(methods == ["GET", "GET"])
        #expect(paths == ["/workspace/wrk_TEST123/usage", "/workspace/wrk_TEST123/billing"])
    }

    @Test
    func `normalizes workspace override from URL into usage and billing paths`() async throws {
        defer {
            OpenCodeStubURLProtocol.handler = nil
        }

        var paths: [String] = []
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        OpenCodeStubURLProtocol.handler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            paths.append(url.path)

            switch url.path {
            case "/workspace/wrk_URL123/usage":
                return Self.makeResponse(
                    url: url,
                    body: Self.usagePageHTML(
                        workspaceID: "wrk_URL123",
                        records: [
                            UsageRecord(
                                timeCreated: formatter.string(from: now.addingTimeInterval(-(30 * 60))),
                                cost: 1_000_000),
                        ]),
                    statusCode: 200,
                    contentType: "text/html")
            case "/workspace/wrk_URL123/billing":
                return Self.makeResponse(
                    url: url,
                    body: Self.billingPageHTML(workspaceID: "wrk_URL123", balance: 9_000_000),
                    statusCode: 200,
                    contentType: "text/html")
            default:
                Issue.record("Unexpected path: \(url.path)")
                return Self.makeResponse(url: url, body: "unexpected", statusCode: 404, contentType: "text/plain")
            }
        }

        _ = try await OpenCodeUsageFetcher.fetchUsage(
            cookieHeader: "auth=test",
            timeout: 2,
            now: now,
            workspaceIDOverride: "https://opencode.ai/workspace/wrk_URL123/billing",
            session: self.makeSession())

        #expect(paths == ["/workspace/wrk_URL123/usage", "/workspace/wrk_URL123/billing"])
    }

    @Test
    func `fetcher sends only auth cookie to opencode host`() async throws {
        defer {
            OpenCodeStubURLProtocol.handler = nil
        }

        var observedCookies: [String] = []
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        OpenCodeStubURLProtocol.handler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            observedCookies.append(request.value(forHTTPHeaderField: "Cookie") ?? "")

            switch url.path {
            case "/workspace/wrk_TEST123/usage":
                return Self.makeResponse(
                    url: url,
                    body: Self.usagePageHTML(
                        workspaceID: "wrk_TEST123",
                        records: [
                            UsageRecord(
                                timeCreated: formatter.string(from: now.addingTimeInterval(-(30 * 60))),
                                cost: 1_000_000),
                        ]),
                    statusCode: 200,
                    contentType: "text/html")
            case "/workspace/wrk_TEST123/billing":
                return Self.makeResponse(
                    url: url,
                    body: Self.billingPageHTML(workspaceID: "wrk_TEST123", balance: 9_000_000),
                    statusCode: 200,
                    contentType: "text/html")
            default:
                Issue.record("Unexpected path: \(url.path)")
                return Self.makeResponse(url: url, body: "unexpected", statusCode: 404, contentType: "text/plain")
            }
        }

        _ = try await OpenCodeUsageFetcher.fetchUsage(
            cookieHeader: "provider=google; auth=test",
            timeout: 2,
            now: now,
            workspaceIDOverride: "wrk_TEST123",
            session: self.makeSession())

        #expect(observedCookies == ["auth=test", "auth=test"])
    }

    private static func usagePageHTML(workspaceID: String, records: [UsageRecord]) -> String {
        let recordText = records.enumerated().map { index, record in
            self.usageRecordHTML(index: index, workspaceID: workspaceID, record: record)
        }
        .joined(separator: ",")

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
        <div data-component="empty-state"><p>No usage data available for the selected period.</p></div>
        </body>
        </html>
        """
    }

    private static func billingPageHTML(workspaceID: String, balance: Int?) -> String {
        let balanceLiteral = balance.map(String.init) ?? "null"
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
                monthlyLimit:null,
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

final class OpenCodeStubURLProtocol: URLProtocol {
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
