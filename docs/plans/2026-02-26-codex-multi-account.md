# Codex Multi-Account Support Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add multi-account switching for the Codex (OpenAI) provider in CodexBar, propagating instantly to the CLI, IDE extension, and Codex.app by atomically rewriting `~/.codex/auth.json` on each switch.

**Architecture:** A new `codexOAuth` injection case is added to `TokenAccountInjection`. Codex is registered in `TokenAccountSupportCatalog+Data.swift`, unlocking the full existing account switcher UI. At switch time, the selected account's stored auth.json content is atomically written to `~/.codex/auth.json`. Parallel usage fetching for inactive accounts uses per-account temp `CODEX_HOME` directories to avoid file conflicts.

**Tech Stack:** Swift 6, Swift Testing framework (`import Testing`), `Data.write(to:options:.atomic)` for create-or-overwrite atomic writes (handles first-write correctly), `FileManager.setAttributes([.posixPermissions:])` for 0600/0700 security hardening, existing `TokenAccountSupportCatalog` / `ProviderRegistry` / `UsageStore` infrastructure.

---

## Task 1: `CodexOAuthAccountWriter` — validator + atomic writer

**Files:**
- Create: `Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexOAuthAccountWriter.swift`
- Create: `Tests/CodexBarTests/CodexOAuthAccountWriterTests.swift`

This is the foundation. Everything else depends on validated writes succeeding.

---

**Step 1: Write the failing tests**

Create `Tests/CodexBarTests/CodexOAuthAccountWriterTests.swift`:

```swift
import Foundation
import Testing
@testable import CodexBarCore

@Suite("CodexOAuthAccountWriter")
struct CodexOAuthAccountWriterTests {

    // MARK: - validate()

    @Test("valid OAuth JSON passes validation")
    func validateValidOAuth() {
        let json = """
        {"auth_mode":"chatgpt","tokens":{"access_token":"tok_abc","refresh_token":"ref_xyz","id_token":"id_123","account_id":"acc_456"},"last_refresh":"2026-02-26T10:00:00Z"}
        """
        #expect(throws: Never.self) {
            try CodexOAuthAccountWriter.validate(jsonString: json)
        }
    }

    @Test("legacy API key JSON passes validation")
    func validateLegacyAPIKey() {
        let json = """
        {"OPENAI_API_KEY":"sk-abc123"}
        """
        #expect(throws: Never.self) {
            try CodexOAuthAccountWriter.validate(jsonString: json)
        }
    }

    @Test("empty string fails validation")
    func validateEmptyString() {
        #expect(throws: CodexOAuthAccountWriterError.self) {
            try CodexOAuthAccountWriter.validate(jsonString: "")
        }
    }

    @Test("invalid JSON fails validation")
    func validateInvalidJSON() {
        #expect(throws: CodexOAuthAccountWriterError.self) {
            try CodexOAuthAccountWriter.validate(jsonString: "not json")
        }
    }

    @Test("missing tokens and API key fails validation")
    func validateMissingTokens() {
        let json = """
        {"auth_mode":"chatgpt"}
        """
        #expect(throws: CodexOAuthAccountWriterError.self) {
            try CodexOAuthAccountWriter.validate(jsonString: json)
        }
    }

    @Test("empty access_token fails validation")
    func validateEmptyAccessToken() {
        let json = """
        {"tokens":{"access_token":"","refresh_token":"ref_xyz"}}
        """
        #expect(throws: CodexOAuthAccountWriterError.self) {
            try CodexOAuthAccountWriter.validate(jsonString: json)
        }
    }

    @Test("missing refresh_token fails validation for OAuth mode")
    func validateMissingRefreshToken() {
        let json = """
        {"tokens":{"access_token":"tok_abc"}}
        """
        #expect(throws: CodexOAuthAccountWriterError.self) {
            try CodexOAuthAccountWriter.validate(jsonString: json)
        }
    }

    // MARK: - write(to:)

    @Test("write creates auth.json atomically")
    func writeCreatesFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let json = """
        {"tokens":{"access_token":"tok_abc","refresh_token":"ref_xyz"}}
        """
        try CodexOAuthAccountWriter.write(jsonString: json, toCodexHome: tempDir)

        let authFile = tempDir.appendingPathComponent("auth.json")
        #expect(FileManager.default.fileExists(atPath: authFile.path))

        let data = try Data(contentsOf: authFile)
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let tokens = parsed?["tokens"] as? [String: Any]
        #expect(tokens?["access_token"] as? String == "tok_abc")
    }

    @Test("write creates intermediate directories")
    func writeCreatesDirectories() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("nested")
        defer { try? FileManager.default.removeItem(at: tempDir.deletingLastPathComponent()) }

        let json = """
        {"tokens":{"access_token":"tok_abc","refresh_token":"ref_xyz"}}
        """
        try CodexOAuthAccountWriter.write(jsonString: json, toCodexHome: tempDir)
        let authFile = tempDir.appendingPathComponent("auth.json")
        #expect(FileManager.default.fileExists(atPath: authFile.path))
    }

    @Test("write to nonexistent path succeeds — first import scenario")
    func writeToNonExistentPath() throws {
        // Destination dir does NOT exist — simulates first-time account import.
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let json = """
        {"tokens":{"access_token":"first_tok","refresh_token":"first_ref"}}
        """
        // Must not throw — Data.write(options:.atomic) handles create-or-overwrite.
        try CodexOAuthAccountWriter.write(jsonString: json, toCodexHome: tempDir)

        let authFile = tempDir.appendingPathComponent("auth.json")
        #expect(FileManager.default.fileExists(atPath: authFile.path))
    }

    @Test("written auth.json has 0600 permissions")
    func writeEnforces0600Permissions() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let json = """
        {"tokens":{"access_token":"tok_abc","refresh_token":"ref_xyz"}}
        """
        try CodexOAuthAccountWriter.write(jsonString: json, toCodexHome: tempDir)

        let authFile = tempDir.appendingPathComponent("auth.json")
        let attrs = try FileManager.default.attributesOfItem(atPath: authFile.path)
        let perms = attrs[.posixPermissions] as? Int ?? 0
        #expect(perms == 0o600, "Expected 0600, got \(String(format: "%o", perms))")
    }

    @Test("write with invalid JSON throws before touching disk")
    func writeInvalidJSONThrows() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        #expect(throws: CodexOAuthAccountWriterError.self) {
            try CodexOAuthAccountWriter.write(jsonString: "bad json", toCodexHome: tempDir)
        }
        // Directory should NOT have been created
        #expect(!FileManager.default.fileExists(atPath: tempDir.path))
    }

    @Test("write overwrites existing auth.json atomically")
    func writeOverwritesExisting() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let authFile = tempDir.appendingPathComponent("auth.json")
        try Data("{\"tokens\":{\"access_token\":\"old\",\"refresh_token\":\"old\"}}".utf8)
            .write(to: authFile)

        let newJSON = """
        {"tokens":{"access_token":"new_tok","refresh_token":"new_ref"}}
        """
        try CodexOAuthAccountWriter.write(jsonString: newJSON, toCodexHome: tempDir)

        let data = try Data(contentsOf: authFile)
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let tokens = parsed?["tokens"] as? [String: Any]
        #expect(tokens?["access_token"] as? String == "new_tok")
    }
}
```

**Step 2: Run tests — verify they fail**

```bash
cd ~/Documents/projects/CodexBar
swift test --filter CodexOAuthAccountWriterTests 2>&1 | tail -20
```

Expected: compile error — `CodexOAuthAccountWriter` not found.

**Step 3: Implement `CodexOAuthAccountWriter`**

Create `Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexOAuthAccountWriter.swift`:

```swift
import Foundation

public enum CodexOAuthAccountWriterError: LocalizedError, Equatable {
    case emptyInput
    case invalidJSON(String)
    case missingCredentials
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .emptyInput:
            "No auth.json content provided."
        case let .invalidJSON(detail):
            "Invalid JSON: \(detail)"
        case .missingCredentials:
            "auth.json must contain tokens.access_token + tokens.refresh_token, or OPENAI_API_KEY."
        case let .writeFailed(detail):
            "Failed to write auth.json: \(detail)"
        }
    }
}

public enum CodexOAuthAccountWriter {

    /// Validates that `jsonString` is well-formed Codex auth JSON.
    /// Throws `CodexOAuthAccountWriterError` on any violation.
    public static func validate(jsonString: String) throws {
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CodexOAuthAccountWriterError.emptyInput }

        let data = Data(trimmed.utf8)
        let parsed: [String: Any]
        do {
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CodexOAuthAccountWriterError.invalidJSON("Root is not an object")
            }
            parsed = dict
        } catch let error as CodexOAuthAccountWriterError {
            throw error
        } catch {
            throw CodexOAuthAccountWriterError.invalidJSON(error.localizedDescription)
        }

        // Legacy API-key mode
        if let apiKey = parsed["OPENAI_API_KEY"] as? String,
           !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return
        }

        // OAuth token mode
        guard let tokens = parsed["tokens"] as? [String: Any] else {
            throw CodexOAuthAccountWriterError.missingCredentials
        }
        let accessToken = tokens["access_token"] as? String ?? ""
        let refreshToken = tokens["refresh_token"] as? String ?? ""
        guard !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !refreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw CodexOAuthAccountWriterError.missingCredentials
        }
    }

    /// Validates then atomically writes `jsonString` as `auth.json` inside `codexHomeDir`.
    /// Creates `codexHomeDir` if it does not exist.
    /// Throws `CodexOAuthAccountWriterError` on validation failure or write error.
    public static func write(jsonString: String, toCodexHome codexHomeDir: URL) throws {
        try validate(jsonString: jsonString)

        do {
            try FileManager.default.createDirectory(
                at: codexHomeDir,
                withIntermediateDirectories: true)
        } catch {
            throw CodexOAuthAccountWriterError.writeFailed(
                "Cannot create directory \(codexHomeDir.path): \(error.localizedDescription)")
        }

        let destination = codexHomeDir.appendingPathComponent("auth.json")
        let data = Data(jsonString.trimmingCharacters(in: .whitespacesAndNewlines).utf8)

        // Atomic write: Data.write(options:.atomic) handles create-or-overwrite on first write,
        // avoiding the replaceItemAt API which requires destination to already exist.
        do {
            try data.write(to: destination, options: .atomic)
        } catch {
            throw CodexOAuthAccountWriterError.writeFailed(error.localizedDescription)
        }

        // Enforce 0600 permissions — auth tokens must not be world-readable.
        // Propagate failure — do NOT use try? (silent failure contradicts the hardening goal).
        // On macOS, setAttributes always succeeds for files we own and just created.
        do {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: destination.path)
        } catch {
            throw CodexOAuthAccountWriterError.writeFailed(
                "Cannot set 0600 permissions on auth.json: \(error.localizedDescription)")
        }
    }
}
```

**Step 4: Run tests — verify they pass**

```bash
swift test --filter CodexOAuthAccountWriterTests 2>&1 | tail -10
```

Expected: all tests pass, 0 failures.

**Step 5: Commit**

```bash
cd ~/Documents/projects/CodexBar
git add Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexOAuthAccountWriter.swift \
        Tests/CodexBarTests/CodexOAuthAccountWriterTests.swift
git commit -m "feat(codex): add CodexOAuthAccountWriter with validation and atomic write"
```

---

## Task 2: New `codexOAuth` injection case + catalog registration

**Files:**
- Modify: `Sources/CodexBarCore/TokenAccountSupport.swift` (lines 3–6)
- Modify: `Sources/CodexBarCore/TokenAccountSupportCatalog+Data.swift`
- Test: `Tests/CodexBarTests/TokenAccountSupportCatalogCodexTests.swift` (new)

---

**Step 1: Write failing tests**

Create `Tests/CodexBarTests/TokenAccountSupportCatalogCodexTests.swift`:

```swift
import Foundation
import Testing
@testable import CodexBarCore

@Suite("TokenAccountSupportCatalog — Codex")
struct TokenAccountSupportCatalogCodexTests {

    @Test("codex is registered in the catalog")
    func codexIsRegistered() {
        let support = TokenAccountSupportCatalog.support(for: .codex)
        #expect(support != nil)
    }

    @Test("codex injection type is codexOAuth")
    func codexInjectionType() {
        let support = TokenAccountSupportCatalog.support(for: .codex)
        guard case .codexOAuth = support?.injection else {
            Issue.record("Expected .codexOAuth injection, got \(String(describing: support?.injection))")
            return
        }
    }

    @Test("envOverride for codex returns nil (file write handled separately)")
    func codexEnvOverrideReturnsNil() {
        let result = TokenAccountSupportCatalog.envOverride(
            for: .codex,
            token: "{\"tokens\":{\"access_token\":\"tok\",\"refresh_token\":\"ref\"}}")
        // codexOAuth writes the file at switch time, not via envOverride
        #expect(result == nil)
    }

    @Test("codex placeholder guides user to auth.json")
    func codexPlaceholder() {
        let support = TokenAccountSupportCatalog.support(for: .codex)
        let placeholder = support?.placeholder ?? ""
        #expect(placeholder.contains("auth.json") || placeholder.contains("import"))
    }

    @Test("codex requiresManualCookieSource is false")
    func codexRequiresManualCookieSource() {
        let support = TokenAccountSupportCatalog.support(for: .codex)
        #expect(support?.requiresManualCookieSource == false)
    }
}
```

**Step 2: Run tests — verify they fail**

```bash
swift test --filter TokenAccountSupportCatalogCodexTests 2>&1 | tail -15
```

Expected: compile error (`.codexOAuth` case doesn't exist) or test failures (`.codex` not in catalog).

**Step 3: Add `codexOAuth` case to `TokenAccountInjection`**

Edit `Sources/CodexBarCore/TokenAccountSupport.swift`, lines 3–6:

```swift
// BEFORE:
public enum TokenAccountInjection: Sendable {
    case cookieHeader
    case environment(key: String)
}

// AFTER:
public enum TokenAccountInjection: Sendable {
    case cookieHeader
    case environment(key: String)
    /// Writes the stored auth.json content directly to ~/.codex/auth.json at switch time.
    /// Parallel fetching uses a per-account temp CODEX_HOME directory instead.
    case codexOAuth
}
```

**Step 4: Handle `.codexOAuth` in `envOverride`**

Edit `Sources/CodexBarCore/TokenAccountSupportCatalog.swift`, inside `envOverride`, add the new case after line 43:

```swift
// BEFORE:
switch support.injection {
case let .environment(key):
    return [key: token]
case .cookieHeader:
    // ... claude oauth handling ...
    return nil
}

// AFTER:
switch support.injection {
case let .environment(key):
    return [key: token]
case .cookieHeader:
    // ... claude oauth handling (unchanged) ...
    return nil
case .codexOAuth:
    // File write happens at switch time via CodexAccountSwitcher.switchToAccount().
    // For parallel fetching, ProviderRegistry.makeEnvironment handles temp CODEX_HOME.
    return nil
}
```

**Step 5: Register `.codex` in `TokenAccountSupportCatalog+Data.swift`**

Add at the top of the `supportByProvider` dictionary (after the opening `[`). Include a `UserDefaults` kill switch so the feature can be disabled in the field without a rebuild:

```swift
// Kill switch: `defaults write <bundle-id> codexMultiAccountEnabled -bool NO` disables the feature.
// Defaults to enabled. Allows rollback without a new release.
.codex: UserDefaults.standard.object(forKey: "codexMultiAccountEnabled") as? Bool ?? true
    ? TokenAccountSupport(
        title: "Codex accounts",
        subtitle: "Paste the contents of ~/.codex/auth.json after each `codex login`.",
        placeholder: "Paste auth.json contents… or use Import button",
        injection: .codexOAuth,
        requiresManualCookieSource: false,
        cookieName: nil)
    : nil,
```

> **Kill switch note:** The catalog is read at app startup. Changing `codexMultiAccountEnabled` via `defaults write` requires an **app restart** to take effect. Document this in internal ops runbooks if used for field rollback.
>
> **Note:** The `supportByProvider` value type must be `[UsageProvider: TokenAccountSupport?]` or simply omit the `.codex` key when disabled. If the dictionary type is `[UsageProvider: TokenAccountSupport]` (non-optional), use an `if` guard at the call site instead:
>
> ```swift
> // In supportByProvider initializer — only register if kill switch is enabled:
> if UserDefaults.standard.object(forKey: "codexMultiAccountEnabled") as? Bool ?? true {
>     dict[.codex] = TokenAccountSupport(
>         title: "Codex accounts", ...)
> }
> ```
>
> Use whichever matches the existing dictionary construction pattern in the file.

**Step 6: Run tests — verify they pass**

```bash
swift test --filter TokenAccountSupportCatalogCodexTests 2>&1 | tail -10
```

Expected: all 5 tests pass.

**Step 7: Verify existing catalog tests still pass**

```bash
swift test --filter TokenAccountSupportCatalog 2>&1 | tail -10
```

Expected: no regressions.

**Step 8: Commit**

```bash
git add Sources/CodexBarCore/TokenAccountSupport.swift \
        Sources/CodexBarCore/TokenAccountSupportCatalog+Data.swift \
        Sources/CodexBarCore/TokenAccountSupportCatalog.swift \
        Tests/CodexBarTests/TokenAccountSupportCatalogCodexTests.swift
git commit -m "feat(codex): register codex in TokenAccountSupportCatalog with codexOAuth injection"
```

---

## Task 3: Atomic write on account switch

**Files:**
- Modify: `Sources/CodexBar/ProviderRegistry.swift` (lines 87–111)
- Create: `Tests/CodexBarTests/CodexAccountSwitchTests.swift`

`makeEnvironment` already calls `TokenAccountSupportCatalog.envOverride`. We now add a `codexOAuth`-specific branch: when a `TokenAccountOverride` is present for Codex, write the token to a temp CODEX_HOME and return that path as `CODEX_HOME`. When no override (active account / normal fetch path), the write already happened at switch time — just return the default `CODEX_HOME`.

---

**Step 1: Write failing tests**

Create `Tests/CodexBarTests/CodexAccountSwitchTests.swift`:

```swift
import Foundation
import Testing
@testable import CodexBarCore

@Suite("Codex account switch — CODEX_HOME env injection")
struct CodexAccountSwitchTests {

    let validAuthJSON = """
    {"tokens":{"access_token":"tok_abc","refresh_token":"ref_xyz"}}
    """

    @Test("writeAndMakeTempCodexHome writes auth.json and returns valid dir URL")
    func writeAndMakeTempCodexHome() throws {
        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempBase) }

        let result = try CodexOAuthTempHome.make(
            jsonString: validAuthJSON,
            under: tempBase)

        #expect(FileManager.default.fileExists(atPath: result.path))
        let authFile = result.appendingPathComponent("auth.json")
        #expect(FileManager.default.fileExists(atPath: authFile.path))
    }

    @Test("make with invalid JSON throws")
    func makeWithInvalidJSON() throws {
        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempBase) }

        #expect(throws: CodexOAuthAccountWriterError.self) {
            _ = try CodexOAuthTempHome.make(jsonString: "bad json", under: tempBase)
        }
    }

    @Test("cleanup removes temp dir")
    func cleanupRemovesTempDir() throws {
        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempBase) }

        let tempHome = try CodexOAuthTempHome.make(
            jsonString: validAuthJSON,
            under: tempBase)

        CodexOAuthTempHome.cleanup(tempHome)
        #expect(!FileManager.default.fileExists(atPath: tempHome.path))
    }

    @Test("cleanupAll removes entire base dir")
    func cleanupAllRemovesBaseDir() throws {
        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-test-all-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempBase) }

        _ = try CodexOAuthTempHome.make(jsonString: validAuthJSON, under: tempBase)
        _ = try CodexOAuthTempHome.make(jsonString: validAuthJSON, under: tempBase)

        CodexOAuthTempHome.cleanupAll(under: tempBase)
        #expect(!FileManager.default.fileExists(atPath: tempBase.path))
    }
}
```

**Step 2: Run tests — verify they fail**

```bash
swift test --filter CodexAccountSwitchTests 2>&1 | tail -10
```

Expected: compile error — `CodexOAuthTempHome` not found.

**Step 3: Implement `CodexOAuthTempHome`**

Create `Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexOAuthTempHome.swift`:

```swift
import Foundation

/// Manages ephemeral per-account CODEX_HOME directories used during
/// parallel usage fetching for inactive Codex accounts.
public enum CodexOAuthTempHome {

    /// Creates a temp directory under `base`, writes `auth.json` into it,
    /// and returns the directory URL (to be passed as CODEX_HOME).
    /// Throws if `jsonString` is invalid or the write fails.
    public static func make(jsonString: String, under base: URL) throws -> URL {
        let dir = base.appendingPathComponent(UUID().uuidString)
        try CodexOAuthAccountWriter.write(jsonString: jsonString, toCodexHome: dir)
        // Restrict temp dir to owner-only access — auth tokens must not be world-readable.
        // Propagate failure — do NOT use try? (silent failure contradicts the hardening goal).
        do {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: dir.path)
        } catch {
            // Clean up the dir we just created before propagating the error.
            try? FileManager.default.removeItem(at: dir)
            throw CodexOAuthAccountWriterError.writeFailed(
                "Cannot set 0700 permissions on temp CODEX_HOME: \(error.localizedDescription)")
        }
        return dir
    }

    /// Removes a single temp CODEX_HOME directory created by `make(jsonString:under:)`.
    public static func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    /// Removes the entire `base` directory tree (all temp CODEX_HOMEs at once).
    /// Safe to call even if `base` doesn't exist.
    public static func cleanupAll(under base: URL) {
        try? FileManager.default.removeItem(at: base)
    }
}
```

**Step 4: Wire into `ProviderRegistry.makeEnvironment`**

Edit `Sources/CodexBar/ProviderRegistry.swift`, replacing lines 86–111:

```swift
@MainActor
static func makeEnvironment(
    base: [String: String],
    provider: UsageProvider,
    settings: SettingsStore,
    tokenOverride: TokenAccountOverride?) -> [String: String]
{
    let account = ProviderTokenAccountSelection.selectedAccount(
        provider: provider,
        settings: settings,
        override: tokenOverride)
    var env = ProviderConfigEnvironment.applyAPIKeyOverride(
        base: base,
        provider: provider,
        config: settings.providerConfig(for: provider))

    guard let account else { return env }
    let support = TokenAccountSupportCatalog.support(for: provider)

    switch support?.injection {
    case .codexOAuth:
        // For the active account: auth.json was already written at switch time.
        // For override (parallel fetch): write to a temp CODEX_HOME and point the CLI there.
        if tokenOverride != nil {
            let tempBase = CodexAccountEnvironment.tempBase
            if let tempHome = try? CodexOAuthTempHome.make(
                jsonString: account.token,
                under: tempBase)
            {
                env["CODEX_HOME"] = tempHome.path
                // Store path so UsageStore can clean it up after the fetch.
                CodexAccountEnvironment.registerTempHome(tempHome)
            }
        }
        // else: no CODEX_HOME override — CLI uses ~/.codex/auth.json as normal.
    default:
        // Existing cookie/env-var injection logic.
        if let override = TokenAccountSupportCatalog.envOverride(for: provider, token: account.token) {
            for (key, value) in override {
                env[key] = value
            }
        }
    }

    return env
}
```

**Step 5: Add `CodexAccountEnvironment` helper**

Create `Sources/CodexBar/Providers/Codex/CodexAccountEnvironment.swift`:

```swift
import CodexBarCore
import Foundation

/// Thread-safe registry for temp CODEX_HOME directories created during
/// parallel usage fetches. Cleaned up after each fetch cycle.
@MainActor
enum CodexAccountEnvironment {

    static let tempBase: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex-bar-tmp")

    private static var pendingTempHomes: [URL] = []

    static func registerTempHome(_ url: URL) {
        pendingTempHomes.append(url)
    }

    /// Call after a fetch cycle completes. Removes all temp dirs created during it.
    static func flushTempHomes() {
        for dir in pendingTempHomes {
            CodexOAuthTempHome.cleanup(dir)
        }
        pendingTempHomes.removeAll()
    }

    /// Called on app launch — removes any stale temp dirs from a previous crash.
    static func cleanupOnLaunch() {
        CodexOAuthTempHome.cleanupAll(under: tempBase)
    }
}
```

**Step 6: Run tests — verify they pass**

```bash
swift test --filter CodexAccountSwitchTests 2>&1 | tail -10
```

Expected: all tests pass.

**Step 7: Full test suite — no regressions**

```bash
swift test 2>&1 | tail -20
```

Expected: all passing, no new failures.

**Step 8: Commit**

```bash
git add Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexOAuthTempHome.swift \
        Sources/CodexBar/Providers/Codex/CodexAccountEnvironment.swift \
        Sources/CodexBar/ProviderRegistry.swift \
        Tests/CodexBarTests/CodexAccountSwitchTests.swift
git commit -m "feat(codex): inject per-account temp CODEX_HOME for parallel usage fetching"
```

---

## Task 4: Write auth.json at switch time + launch cleanup

**Files:**
- Create: `Sources/CodexBar/Providers/Codex/CodexAccountSwitcher.swift` (**new** — domain layer for switch logic)
- Modify: `Sources/CodexBar/PreferencesProvidersPane.swift` (delegate `setActiveIndex` to `CodexAccountSwitcher`)
- Modify: `Sources/CodexBar/UsageStore+TokenAccounts.swift` (flush temp homes after `refreshTokenAccounts`)
- Modify: `Sources/CodexBar/CodexbarApp.swift` (call `cleanupOnLaunch` at startup)
- Create: `Tests/CodexBarTests/CodexAuthSwitchWriteTests.swift`

> **Why a separate `CodexAccountSwitcher`:** Placing the write inside the UI closure (`PreferencesProvidersPane`) would mean any future switch trigger (CLI, keyboard shortcut, notifications) would bypass the write. Centralizing in a single domain method makes all switch paths identical and testable without UI.

---

**Step 1: Write failing tests**

Create `Tests/CodexBarTests/CodexAuthSwitchWriteTests.swift`:

```swift
import Foundation
import Testing
@testable import CodexBarCore  // for CodexOAuthAccountWriter, CodexOAuthTempHome
@testable import CodexBar      // for CodexAccountSwitcher (app module — Sources/CodexBar/)

// Note: If the test target does not yet list CodexBar as a dependency in Package.swift,
// add it: .testTarget(name: "CodexBarTests", dependencies: ["CodexBarCore", "CodexBar"])

@Suite("Codex auth.json switch-write integration")
struct CodexAuthSwitchWriteTests {

    let validJSON = """
    {"tokens":{"access_token":"acct2_tok","refresh_token":"acct2_ref"}}
    """

    @Test("writing valid JSON to a custom codexHome creates auth.json")
    func writeValidJSON() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }

        try CodexOAuthAccountWriter.write(jsonString: validJSON, toCodexHome: dir)

        let auth = dir.appendingPathComponent("auth.json")
        let data = try Data(contentsOf: auth)
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let tokens = parsed?["tokens"] as? [String: Any]
        #expect(tokens?["access_token"] as? String == "acct2_tok")
    }

    @Test("write failure does not change existing auth.json content")
    func writeFailureDoesNotCorrupt() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let original = """
        {"tokens":{"access_token":"original_tok","refresh_token":"original_ref"}}
        """
        let auth = dir.appendingPathComponent("auth.json")
        try Data(original.utf8).write(to: auth)

        // Attempt to write invalid JSON — should throw, leave original intact.
        do {
            try CodexOAuthAccountWriter.write(jsonString: "bad json", toCodexHome: dir)
            Issue.record("Expected write to throw")
        } catch {}

        let data = try Data(contentsOf: auth)
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let tokens = parsed?["tokens"] as? [String: Any]
        #expect(tokens?["access_token"] as? String == "original_tok")
    }

    @Test("switchToAccount — write fails → advance closure NOT called")
    func switchToAccount_writeFails_advanceNotCalled() throws {
        // Tests CodexAccountSwitcher's internal testable overload (see implementation below).
        // This directly proves: if write throws, the advance closure is never invoked.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-switch-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        var advanceCalled = false

        do {
            try CodexAccountSwitcher.switchToAccount(
                token: "not-valid-json",   // will fail validation → write throws
                codexHome: dir,
                advance: { advanceCalled = true })
        } catch {
            // Expected — write validation failed.
        }

        #expect(!advanceCalled, "advance must never be called when write throws")
    }

    @Test("temp-home cleanup is idempotent — double-cleanup does not throw")
    func tempHomeCleanupIsIdempotent() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-idempotent-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }

        let tempHome = try CodexOAuthTempHome.make(
            jsonString: validJSON,
            under: base)

        // First cleanup
        CodexOAuthTempHome.cleanup(tempHome)
        #expect(!FileManager.default.fileExists(atPath: tempHome.path))

        // Second cleanup on already-removed dir must not throw.
        CodexOAuthTempHome.cleanup(tempHome)
        // If we reach here without crashing, idempotence is confirmed.
    }
}
```

**Step 2: Run tests — verify they pass** (these depend on Task 1, so should pass immediately after Task 1 is done)

```bash
swift test --filter CodexAuthSwitchWriteTests 2>&1 | tail -10
```

**Step 3: Create `CodexAccountSwitcher` — domain layer**

Create `Sources/CodexBar/Providers/Codex/CodexAccountSwitcher.swift`:

```swift
import CodexBarCore
import Foundation

/// Encapsulates all logic for switching the active Codex account.
/// Centralised here so any future switch trigger (UI, CLI, notification) uses the same path.
@MainActor
enum CodexAccountSwitcher {

    /// Switches to the Codex account at `index` in `settings`.
    ///
    /// **Ordering guarantee:** auth.json is written BEFORE `activeIndex` advances.
    /// If the write fails, this method throws and the active index is NOT changed.
    ///
    /// - Parameters:
    ///   - index:    The target account index (clamped to valid range).
    ///   - settings: The shared settings store.
    ///   - codexHome: The CODEX_HOME directory (defaults to `~/.codex`).
    /// - Throws: `CodexOAuthAccountWriterError` if validation or write fails.
    static func switchToAccount(
        index: Int,
        settings: SettingsStore,
        codexHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    ) throws {
        let accounts = settings.tokenAccounts(for: .codex)
        guard !accounts.isEmpty else { return }
        let clamped = max(0, min(index, accounts.count - 1))
        let token = accounts[clamped].token

        // Delegates to the internal overload — write first, then advance.
        try Self.switchToAccount(
            token: token,
            codexHome: codexHome,
            advance: { settings.setActiveTokenAccountIndex(clamped, for: .codex) })
    }

    /// Internal testable overload — accepts an explicit `advance` closure.
    /// Tests can pass a spy closure to verify advance is NOT called when write throws.
    ///
    /// - Parameters:
    ///   - token:   The raw auth.json content to write.
    ///   - codexHome: Target CODEX_HOME directory.
    ///   - advance: Called only after a successful write (e.g. updates activeIndex).
    /// - Throws: `CodexOAuthAccountWriterError` if write fails. `advance` is never called.
    internal static func switchToAccount(
        token: String,
        codexHome: URL,
        advance: () -> Void
    ) throws {
        // Write FIRST — if this throws, advance is NEVER called.
        try CodexOAuthAccountWriter.write(jsonString: token, toCodexHome: codexHome)
        // Write succeeded — now safe to advance.
        advance()
    }
}
```

**Step 4: Wire `CodexAccountSwitcher` into `setActiveIndex` in `PreferencesProvidersPane.swift`**

In `Sources/CodexBar/PreferencesProvidersPane.swift`, the `setActiveIndex` closure (around line 188). Add an `@State` error banner and delegate to `CodexAccountSwitcher`:

```swift
// Add to the view's @State properties:
@State private var codexSwitchError: String? = nil

// BEFORE:
setActiveIndex: { index in
    self.settings.setActiveTokenAccountIndex(index, for: provider)
    Task { @MainActor in
        await ProviderInteractionContext.$current.withValue(.userInitiated) {
            await self.store.refreshProvider(provider, allowDisabled: true)
        }
    }
},

// AFTER — for .codex with .codexOAuth injection, delegate to CodexAccountSwitcher:
setActiveIndex: { index in
    if provider == .codex,
       case .codexOAuth = TokenAccountSupportCatalog.support(for: .codex)?.injection
    {
        do {
            // Write-first: throws if auth.json cannot be written.
            // On success, CodexAccountSwitcher also advances the activeIndex.
            try CodexAccountSwitcher.switchToAccount(index: index, settings: self.settings)
            self.codexSwitchError = nil
        } catch {
            // Write failed — activeIndex NOT advanced. Surface error to user.
            self.codexSwitchError = error.localizedDescription
            return  // Do not trigger refresh — account did not switch.
        }
    } else {
        // All other providers use the standard path.
        self.settings.setActiveTokenAccountIndex(index, for: provider)
    }

    Task { @MainActor in
        await ProviderInteractionContext.$current.withValue(.userInitiated) {
            await self.store.refreshProvider(provider, allowDisabled: true)
        }
    }
},
```

Also add the error banner somewhere in the view body (near the Codex account switcher):

```swift
if let msg = codexSwitchError {
    Text("Account switch failed: \(msg)")
        .font(.footnote)
        .foregroundStyle(.red)
        .padding(.horizontal)
}
```

**Step 5: Callsite audit — verify all `setActiveTokenAccountIndex` callsites are safe**

```bash
cd ~/Documents/projects/CodexBar
rg -n "setActiveTokenAccountIndex" Sources/
```

Inspect EVERY line in the output. For each callsite:
- If it is inside `CodexAccountSwitcher.switchToAccount()` → **expected, safe**.
- If it is a direct call with `for: .codex` → **must migrate** to `CodexAccountSwitcher.switchToAccount()`.
- If it is a generic call with `for: provider` where `provider` is a variable → **trace whether `provider` can be `.codex`** in that context. If yes → migrate.

> **Why exhaustive:** A filter like `| grep -i codex` misses generic `for: provider` call patterns where `provider` is `.codex` at runtime. Only a full list + manual inspection closes this gap.

**Step 6: Flush temp homes after each fetch cycle**

In `Sources/CodexBar/UsageStore+TokenAccounts.swift`, at the end of `refreshTokenAccounts(provider:accounts:)`, before the final `if let selectedOutcome` block:

```swift
// Add after the for-loop that builds `snapshots`:
await MainActor.run {
    CodexAccountEnvironment.flushTempHomes()
}
```

**Step 7: Cleanup stale temp dirs on launch**

In `Sources/CodexBar/CodexbarApp.swift`, inside the app's `init()` or `onAppear`:

```swift
// Add at the top of app initialization:
CodexAccountEnvironment.cleanupOnLaunch()
```

**Step 8: Run full test suite**

```bash
swift test 2>&1 | tail -20
```

Expected: all passing.

**Step 9: Commit**

```bash
git add Sources/CodexBar/Providers/Codex/CodexAccountSwitcher.swift \
        Sources/CodexBar/PreferencesProvidersPane.swift \
        Sources/CodexBar/UsageStore+TokenAccounts.swift \
        Sources/CodexBar/CodexbarApp.swift \
        Tests/CodexBarTests/CodexAuthSwitchWriteTests.swift
git commit -m "feat(codex): write auth.json on account switch and flush temp CODEX_HOME dirs after fetch"
```

---

## Task 5: "Import current login" button in Preferences

**Files:**
- Modify: `Sources/CodexBar/Providers/Shared/ProviderSettingsDescriptors.swift` (add optional `importCurrentToken` to descriptor)
- Modify: `Sources/CodexBar/PreferencesProviderSettingsRows.swift` (`ProviderSettingsTokenAccountsRowView` — add Import button)
- Modify: `Sources/CodexBar/PreferencesProvidersPane.swift` (wire `importCurrentToken` for `.codex`)
- Create: `Tests/CodexBarTests/CodexImportCurrentLoginTests.swift`

---

**Step 1: Write failing tests**

Create `Tests/CodexBarTests/CodexImportCurrentLoginTests.swift`:

```swift
import Foundation
import Testing
@testable import CodexBarCore

@Suite("Codex — import current login")
struct CodexImportCurrentLoginTests {

    @Test("reads valid auth.json from a given path")
    func readsValidAuthJSON() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let json = """
        {"auth_mode":"chatgpt","tokens":{"access_token":"import_tok","refresh_token":"import_ref"}}
        """
        try Data(json.utf8).write(to: dir.appendingPathComponent("auth.json"))

        let result = try CodexCurrentLoginImporter.read(fromCodexHome: dir)
        #expect(result.contains("import_tok"))
    }

    @Test("returns error when auth.json is absent")
    func returnsErrorWhenAbsent() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent-\(UUID().uuidString)")
        #expect(throws: CodexCurrentLoginImporterError.self) {
            _ = try CodexCurrentLoginImporter.read(fromCodexHome: dir)
        }
    }

    @Test("returns error when auth.json has no tokens")
    func returnsErrorWhenNoTokens() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{\"auth_mode\":\"chatgpt\"}".utf8)
            .write(to: dir.appendingPathComponent("auth.json"))

        #expect(throws: CodexCurrentLoginImporterError.self) {
            _ = try CodexCurrentLoginImporter.read(fromCodexHome: dir)
        }
    }
}
```

**Step 2: Run tests — verify they fail**

```bash
swift test --filter CodexImportCurrentLoginTests 2>&1 | tail -10
```

**Step 3: Implement `CodexCurrentLoginImporter`**

Create `Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexCurrentLoginImporter.swift`:

```swift
import Foundation

public enum CodexCurrentLoginImporterError: LocalizedError {
    case notFound
    case invalidContent(String)

    public var errorDescription: String? {
        switch self {
        case .notFound:
            "No auth.json found at ~/.codex/. Run `codex login` first."
        case let .invalidContent(detail):
            "auth.json is invalid: \(detail)"
        }
    }
}

public enum CodexCurrentLoginImporter {

    /// Reads `auth.json` from `codexHome`, validates it, and returns its raw string content.
    public static func read(fromCodexHome codexHome: URL) throws -> String {
        let authFile = codexHome.appendingPathComponent("auth.json")
        guard FileManager.default.fileExists(atPath: authFile.path) else {
            throw CodexCurrentLoginImporterError.notFound
        }
        let data = try Data(contentsOf: authFile)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw CodexCurrentLoginImporterError.invalidContent("File is not valid UTF-8")
        }
        do {
            try CodexOAuthAccountWriter.validate(jsonString: jsonString)
        } catch let writerError as CodexOAuthAccountWriterError {
            throw CodexCurrentLoginImporterError.invalidContent(
                writerError.errorDescription ?? writerError.localizedDescription)
        }
        return jsonString
    }

    /// Reads the default `~/.codex/auth.json`.
    public static func readDefault() throws -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let codexHome = home.appendingPathComponent(".codex")
        return try read(fromCodexHome: codexHome)
    }
}
```

**Step 4: Add `importCurrentToken` to the descriptor**

Edit `Sources/CodexBar/Providers/Shared/ProviderSettingsDescriptors.swift`, add one optional field to `ProviderSettingsTokenAccountsDescriptor`:

```swift
// Add after `reloadFromDisk`:
let importCurrentToken: (() -> Result<String, Error>)?
```

Update the initializer accordingly (add `importCurrentToken: (() -> Result<String, Error>)? = nil`).

**Step 5: Add Import button to `ProviderSettingsTokenAccountsRowView`**

In `Sources/CodexBar/PreferencesProviderSettingsRows.swift`, inside the "add account" section of `ProviderSettingsTokenAccountsRowView`, add a button that calls `descriptor.importCurrentToken?()` and pre-fills the token text field when it succeeds:

```swift
if let importCurrentToken = descriptor.importCurrentToken {
    Button("Import current login") {
        switch importCurrentToken() {
        case let .success(json):
            newTokenText = json
        case let .failure(error):
            importErrorMessage = error.localizedDescription
        }
    }
    .help("Reads ~/.codex/auth.json from your active `codex login` session")
    if let msg = importErrorMessage {
        Text(msg)
            .font(.footnote)
            .foregroundStyle(.red)
    }
}
```

(Add `@State private var importErrorMessage: String? = nil` to the view's state.)

**Step 6: Wire `importCurrentToken` for Codex in `PreferencesProvidersPane`**

In `tokenAccountDescriptor(for provider:)` (line ~168), set `importCurrentToken` when `provider == .codex`:

```swift
importCurrentToken: provider == .codex ? {
    Result { try CodexCurrentLoginImporter.readDefault() }
} : nil,
```

**Step 7: Run tests — verify they pass**

```bash
swift test --filter CodexImportCurrentLoginTests 2>&1 | tail -10
```

**Step 8: Full suite**

```bash
swift test 2>&1 | tail -20
```

**Step 9: Commit**

```bash
git add Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexCurrentLoginImporter.swift \
        Sources/CodexBar/Providers/Shared/ProviderSettingsDescriptors.swift \
        Sources/CodexBar/PreferencesProviderSettingsRows.swift \
        Sources/CodexBar/PreferencesProvidersPane.swift \
        Tests/CodexBarTests/CodexImportCurrentLoginTests.swift
git commit -m "feat(codex): add Import current login button in Preferences for Codex accounts"
```

---

## Task 6: Validation gates in the add-account UI *(collapsed from original Tasks 6+8)*

**Files:**
- Modify: `Sources/CodexBar/PreferencesProviderSettingsRows.swift` (inline validation + 6-account limit for `.codexOAuth`)

No new tests needed — `CodexOAuthAccountWriter.validate` and `limitedTokenAccounts` are already covered. This is UI-only wiring.

---

**Step 1: Validate on paste/type for codex**

In `ProviderSettingsTokenAccountsRowView`, where the token text field lives, add a `.onChange` modifier that calls `TokenAccountSupportCatalog.support(for: provider)?.injection == .codexOAuth` and runs `CodexOAuthAccountWriter.validate` live:

```swift
.onChange(of: newTokenText) { _, newValue in
    guard case .codexOAuth = TokenAccountSupportCatalog.support(for: descriptor.provider)?.injection else {
        tokenValidationError = nil
        return
    }
    do {
        try CodexOAuthAccountWriter.validate(jsonString: newValue)
        tokenValidationError = nil
    } catch let error as CodexOAuthAccountWriterError {
        tokenValidationError = error.errorDescription
    } catch {
        tokenValidationError = error.localizedDescription
    }
}
```

Show `tokenValidationError` as red `.footnote` text below the text field.

(Add `@State private var tokenValidationError: String? = nil` to the view's state.)

**Step 2: Enforce 6-account limit for Codex**

In the same view, disable the Add button at the limit (both validationError and atLimit must gate the button):

```swift
let atLimit = descriptor.accounts().count >= 6
    && (TokenAccountSupportCatalog.support(for: descriptor.provider)?.injection == .some(.codexOAuth))

Button("Add") { ... }
    .disabled(newTokenText.isEmpty || tokenValidationError != nil || atLimit)

if atLimit {
    Text("Maximum 6 Codex accounts. Remove one to add another.")
        .font(.footnote)
        .foregroundStyle(.secondary)
}
```

**Step 3: Build and smoke-test**

```bash
swift build 2>&1 | tail -20
```

Expected: clean build, no warnings about unhandled switch cases.

**Step 4: Commit**

```bash
git add Sources/CodexBar/PreferencesProviderSettingsRows.swift
git commit -m "feat(codex): add inline validation and 6-account limit in add-account UI"
```

---

## Task 7: Edge case — keychain auth detection

**Files:**
- Modify: `Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexCurrentLoginImporter.swift`

> **Note:** `CodexCurrentLoginImporter` lives in `Sources/CodexBarCore/Providers/Codex/CodexOAuth/` (not `Sources/CodexBar/`). The Core target contains all provider-specific logic; the app target contains UI wiring only.

When `~/.codex/auth.json` is missing because `cli_auth_credentials_store = "keyring"`, the Import button must show a helpful message rather than a generic "not found" error.

---

**Step 1: Write the test**

Add to `Tests/CodexBarTests/CodexImportCurrentLoginTests.swift`:

```swift
@Test("absent auth.json error message guides user to file-mode")
func absentAuthJSONMessageMentionsFileMode() {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("nonexistent-\(UUID().uuidString)")
    do {
        _ = try CodexCurrentLoginImporter.read(fromCodexHome: dir)
        Issue.record("Expected throw")
    } catch let error as CodexCurrentLoginImporterError {
        let msg = error.errorDescription ?? ""
        #expect(msg.contains("codex login") || msg.contains("auth.json"))
    } catch {
        Issue.record("Wrong error type: \(error)")
    }
}
```

**Step 2: Verify it passes** (existing `notFound` message already covers this)

```bash
swift test --filter CodexImportCurrentLoginTests 2>&1 | tail -10
```

**Step 3: Enhance the `notFound` message in `CodexCurrentLoginImporter`**

```swift
case .notFound:
    "No auth.json found. Set `cli_auth_credentials_store = \"file\"` in ~/.codex/config.toml, run `codex login`, then import."
```

**Step 4: Commit**

```bash
git add Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexCurrentLoginImporter.swift \
        Tests/CodexBarTests/CodexImportCurrentLoginTests.swift
git commit -m "fix(codex): improve auth.json-absent error to guide keychain users to file-mode"
```

---

## Task 8: Final integration — build, run, smoke test

**Step 1: Run the full test suite**

```bash
swift test 2>&1 | tail -30
```

Expected: all tests pass, 0 failures.

**Step 2: Build the app**

```bash
swift build 2>&1 | tail -20
```

Expected: clean build.

**Step 3: Manual smoke test checklist**

1. Open Preferences → Providers → Codex
2. Confirm "Codex accounts" section appears under Settings
3. Click "Import current login" → confirm it pre-fills the text field with your current auth.json
4. Give it a label (e.g. "Account A") → click Add
5. `codex login` with second account → return to Preferences → Import → label "Account B" → Add
6. In the Codex menu card, confirm account switcher pills appear (A / B)
7. Click "Account B" pill → confirm the switch happens without a browser window
8. In terminal: `codex login status` → verify it shows Account B's email
9. In Cursor/VS Code: open Codex panel → confirm Account B is active
10. Deplete Account B's quota → confirm macOS notification fires ("Codex session depleted")
11. Switch back to Account A → confirm notification fires ("Codex session restored")
12. Restart CodexBar → confirm Account B remains active (activeIndex persisted)

**Step 4: Final commit**

```bash
git add -A
git commit -m "feat(codex): complete multi-account support — import, switch, validate, cleanup"
```

---

## Edge Cases Summary

| # | Scenario | Handled in Task |
|---|---|---|
| Expired tokens in stored account | UI shows fetch error; user must re-import | Task 1 (validation) |
| auth.json write failure | `CodexAccountSwitcher.switchToAccount` throws → activeIndex NOT advanced; error banner shown in UI | Task 4 |
| Invalid/malformed JSON in token store | Blocked at add-time with inline error | Task 6 |
| External `codex login` overwrites auth.json | No conflict — stored accounts unaffected | Task 4 |
| App crash → stale temp dirs | `cleanupOnLaunch()` removes `~/.codex-bar-tmp` | Task 3 |
| Concurrent switch during fetch | Temp dirs isolate fetches; switch completes immediately | Task 3 |
| Keychain-stored credentials (no auth.json) | Import shows config.toml guidance | Task 7 |
| 6-account limit | Add button disabled with message | Task 6 |
| Single account | Switcher UI not shown (existing behavior) | n/a |
| Active account reconciliation on launch | File write only on explicit switch, not on startup | Task 4 |
