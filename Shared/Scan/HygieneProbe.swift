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

        // Secrets committed to git: .env (but never .env.example/.sample/.template),
        // private keys, keystores. Tracked, not just present on disk.
        let secretSpecs = [":(glob)**/.env", ":(glob).env", ":(glob)**/.env.*", ":(glob).env.*",
                           ":(glob)**/*.pem", ":(glob)**/id_rsa", ":(glob)**/id_dsa",
                           ":(glob)**/*.p12", ":(glob)**/*.pfx", ":(glob)**/*.keystore", ":(glob)**/*.jks"]
        h.secretFiles = (await tracked(abs, secretSpecs)).filter { !isEnvExample($0) }

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

    /// `.env.example` / `.env.sample` / `.env.template` / `.env.dist` are safe to commit.
    private static func isEnvExample(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent.lowercased()
        return ["example", "sample", "template", "dist", "md"].contains { name.hasSuffix($0) }
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
    static func hasConflictMarkers(_ data: Data) -> Bool {
        data.range(of: Data("<<<<<<< ".utf8)) != nil && data.range(of: Data(">>>>>>> ".utf8)) != nil
    }
}
