import Foundation
import Testing
@testable import CodexBarCore

@Suite("CodexDependentProcessProbe")
struct CodexDependentProcessProbeTests {
    @Test("parses headerless ps output and classifies BrowserForce")
    func classifiesBrowserForceProcess() throws {
        let output = """
          810 Mon Mar  4 09:14:33 2026 /bin/node /bin/node /tmp/browserforce/codex.js --stdio
        """

        let snapshot = CodexDependentProcessProbe.parsePSOutputForTesting(
            output,
            capturedAt: Date(timeIntervalSince1970: 1_709_541_000))

        #expect(snapshot.processes.count == 1)
        let process = try #require(snapshot.processes.first)
        #expect(process.pid == 810)
        #expect(process.source == .browserForce)
        #expect(process.process == "node")
        #expect(process.command.contains("browserforce"))
    }

    @Test("filters codex-related processes and classifies source buckets")
    func filtersAndClassifiesSources() {
        let output = """
          120 Mon Mar  4 08:00:01 2026 /Applications/Codex.app/Codex /Applications/Codex.app/Codex --headless
          121 Mon Mar  4 08:01:01 2026 /Applications/Cursor.app/Cursor /Applications/Cursor.app/Cursor --openai.chatgpt
          122 Mon Mar  4 08:02:01 2026 /bin/zsh /bin/zsh -lc codex chat --model gpt-5
          123 Mon Mar  4 08:03:01 2026 /usr/bin/python3 /usr/bin/python3 /tmp/script.py
        """

        let snapshot = CodexDependentProcessProbe.parsePSOutputForTesting(
            output,
            capturedAt: Date(timeIntervalSince1970: 1_709_541_000))

        #expect(snapshot.processes.map(\.pid) == [120, 121, 122])
        #expect(snapshot.processes.map(\.source) == [.codexApp, .cursor, .terminalOther])
        #expect(snapshot.processes.map(\.process) == ["Codex", "Cursor", "zsh"])
    }

    @Test("marks process started before switch as stale-risk")
    func staleRiskDetection() throws {
        let output = """
          555 Mon Mar  4 10:00:00 2026 /Applications/Codex.app/Codex /Applications/Codex.app/Codex
        """

        let snapshot = CodexDependentProcessProbe.parsePSOutputForTesting(output, capturedAt: Date())
        let process = try #require(snapshot.processes.first)

        let afterStart = process.startedAt.addingTimeInterval(60)
        #expect(process.isStaleRisk(relativeTo: afterStart))
        #expect(!process.isStaleRisk(relativeTo: process.startedAt))
        #expect(!process.isStaleRisk(relativeTo: nil))
    }

    @Test("ignores malformed and unrelated lines")
    func ignoresMalformedAndUnrelatedLines() {
        let output = """
          malformed line
          999 Mon Mar  4 10:00:00 2026 /usr/bin/env /usr/bin/env NODE_ENV=dev
          1000 Mon Mar  4 10:00:01 2026 /usr/local/bin/codexbar /usr/local/bin/codexbar --debug
        """

        let snapshot = CodexDependentProcessProbe.parsePSOutputForTesting(output, capturedAt: Date())

        #expect(snapshot.processes.isEmpty)
    }
}
