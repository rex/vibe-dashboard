// GradeFactorTests.swift — the severity-weighted grade: proportional deductions,
// critical overrides, caps, and the factor↔score↔health agreement invariant.

import Testing
import Foundation
@testable import VibeDashboard

@Suite("severity-weighted grading")
struct GradeFactorTests {
    private func repo(_ mutate: (inout Repo) -> Void = { _ in }) -> Repo {
        var r = Repo(id: "t", name: "t", path: "~/t", absolutePath: "/t")
        r.management = .skeleton
        mutate(&r)
        return r
    }
    private func guardrail() -> Hook {
        Hook(src: "claude", event: "PreToolUse", command: "guard.sh", status: .active)
    }

    @Test("a pristine repo has zero factors, 100, ok")
    func cleanBill() {
        let f = Derive.factors(repo(), signedRequired: false)
        #expect(f.isEmpty)
        #expect(Derive.score(f) == 100)
        #expect(Derive.healthBand(f) == .ok)
    }

    @Test("a single dirty file is WARN with one visible reason — never danger")
    func singleDirtyFileIsWarn() {
        let f = Derive.factors(repo { $0.worktree.clean = false; $0.worktree.unstaged = 1 },
                               signedRequired: false)
        #expect(f.map(\.delta) == [-8])
        #expect(f[0].label == "1 uncommitted file")
        #expect(Derive.score(f) == 92)
        #expect(Derive.healthBand(f) == .warn)
    }

    @Test("dirty scales with size and is halved while an agent is mid-work")
    func dirtyProportional() {
        let big = Derive.factors(repo { $0.worktree.clean = false; $0.worktree.unstaged = 30 },
                                 signedRequired: false)
        #expect(big.first?.delta == -20)

        let live = Derive.factors(repo {
            $0.worktree.clean = false; $0.worktree.unstaged = 30
            $0.agent = AgentInfo(active: true)
            $0.hooks = [guardrail()]          // guarded, so no critical fires
        }, signedRequired: false)
        let dirty = live.first { $0.label.contains("uncommitted") }
        #expect(dirty?.delta == -10)
        #expect(dirty?.label.contains("agent mid-work") == true)
    }

    @Test("criticals force danger even when the score alone would not")
    func criticalForcesDanger() {
        let f = Derive.factors(repo { $0.hygiene.secretFiles = ["/t/.env"] },
                               signedRequired: false)
        #expect(Derive.score(f) == 75)             // score says warn…
        #expect(Derive.healthBand(f) == .danger)   // …but a tracked secret is always red
        #expect(f.first?.critical == true)
    }

    @Test("an unguarded live agent is critical; a guarded one adds nothing")
    func guardrailCritical() {
        let unguarded = Derive.factors(repo { $0.agent = AgentInfo(active: true) },
                                       signedRequired: false)
        #expect(unguarded.contains { $0.critical && $0.label.contains("guardrail") })
        let guarded = Derive.factors(repo {
            $0.agent = AgentInfo(active: true); $0.hooks = [guardrail()]
        }, signedRequired: false)
        #expect(guarded.isEmpty)
    }

    @Test("god-file deduction caps at three files")
    func godFileCap() {
        let files = (0..<10).map { FileLines(path: "f\($0).swift", lines: 500) }
        let f = Derive.factors(repo { $0.census.godFiles = files }, signedRequired: false)
        let gods = f.first { $0.label.contains("god-file") }
        #expect(gods?.delta == -24)
        #expect(gods?.tone == .danger)
    }

    @Test("compounding real problems reach danger through the score")
    func compoundingReachesDanger() {
        let f = Derive.factors(repo {
            $0.worktree.clean = false; $0.worktree.unstaged = 12   // -20
            $0.worktree.unpushed = 5                               // -12
            $0.census.godFiles = (0..<3).map { FileLines(path: "f\($0)", lines: 500) }  // -24
        }, signedRequired: false)
        #expect(!f.contains { $0.critical })
        #expect(Derive.score(f) == 44)
        #expect(Derive.healthBand(f) == .danger)
    }

    @Test("compliance and health are computed FROM the factors — they can't disagree")
    func factorsAreTheGrade() {
        let r = repo { $0.worktree.clean = false; $0.worktree.unstaged = 2; $0.drift.behind = "2 minor" }
        let f = Derive.factors(r, signedRequired: false)
        #expect(Derive.compliance(r, signedRequired: false) == Derive.score(f))
        #expect(Derive.health(r, signedRequired: false) == Derive.healthBand(f))
    }

    @Test("a waived finding removes its factor — grade and feed agree")
    func waiversRemoveWeight() {
        let r = repo { $0.hygiene.secretFiles = ["/t/.npmrc"] }
        let finding = Finding(severity: .high, pass: "Hygiene",
                              what: "secret tracked in git: .npmrc", why: "", fix: nil)
        let waived = Derive.WaivedFacts.parse([finding])
        #expect(waived.secrets)
        let f = Derive.factors(r, signedRequired: false, waived: waived)
        #expect(f.isEmpty)
        #expect(Derive.score(f) == 100)
        #expect(Derive.healthBand(f) == .ok)
    }

    @Test("waived god-files stop counting; unwaived ones still do")
    func waivedGodFilePartial() {
        let r = repo { $0.census.godFiles = [FileLines(path: "a.swift", lines: 500),
                                             FileLines(path: "b.swift", lines: 600)] }
        let waived = Derive.WaivedFacts.parse([
            Finding(severity: .med, pass: "Census", what: "god-file: a.swift", why: "", fix: nil),
        ])
        let f = Derive.factors(r, signedRequired: false, waived: waived)
        #expect(f.first?.label == "1 god-file")
        #expect(f.first?.delta == -8)
    }

    @Test("dirty waiver text parses despite containing 'committed'")
    func waivedFactsParseOrder() {
        let w = Derive.WaivedFacts.parse([
            Finding(severity: .high, pass: "Worktree", what: "3 uncommitted changes", why: "", fix: nil),
        ])
        #expect(w.dirty && !w.trackedJunk)
    }
}

@Suite("hygiene rc-file content gate")
struct RcSecretTests {
    @Test("an .npmrc of pure config is not a secret; auth entries are")
    func npmrcContent() {
        #expect(!HygieneProbe.rcFileLeaksCredentials("engine-strict=true\nregistry=https://r.example\n"))
        #expect(HygieneProbe.rcFileLeaksCredentials("//registry.npmjs.org/:_authToken=npm_abc123"))
        #expect(HygieneProbe.rcFileLeaksCredentials("machine github.com login me password hunter2"))
        #expect(HygieneProbe.isCredentialRcFile("/x/.npmrc"))
        #expect(!HygieneProbe.isCredentialRcFile("/x/.env"))
    }
}

@Suite("agent refresh change gating")
struct AgentChangeGateTests {
    private func info(_ id: String, at: Date, files: Int = 0) -> AgentInfo {
        var a = AgentInfo(); a.id = id; a.lastActivityAt = at; a.filesTouched = files; return a
    }

    @Test("pure timestamp drift under a minute is NOT a meaningful change")
    func timestampDriftIgnored() {
        let t = Date(timeIntervalSince1970: 1_000_000)
        let old = [info("s1", at: t)]
        #expect(!FleetStore.agentsMeaningfullyDiffer(old, [info("s1", at: t.addingTimeInterval(20))]))
        #expect(FleetStore.agentsMeaningfullyDiffer(old, [info("s1", at: t.addingTimeInterval(90))]))
        #expect(FleetStore.agentsMeaningfullyDiffer(old, [info("s2", at: t)]))
        #expect(FleetStore.agentsMeaningfullyDiffer(old, [info("s1", at: t, files: 3)]))
        #expect(FleetStore.agentsMeaningfullyDiffer(old, []))
    }
}
