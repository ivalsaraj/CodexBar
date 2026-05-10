import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct OpenCodeWorkspaceDiscoveryTests {
    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OpenCodeStubURLProtocol.self]
        return URLSession(configuration: config)
    }

    @Test
    func `parses workspace metadata from seroval response`() {
        let text = ";0x00000089;((self.$R=self.$R||{})[\"codexbar\"]=[]," +
            "($R=>$R[0]=[$R[1]={id:\"wrk_01K6AR1ZET89H8NB691FQ2C2VB\",name:\"Default\"," +
            "slug:null,owner:{name:\"Team Alpha\"}}," +
            "$R[2]={id:\"wrk_01K6AR1ZET89H8NB691FQ2C2VC\",name:\"Sandbox\",slug:null,owner:{name:\"Personal\"}}])" +
            "($R[\"codexbar\"]))"

        let workspaces = OpenCodeWorkspaceDiscovery.parseWorkspaces(text: text)

        #expect(workspaces == [
            OpenCodeDiscoveredWorkspace(
                workspaceID: "wrk_01K6AR1ZET89H8NB691FQ2C2VB",
                workspaceLabel: "Default",
                ownerLabel: "Team Alpha"),
            OpenCodeDiscoveredWorkspace(
                workspaceID: "wrk_01K6AR1ZET89H8NB691FQ2C2VC",
                workspaceLabel: "Sandbox",
                ownerLabel: "Personal"),
        ])
    }

    @Test
    func `parses workspace metadata from nested JSON fallback`() throws {
        let payload: [String: Any] = [
            "workspaces": [
                [
                    "id": "wrk_JSON123",
                    "name": "JSON Workspace",
                    "owner": [
                        "name": "JSON Owner",
                    ],
                ],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let text = String(data: data, encoding: .utf8) ?? ""

        let workspaces = OpenCodeWorkspaceDiscovery.parseWorkspaces(text: text)

        #expect(workspaces == [
            OpenCodeDiscoveredWorkspace(
                workspaceID: "wrk_JSON123",
                workspaceLabel: "JSON Workspace",
                ownerLabel: "JSON Owner"),
        ])
    }

    @Test
    func `normalizes workspace identifiers from raw ids and urls`() {
        #expect(OpenCodeWorkspaceDiscovery.normalizeWorkspaceID("wrk_RAW123") == "wrk_RAW123")
        #expect(
            OpenCodeWorkspaceDiscovery
                .normalizeWorkspaceID("https://opencode.ai/workspace/wrk_URL123/billing")
                == "wrk_URL123")
        #expect(OpenCodeWorkspaceDiscovery.normalizeWorkspaceID("workspace=wrk_QUERY123") == "wrk_QUERY123")
        #expect(OpenCodeWorkspaceDiscovery.normalizeWorkspaceID("not-a-workspace") == nil)
    }

    @Test
    func `discovers workspaces from current session`() async throws {
        defer {
            OpenCodeStubURLProtocol.handler = nil
        }

        OpenCodeStubURLProtocol.handler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            let body =
                ";0x00000089;((self.$R=self.$R||{})[\"codexbar\"]=[]," +
                "($R=>$R[0]=[$R[1]={id:\"wrk_DISCOVER123\",name:\"Discovered\",slug:null,owner:{name:\"Team One\"}}])" +
                "($R[\"codexbar\"]))"
            return Self.makeResponse(url: url, body: body, statusCode: 200, contentType: "text/javascript")
        }

        let workspaces = try await OpenCodeWorkspaceDiscovery.discoverWorkspaces(
            cookieHeader: "auth=test",
            timeout: 2,
            session: self.makeSession())

        #expect(workspaces == [
            OpenCodeDiscoveredWorkspace(
                workspaceID: "wrk_DISCOVER123",
                workspaceLabel: "Discovered",
                ownerLabel: "Team One"),
        ])
    }

    @Test
    func `discovery retries post when get payload has no workspaces`() async throws {
        defer {
            OpenCodeStubURLProtocol.handler = nil
        }

        var methods: [String] = []
        OpenCodeStubURLProtocol.handler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            methods.append(request.httpMethod ?? "GET")
            let body = if methods.count == 1 {
                #"{"workspaces":[]}"#
            } else {
                #"{"workspaces":[{"id":"wrk_POST123","name":"Post Fallback","owner":{"name":"Recovered"}}]}"#
            }
            return Self.makeResponse(url: url, body: body, statusCode: 200, contentType: "application/json")
        }

        let workspaces = try await OpenCodeWorkspaceDiscovery.discoverWorkspaces(
            cookieHeader: "auth=test",
            timeout: 2,
            session: self.makeSession())

        #expect(methods == ["GET", "POST"])
        #expect(workspaces == [
            OpenCodeDiscoveredWorkspace(
                workspaceID: "wrk_POST123",
                workspaceLabel: "Post Fallback",
                ownerLabel: "Recovered"),
        ])
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
