import Foundation
import Testing
@testable import CodexBar

@Suite("CodexLoginRunner")
struct CodexLoginRunnerTests {
    @Test("buildLoginEnvironment prepends resolved executable directory")
    func buildLoginEnvironmentPrependsResolvedExecutableDirectory() {
        let baseEnv: [String: String] = [
            "PATH": "/usr/bin:/bin",
        ]

        let env = CodexLoginRunner.buildLoginEnvironment(
            baseEnv: baseEnv,
            loginPATH: nil,
            resolvedExecutable: "/opt/homebrew/bin/codex")

        let path = env["PATH"] ?? ""
        #expect(path.hasPrefix("/opt/homebrew/bin:"))
        #expect(path.contains("/usr/bin"))
    }

    @Test("buildLoginEnvironment does not duplicate resolved executable directory")
    func buildLoginEnvironmentDoesNotDuplicateResolvedExecutableDirectory() {
        let baseEnv: [String: String] = [
            "PATH": "/opt/homebrew/bin:/usr/bin:/bin",
        ]

        let env = CodexLoginRunner.buildLoginEnvironment(
            baseEnv: baseEnv,
            loginPATH: nil,
            resolvedExecutable: "/opt/homebrew/bin/codex")

        let components = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        let matches = components.filter { $0 == "/opt/homebrew/bin" }
        #expect(matches.count == 1)
    }
}
