import Testing
@testable import VibeDashboard

/// The real in-app git *write* actions are the highest-risk surface in the app —
/// the moment it starts MUTATING repos. `GitWrite` is the single, pure place those
/// commands are shaped, deliberately free of any subprocess so the exact argument
/// vectors and the safety guard can be pinned here WITHOUT running git. A wrong or
/// missing flag (a stray `--force`, a dropped `-S`, a `--no-verify`) is a
/// catastrophic bug, so each invariant is asserted explicitly. These test the pure
/// builders/guards only — no real git is executed.
@Suite("git write command builders")
struct GitWriteBuilderTests {
    @Test("commit is signed by default: exactly [commit, -S, -m, msg]")
    func signedCommit() {
        #expect(GitWrite.commitArgs(message: "one logical step") == ["commit", "-S", "-m", "one logical step"])
    }

    @Test("an explicit unsigned commit drops -S but keeps -m <msg>")
    func unsignedCommit() {
        #expect(GitWrite.commitArgs(message: "wip", sign: false) == ["commit", "-m", "wip"])
    }

    @Test("commit NEVER passes --no-verify / -n (the pre-commit gate must run)")
    func commitNeverSkipsHooks() {
        for sign in [true, false] {
            let args = GitWrite.commitArgs(message: "x", sign: sign)
            #expect(!args.contains("--no-verify"))
            #expect(!args.contains("-n"))
        }
    }

    @Test("the commit message is used verbatim — spaces, quotes, and newlines survive")
    func messagePassedThrough() {
        let msg = "fix: don't \"swallow\" the message\n\nbody line"
        let args = GitWrite.commitArgs(message: msg)
        // -m and its value are adjacent, and the value is the EXACT message the user typed
        // (it used to be captured then silently discarded).
        guard let i = args.firstIndex(of: "-m") else { Issue.record("no -m flag"); return }
        #expect(args[args.index(after: i)] == msg)
    }

    @Test("add stages everything; push and hooks-path are the fixed skeleton commands")
    func fixedCommands() {
        #expect(GitWrite.addAllArgs == ["add", "-A"])
        #expect(GitWrite.pushArgs == ["push"])
        #expect(GitWrite.hooksPathArgs == ["config", "core.hooksPath", ".githooks"])
    }

    @Test("worktree remove is [worktree, remove, path] and NEVER --force / -f")
    func worktreeRemoveNeverForces() {
        let path = "/Users/x/Code/app/.worktrees/feature"
        let args = GitWrite.worktreeRemoveArgs(path: path)
        #expect(args == ["worktree", "remove", path])
        #expect(!args.contains("--force"))
        #expect(!args.contains("-f"))
    }

    @Test("a worktree path with spaces stays ONE argument (no shell splitting)")
    func worktreePathWithSpaces() {
        let path = "/Users/x/Code/my app/wt one"
        let args = GitWrite.worktreeRemoveArgs(path: path)
        #expect(args.count == 3)
        #expect(args.last == path)
    }
}

/// The commit-message gate — drives the disabled confirm button and refuses a no-op
/// commit. An empty message can never fire a commit.
@Suite("commit message gate")
struct CommitGateTests {
    @Test("blank / whitespace-only messages are not committable")
    func blankRejected() {
        #expect(!GitWrite.isCommittable(""))
        #expect(!GitWrite.isCommittable("   "))
        #expect(!GitWrite.isCommittable("\n\t "))
    }

    @Test("any message with real content is committable")
    func nonBlankAccepted() {
        #expect(GitWrite.isCommittable("x"))
        #expect(GitWrite.isCommittable("  trimmed to content  "))
    }
}

/// The worktree-prune SAFETY guard — the app's "unpushed = danger" stance in code:
/// unpushed/uncommitted work must never be silently destroyed, and ONLY abandoned
/// worktrees are ever prune candidates (a stale one can hold unpushed commits).
/// `PruneDecision` is a two-case enum, so `!= .remove` is exactly "refused".
@Suite("worktree prune guard")
struct PruneGuardTests {
    @Test("an abandoned, fully-pushed worktree is the ONLY case that removes")
    func abandonedCleanRemoves() {
        #expect(GitWrite.pruneDecision(state: .abandoned, unpushedCommits: 0) == .remove)
    }

    @Test("a DIRTY (unpushed) worktree is refused, even when abandoned")
    func dirtyAbandonedRefused() {
        #expect(GitWrite.pruneDecision(state: .abandoned, unpushedCommits: 3) != .remove)
    }

    @Test("a stale worktree is always refused — pushed or not")
    func staleRefused() {
        #expect(GitWrite.pruneDecision(state: .stale, unpushedCommits: 0) != .remove)
        #expect(GitWrite.pruneDecision(state: .stale, unpushedCommits: 9) != .remove)
    }

    @Test("an active worktree is never a prune candidate")
    func activeRefused() {
        #expect(GitWrite.pruneDecision(state: .active, unpushedCommits: 0) != .remove)
    }

    @Test("a refusal carries a human reason (it's surfaced to the user)")
    func refusalHasReason() {
        if case .refuse(let why) = GitWrite.pruneDecision(state: .abandoned, unpushedCommits: 2) {
            #expect(!why.isEmpty)
        } else {
            #expect(Bool(false), "abandoned+unpushed must refuse")
        }
    }

    @Test("exhaustive: only abandoned+clean removes — every other combination refuses")
    func exhaustive() {
        for state in [WorktreeLife.active, .stale, .abandoned] {
            for unpushed in [0, 1, 5] {
                let d = GitWrite.pruneDecision(state: state, unpushedCommits: unpushed)
                let shouldRemove = (state == .abandoned && unpushed == 0)
                #expect((d == .remove) == shouldRemove)
            }
        }
    }
}
