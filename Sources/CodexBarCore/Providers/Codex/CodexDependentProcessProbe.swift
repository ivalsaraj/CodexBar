import Foundation

public struct CodexDependentProcessSnapshot: Sendable, Equatable {
    public struct Process: Sendable, Equatable {
        public enum Source: String, CaseIterable, Sendable {
            case browserForce = "BrowserForce"
            case codexApp = "Codex.app"
            case cursor = "Cursor"
            case terminalOther = "Terminal/Other"
        }

        public let process: String
        public let pid: Int
        public let source: Source
        public let startedAt: Date
        public let command: String

        public init(
            process: String,
            pid: Int,
            source: Source,
            startedAt: Date,
            command: String)
        {
            self.process = process
            self.pid = pid
            self.source = source
            self.startedAt = startedAt
            self.command = command
        }

        public func isStaleRisk(relativeTo lastSwitchAt: Date?) -> Bool {
            guard let lastSwitchAt else { return false }
            return self.startedAt < lastSwitchAt
        }
    }

    public let capturedAt: Date
    public let processes: [Process]

    public init(capturedAt: Date, processes: [Process]) {
        self.capturedAt = capturedAt
        self.processes = processes
    }
}

public enum CodexDependentProcessProbe {
    private static let commandTimeout: TimeInterval = 3.0

    public static func snapshot(now: Date = .init()) async throws -> CodexDependentProcessSnapshot {
        let result = try await SubprocessRunner.run(
            binary: "/bin/ps",
            arguments: ["-axo", "pid=,lstart=,comm=,command="],
            environment: ProcessInfo.processInfo.environment,
            timeout: Self.commandTimeout,
            label: "codex-dependent-processes")

        return self.parsePSOutputForTesting(result.stdout, capturedAt: now)
    }

    static func parsePSOutputForTesting(_ output: String, capturedAt: Date) -> CodexDependentProcessSnapshot {
        var rows: [CodexDependentProcessSnapshot.Process] = []

        for line in output.split(whereSeparator: \.isNewline) {
            guard let parsed = self.parseProcessLine(String(line)),
                  let source = self.classifySource(for: parsed)
            else { continue }

            rows.append(
                CodexDependentProcessSnapshot.Process(
                    process: self.processName(comm: parsed.comm, command: parsed.command),
                    pid: parsed.pid,
                    source: source,
                    startedAt: parsed.startedAt,
                    command: parsed.command))
        }

        rows.sort { lhs, rhs in
            if lhs.startedAt == rhs.startedAt {
                return lhs.pid < rhs.pid
            }
            return lhs.startedAt < rhs.startedAt
        }

        return CodexDependentProcessSnapshot(capturedAt: capturedAt, processes: rows)
    }

    private struct ParsedProcessLine: Sendable {
        let pid: Int
        let startedAt: Date
        let comm: String
        let command: String
    }

    private static func parseProcessLine(_ line: String) -> ParsedProcessLine? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = self.processLineRegex.firstMatch(in: line, options: [], range: range),
              let pidRange = Range(match.range(at: 1), in: line),
              let startedRange = Range(match.range(at: 2), in: line),
              let commRange = Range(match.range(at: 3), in: line),
              let commandRange = Range(match.range(at: 4), in: line),
              let pid = Int(line[pidRange])
        else { return nil }

        let normalizedStartedAt = self.normalizedPSDate(String(line[startedRange]))
        guard let startedAt = self.psDateFormatter.date(from: normalizedStartedAt) else { return nil }

        return ParsedProcessLine(
            pid: pid,
            startedAt: startedAt,
            comm: String(line[commRange]),
            command: String(line[commandRange]).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func classifySource(
        for process: ParsedProcessLine) -> CodexDependentProcessSnapshot.Process.Source?
    {
        let command = process.command.lowercased()
        let comm = process.comm.lowercased()
        let haystack = "\(comm) \(command)"

        guard self.isCodexRelated(haystack: haystack) else { return nil }

        if haystack.contains("browserforce") { return .browserForce }
        if haystack.contains("/codex.app/") { return .codexApp }
        if haystack.contains("cursor") || haystack.contains("openai.chatgpt") { return .cursor }
        return .terminalOther
    }

    private static func isCodexRelated(haystack: String) -> Bool {
        guard !haystack.contains("codexbar") else { return false }
        if haystack.contains("openai.chatgpt") { return true }
        if haystack.contains("browserforce") { return true }
        return haystack.contains("codex")
    }

    private static func processName(comm: String, command: String) -> String {
        if let token = command.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).first {
            let cleaned = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            let component = URL(fileURLWithPath: cleaned).lastPathComponent
            if !component.isEmpty {
                return component
            }
        }

        let commName = URL(fileURLWithPath: comm).lastPathComponent
        if !commName.isEmpty {
            return commName
        }

        return comm
    }

    private static func normalizedPSDate(_ value: String) -> String {
        value.replacingOccurrences(of: #"\\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let processLineRegex: NSRegularExpression = {
        let pattern = #"^\s*(\d+)\s+([A-Za-z]{3}\s+[A-Za-z]{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}\s+\d{4})\s+(\S+)\s+(.*)$"#
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            preconditionFailure("Invalid process line regex: \(error)")
        }
    }()

    private static let psDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return formatter
    }()
}
