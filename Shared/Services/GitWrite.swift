// GitWrite.swift — pure, testable builders for the app's real git *write* commands.

import Foundation

/// The ONLY place the app's real git *write* commands are shaped. Deliberately
/// free of any subprocess execution so the exact argument vectors and the safety
/// guard can be unit-tested without touching a real repo (see GitWriteTests). The
/// hard-safety invariants live here: commits are signed by default and never
/// `--no-verify`, worktree removal NEVER passes `--force`, and only an abandoned +
/// fully-pushed worktree may be pruned automatically.
enum GitWrite {
    /// `git add -A` — stage every change.
    static let addAllArgs = ["add", "-A"]
    /// `git push` — to the configured upstream.
    static let pushArgs = ["push"]
    /// `git config core.hooksPath .githooks` — the skeleton's `make install-hooks`.
    static let hooksPathArgs = ["config", "core.hooksPath", ".githooks"]

    /// `git commit [-S] -m <message>`. Signed by default to honor a repo's signing
    /// setup; never `--no-verify`, so the pre-commit gate always runs.
    static func commitArgs(message: String, sign: Bool = true) -> [String] {
        sign ? ["commit", "-S", "-m", message] : ["commit", "-m", message]
    }

    /// `git worktree remove <path>` — WITHOUT `--force`. A dirty worktree makes
    /// plain remove fail loudly (the safe outcome); we never silently destroy it.
    static func worktreeRemoveArgs(path: String) -> [String] {
        ["worktree", "remove", path]
    }

    /// Is a commit message non-blank (after trimming)? The confirm button is
    /// disabled — and the commit refused — when this is false.
    static func isCommittable(_ message: String) -> Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether a single worktree may be pruned. ONLY `.abandoned` worktrees are
    /// eligible (a `.stale` one can still hold unpushed commits); an abandoned one
    /// that carries unpushed commits is refused too, so real work is never lost.
    enum PruneDecision: Equatable { case remove; case refuse(String) }
    static func pruneDecision(state: WorktreeLife, unpushedCommits: Int) -> PruneDecision {
        switch state {
        case .active: return .refuse("worktree is active — not a prune candidate")
        case .stale:  return .refuse("stale, not abandoned — may hold unpushed work")
        case .abandoned:
            if unpushedCommits > 0 {
                return .refuse("\(unpushedCommits) unpushed commit\(unpushedCommits == 1 ? "" : "s") — push or remove by hand")
            }
            return .remove
        }
    }
}
