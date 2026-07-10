// OwnerScope.swift — optional "repos I own" scoping for the fleet.
//
// The scanner can narrow the fleet to repos whose git remote you own — your
// self-hosted git hosts and/or your GitHub orgs. This is OFF by default (empty):
// with no scope set, every managed repo under the scan root is kept (a managed
// repo is owned-by-default), and you scope instead with the scan root + ignore
// list. To turn it on, drop a JSON file at:
//
//   ~/Library/Application Support/VibeDashboard/owner-scope.json
//
//   { "hosts": ["gitea", "git.example.com"], "githubOwners": ["your-org"] }
//
// It's read once at launch and never committed — keep your own hosts/orgs there,
// out of the source tree.

import Foundation

struct OwnerScope: Sendable, Codable {
    /// Remote-host substrings you own (matched with `contains`), e.g. "gitea".
    var hosts: [String] = []
    /// GitHub org/user names you own (exact match), e.g. "your-org".
    var githubOwners: [String] = []

    var isEmpty: Bool { hosts.isEmpty && githubOwners.isEmpty }

    /// Loaded once from Application Support; empty (no owner filter) if absent.
    static let current: OwnerScope = load()

    static func load() -> OwnerScope {
        let path = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Application Support/VibeDashboard/owner-scope.json")
        guard let data = FileManager.default.contents(atPath: path),
              let scope = try? JSONDecoder().decode(OwnerScope.self, from: data)
        else { return OwnerScope() }
        return scope
    }
}
