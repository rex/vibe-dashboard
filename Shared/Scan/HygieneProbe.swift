// HygieneProbe.swift — "classic vibe-coding shenanigans" a local scanner can catch.
//
// Content facts (merge-conflict markers, on-disk junk files) are gathered for free
// during the census file-walk and passed in. The git-aware facts (tracked secrets,
// committed dependency dirs, forgotten stashes) each cost a subprocess, kept to a
// tight, near-zero-false-positive set — alert fatigue is the enemy of this app.

import Foundation

enum HygieneProbe {
    static func probe(_ abs: String, conflicts: [String], junk: [String]) async -> Hygiene {
        var h = Hygiene()
        h.conflictFiles = conflicts
        h.junkFiles = junk

        // Secrets committed to git. Pull the tracked-file list and classify in Swift
        // (isTrackedSecret) — a pure, near-zero-false-positive call that catches modern
        // key material (id_ed25519, id_ecdsa, *.key, cloud credentials, service-account
        // keys) yet never flags a .env.example or a source file that merely mentions
        // "credentials". Managed repos have small trees, so listing all tracked files is
        // cheap; the classifier does the precise work git pathspecs used to.
        h.secretFiles = (await tracked(abs, [])).filter { rel in
            guard isTrackedSecret(rel) else { return false }
            // Credential rc-files are only a secret if they CONTAIN credentials —
            // an .npmrc holding just `engine-strict=true` must not cry wolf.
            guard isCredentialRcFile(rel) else { return true }
            let head = FileManager.default.contents(atPath: (abs as NSString).appendingPathComponent(rel))
                .map { String(decoding: $0.prefix(8192), as: UTF8.self) } ?? ""
            return rcFileLeaksCredentials(head)
        }

        // Dependency / build output committed to git — never belongs in a repo.
        let junkSpecs = [":(glob)**/node_modules/**", ":(glob)**/DerivedData/**", ":(glob)**/.venv/**",
                         ":(glob)**/.build/**", ":(glob)**/__pycache__/**", ":(glob)**/.DS_Store"]
        let trackedJunk = await tracked(abs, junkSpecs)
        h.trackedJunk = Array(Set(trackedJunk.map(topSegment))).sorted()

        // Forgotten work parked in the stash.
        let stash = await ProcessRunner.git(["stash", "list"], cwd: abs)
        h.stashCount = stash.stdout.split(separator: "\n").filter { !$0.isEmpty }.count
        return h
    }

    private static func tracked(_ abs: String, _ specs: [String]) async -> [String] {
        let r = await ProcessRunner.git(["ls-files", "--"] + specs, cwd: abs)
        guard r.ok else { return [] }
        return r.stdout.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    /// Is a tracked path a committed secret worth flagging? Pure + testable and tuned
    /// for near-zero false positives: key material is ALWAYS flagged; env / credential
    /// files are flagged unless they're an obvious example/template; and a source file
    /// that merely contains "credentials" in its name is NOT flagged.
    static func isTrackedSecret(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent.lowercased()
        // 1. Key material — always a secret. A private key is never an "example"
        //    (the v0.22 contract): extensions + the well-known SSH key basenames.
        for ext in ["pem", "key", "p12", "pfx", "keystore", "jks"] where name.hasSuffix("." + ext) { return true }
        if ["id_rsa", "id_dsa", "id_ed25519", "id_ecdsa"].contains(name) { return true }
        // 2. Env family — flagged unless it's a committed example/sample/template/dist.
        if name == ".env" || name.hasPrefix(".env.") || name.hasSuffix(".env") { return !isSafeExampleEnv(path) }
        // 3. Credential rc-files — flagged only when their CONTENT carries auth
        //    material (the probe does the read; see rcFileLeaksCredentials).
        if [".netrc", ".npmrc", ".pypirc"].contains(name) { return true }
        // 4. Cloud credentials + service-account keys (config-shaped, so example-guarded).
        return isCredentialFile(name)
    }

    /// Is this one of the rc-files whose secrecy depends on CONTENT? (.netrc /
    /// .npmrc / .pypirc are config files first; only auth entries make them secrets.)
    static func isCredentialRcFile(_ path: String) -> Bool {
        [".netrc", ".npmrc", ".pypirc"].contains((path as NSString).lastPathComponent.lowercased())
    }

    /// Does an rc-file's content actually carry credentials? Pure + testable — an
    /// `.npmrc` of `engine-strict=true` is configuration, not a leak; `_authToken=`,
    /// `password`, or a `.netrc` `machine … login … password …` block is.
    static func rcFileLeaksCredentials(_ content: String) -> Bool {
        let lower = content.lowercased()
        return ["_auth", "password", "token", "machine ", "login ", "api_key", "apikey"]
            .contains { lower.contains($0) }
    }

    /// Cloud-credential / service-account files. Bare `credentials` (no extension) is
    /// the classic ~/.aws/credentials shape; otherwise a config-ish extension is
    /// required so a `CredentialsManager.swift` source file can't cry wolf. Example /
    /// template variants are excluded.
    private static func isCredentialFile(_ lowerName: String) -> Bool {
        if lowerName == "credentials" { return true }
        if isExampleName(lowerName) { return false }
        let ext = (lowerName as NSString).pathExtension
        let configExts: Set<String> = ["json", "yaml", "yml", "ini", "cfg", "conf", "config",
                                       "properties", "toml", "txt", "csv", "xml"]
        if lowerName.hasPrefix("serviceaccount") || lowerName.hasPrefix("service-account")
            || lowerName.hasPrefix("service_account") { return ext == "json" }
        return lowerName.contains("credentials") && configExts.contains(ext)
    }

    /// A committed placeholder — `foo.example.json`, `bar-sample`, `baz.template`.
    private static func isExampleName(_ lowerName: String) -> Bool {
        let stem = (lowerName as NSString).deletingPathExtension
        return ["example", "sample", "template", "dist"].contains {
            lowerName.contains("." + $0) || stem.hasSuffix($0) || stem.hasSuffix("-" + $0) || stem.hasSuffix("_" + $0)
        }
    }

    /// Only `.env` VARIANTS named example/sample/template/dist are safe to commit.
    /// This exclusion must NOT apply to key material (*.pem, id_rsa, *.p12, keystores) —
    /// a private key is never an "example", so those are always flagged.
    private static func isSafeExampleEnv(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent.lowercased()
        guard name == ".env" || name.hasPrefix(".env.") || name.hasSuffix(".env") else { return false }
        return ["example", "sample", "template", "dist"].contains { name.hasSuffix($0) }
    }

    /// "node_modules/foo/bar.js" → "node_modules" (report the offending dir, not every file).
    private static func topSegment(_ path: String) -> String {
        for seg in path.split(separator: "/") where
            ["node_modules", "DerivedData", ".venv", ".build", "__pycache__"].contains(String(seg)) {
            return String(seg)
        }
        return (path as NSString).lastPathComponent   // e.g. a stray .DS_Store
    }

    // ---- filename-based junk detection, used by the census walk ----
    /// Agent / Finder cruft: `foo.orig`, `bar.bak`, editor swaps, "baz copy.swift".
    static func isJunkFile(_ name: String) -> Bool {
        let lower = name.lowercased()
        if lower.hasSuffix(".orig") || lower.hasSuffix(".bak") || lower.hasSuffix(".swp")
            || lower.hasSuffix(".tmp") || name.hasSuffix("~") { return true }
        let stem = (name as NSString).deletingPathExtension
        if stem.hasSuffix(" copy") { return true }
        if stem.range(of: " copy [0-9]+$", options: .regularExpression) != nil { return true }
        return false
    }

    /// Live merge-conflict markers left in a file — a genuine "agent gave up mid-merge".
    /// LINE-ANCHORED: git writes conflict markers at column 0, so both markers must
    /// start a line. A `"<<<<<<< HEAD\n…"` inside a STRING LITERAL (this app's own
    /// tests and this very file) sits mid-line and must never cry wolf — the scanner
    /// once flagged its own implementation.
    static func hasConflictMarkers(_ data: Data) -> Bool {
        atLineStart("<<<<<<< ", in: data) && atLineStart(">>>>>>> ", in: data)
    }

    private static func atLineStart(_ marker: String, in data: Data) -> Bool {
        let m = Data(marker.utf8)
        if data.prefix(m.count) == m { return true }
        return data.range(of: Data("\n".utf8) + m) != nil
    }
}
