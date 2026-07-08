import Testing
import Foundation
@testable import VibeDashboard

/// SCAN-CORE robustness. The pure decisions behind repo discovery, ownership, and
/// worktree identity must never make an owned repo INVISIBLE (the blind spot this
/// slice kills) and must give every worktree a stable, unique id. These pin the
/// URL normalizer, the owned-by-default rule, the push-only-mirror surfacing, and
/// the path-keyed worktree identity — all reachable without spawning git.
@Suite("Remote URL normalization")
struct RemoteIdentityTests {
    @Test("scp, ssh, and https forms of the same repo resolve to ONE owner")
    func ownerAcrossForms() {
        // The exact regression from the backlog: three spellings of `rex/x`, one owner.
        let scp = GitProbe.remoteIdentity("git@github.com:rex/x.git")
        let ssh = GitProbe.remoteIdentity("ssh://git@github.com/rex/x")
        let https = GitProbe.remoteIdentity("https://github.com/rex/x.git")
        #expect(scp?.owner == "rex")
        #expect(ssh?.owner == "rex")
        #expect(https?.owner == "rex")
        #expect(scp?.host == "github.com")
        #expect(ssh?.host == "github.com")
        #expect(https?.host == "github.com")
    }

    @Test("ownership is form-agnostic across every owned owner")
    func ownedFormAgnostic() {
        #expect(GitProbe.isOwnedRemoteURL("git@github.com:rex/x.git"))
        #expect(GitProbe.isOwnedRemoteURL("ssh://git@github.com/rex/x"))
        #expect(GitProbe.isOwnedRemoteURL("https://github.com/rex/x.git"))
        #expect(GitProbe.isOwnedRemoteURL("git@github.com:eye/thing"))
        #expect(GitProbe.isOwnedRemoteURL("https://github.com/widgets/svc.git"))
    }

    @Test("a self-hosted gitea remote is owned in any form")
    func giteaOwned() {
        #expect(GitProbe.isOwnedRemoteURL("git@git.example.com:dev/infra.git"))
        #expect(GitProbe.isOwnedRemoteURL("https://git.example.com/dev/infra"))
    }

    @Test("a foreign owner is NOT owned, and a near-miss prefix does not false-match")
    func foreignRejected() {
        #expect(!GitProbe.isOwnedRemoteURL("https://github.com/facebook/react.git"))
        #expect(!GitProbe.isOwnedRemoteURL("git@github.com:rexany/x.git"))   // 'rexany' ≠ 'rex'
        #expect(!GitProbe.isOwnedRemoteURL("https://gitlab.com/rex/x.git"))  // right owner, wrong host
        #expect(!GitProbe.isOwnedRemoteURL(""))
    }

    @Test("an ssh URL with an explicit port still recovers the owner")
    func sshWithPort() {
        #expect(GitProbe.remoteIdentity("ssh://git@github.com:22/rex/x.git")?.owner == "rex")
        #expect(GitProbe.remoteIdentity("ssh://git@github.com:22/rex/x.git")?.host == "github.com")
    }
}

@Suite("Owned-by-default for managed repos")
struct OwnershipDefaultTests {
    @Test("a MANAGED repo with NO remote is owned by default (never silently dropped)")
    func managedNoRemoteOwned() {
        #expect(FleetScanner.isOwnedRepo(remotes: [], managed: true))
    }

    @Test("an UNMANAGED repo with no owned remote is NOT owned")
    func unmanagedNotOwned() {
        let foreign = [Remote(name: "origin", host: "github", url: "https://github.com/facebook/react")]
        #expect(!FleetScanner.isOwnedRepo(remotes: foreign, managed: false))
        #expect(!FleetScanner.isOwnedRepo(remotes: [], managed: false))
    }

    @Test("an owned remote wins regardless of the managed flag or the URL form")
    func ownedRemoteWins() {
        let scp = [Remote(name: "origin", host: "github", url: "git@github.com:rex/x.git")]
        #expect(FleetScanner.isOwnedRepo(remotes: scp, managed: false))
    }
}

@Suite("Push-only owned mirror")
struct DisplayURLTests {
    @Test("when fetch is foreign but push is owned, the OWNED push URL surfaces")
    func ownedPushSurfaces() {
        let picked = GitProbe.displayURL(fetch: "https://github.com/facebook/react.git",
                                         push: "git@github.com:rex/react.git")
        #expect(picked == "git@github.com:rex/react.git")
        #expect(GitProbe.isOwnedRemoteURL(picked))
    }

    @Test("identical fetch/push keeps the fetch URL")
    func identicalKeepsFetch() {
        #expect(GitProbe.displayURL(fetch: "https://github.com/rex/x.git",
                                    push: "https://github.com/rex/x.git") == "https://github.com/rex/x.git")
    }

    @Test("a fetch-only remote uses its fetch URL; a push-only remote uses push")
    func singleSided() {
        #expect(GitProbe.displayURL(fetch: "https://github.com/rex/x.git", push: nil) == "https://github.com/rex/x.git")
        #expect(GitProbe.displayURL(fetch: nil, push: "git@github.com:rex/x.git") == "git@github.com:rex/x.git")
        #expect(GitProbe.displayURL(fetch: nil, push: nil).isEmpty)
    }
}

@Suite("Worktree identity")
struct WorktreeIdentityTests {
    @Test("two worktrees on the SAME branch have distinct ids (id is the path)")
    func pathKeyedId() {
        let a = Worktree(path: "/repo/wt-a", branch: "main", created: "—", lastCommit: "—", commits: 0, state: .active)
        let b = Worktree(path: "/repo/wt-b", branch: "main", created: "—", lastCommit: "—", commits: 0, state: .active)
        #expect(a.id != b.id)               // no ForEach id collision anymore
        #expect(a.id == "/repo/wt-a")
        #expect(a.branch == b.branch)       // same branch label, still unique identity
    }

    @Test("dirty defaults to false and is carried on the model")
    func dirtyField() {
        var wt = Worktree(path: "/repo/wt", branch: "x", created: "—", lastCommit: "—", commits: 0, state: .stale)
        #expect(!wt.dirty)
        wt.dirty = true
        #expect(wt.dirty)
    }
}

@Suite("parseWorktrees excludes main, records detached")
struct ParseWorktreesTests {
    @Test("the main worktree is dropped; a linked + a detached worktree survive")
    func mainExcludedDetachedKept() {
        let out = """
        worktree /repo
        HEAD aaaaaaaaaaaa
        branch refs/heads/main

        worktree /repo/wt-feature
        HEAD bbbbbbbbbbbb
        branch refs/heads/feature

        worktree /repo/wt-detached
        HEAD 0123456789abcdef
        detached

        """
        let pairs = GitProbe.parseWorktrees(out, repoAbs: "/repo")
        #expect(pairs.count == 2)
        #expect(pairs.contains { $0.path == "/repo/wt-feature" && $0.branch == "feature" })
        #expect(pairs.contains { $0.path == "/repo/wt-detached" && $0.branch == "detached@01234567" })
        #expect(!pairs.contains { $0.path == "/repo" })   // main worktree never listed
    }
}
