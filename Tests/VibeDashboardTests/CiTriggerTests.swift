import Testing
import Foundation
@testable import VibeDashboard

/// CI triggers and container checks must be READ from each repo's own files —
/// never fabricated. Before this slice every workflow was stamped with a hardcoded
/// `trigger: "push · pull_request"` and a canned `grade: "B"`; every compose file
/// got a canned "B" plus one always-true "compose file present" check. These pin
/// the honest replacement: a `schedule:`-only workflow reads "schedule", an
/// unreadable file reads "—", and a compose grade reflects real checks.
@Suite("CI trigger parse")
struct CiTriggerTests {
    /// Writes throwaway files under a unique temp dir and returns the dir path.
    private func tempRepo(_ files: [String: String]) -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ci-trigger-" + UUID().uuidString)
        for (rel, body) in files {
            let url = dir.appendingPathComponent(rel)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? body.write(to: url, atomically: true, encoding: .utf8)
        }
        return dir.path
    }
    /// Writes a single workflow file and returns its absolute path.
    private func workflow(_ yaml: String) -> String {
        let repo = tempRepo([".github/workflows/wf.yml": yaml])
        return (repo as NSString).appendingPathComponent(".github/workflows/wf.yml")
    }

    /// The required case: an `on:` block that is only `schedule:` must read
    /// "schedule" — never the old hardcoded "push · pull_request".
    @Test("a schedule-only `on:` block parses to \"schedule\", not the old fake")
    func scheduleOnly() {
        let yaml = """
        name: Nightly
        on:
          schedule:
            - cron: "0 3 * * *"
        jobs:
          build:
            runs-on: ubuntu-latest
            steps:
              - run: echo hi
        """
        let repo = tempRepo([".github/workflows/nightly.yml": yaml])
        let path = (repo as NSString).appendingPathComponent(".github/workflows/nightly.yml")

        // Direct parse …
        #expect(DeriveIntegrations.workflowTrigger(path) == "schedule")
        #expect(DeriveIntegrations.workflowTrigger(path) != "push · pull_request")

        // … and end-to-end through ci().
        let ci = DeriveIntegrations.ci(repo, stack: "swift")
        #expect(ci.workflows.first?.trigger == "schedule")
        #expect(ci.workflows.first?.trigger != "push · pull_request")
    }

    /// The YAML 1.1 footgun: a bare `on:` mapping key resolves to Bool(`true`),
    /// so a naive `dict["on"]` misses it. The parser must still find the events.
    @Test("a bare `on:` mapping key (YAML resolves to true) is still found")
    func boolKeyFootgun() {
        let yaml = """
        on:
          push:
            branches: [main]
          pull_request:
        """
        #expect(DeriveIntegrations.workflowTrigger(workflow(yaml)) == "push · pull_request")
    }

    @Test("sequence and scalar `on:` forms parse and sort canonically")
    func sequenceAndScalar() {
        #expect(DeriveIntegrations.workflowTrigger(workflow("on: [pull_request, push]")) == "push · pull_request")
        #expect(DeriveIntegrations.workflowTrigger(workflow("on: push")) == "push")
        #expect(DeriveIntegrations.workflowTrigger(workflow("on: [release, workflow_dispatch]")) == "workflow_dispatch · release")
    }

    @Test("an unreadable or `on:`-less file is an honest dash, never a fabricated trigger")
    func honestUnknown() {
        #expect(DeriveIntegrations.workflowTrigger("/no/such/path/wf.yml") == "—")
        #expect(DeriveIntegrations.workflowTrigger(workflow("name: NoTriggers\njobs: {}")) == "—")
    }

    @Test("ci() wires real triggers and refuses to invent a run status or grade")
    func ciEndToEnd() {
        let repo = tempRepo([
            ".github/workflows/ci.yml": "on: [push]",
            ".github/workflows/release.yml": "on:\n  release:\n    types: [published]",
        ])
        let ci = DeriveIntegrations.ci(repo, stack: "swift")
        #expect(ci.configured)
        #expect(ci.provider == "github-actions")
        #expect(ci.grade == "n/a")                       // no fabricated letter
        let byName = Dictionary(uniqueKeysWithValues: ci.workflows.map { ($0.name, $0) })
        #expect(byName["ci.yml"]?.trigger == "push")
        #expect(byName["release.yml"]?.trigger == "release")
        #expect(ci.workflows.allSatisfy { $0.status == .skip && $0.last == "—" })  // honestly unmeasured
    }
}

/// The `on:`-value normaliser, unit-tested without touching disk.
@Suite("trigger event normalisation")
struct TriggerEventTests {
    @Test("map keys are de-duped and canonically ordered")
    func mapOrdering() {
        let value: [AnyHashable: Any] = ["pull_request": 1, "push": 1, "schedule": 1]
        #expect(DeriveIntegrations.triggerEvents(from: value) == ["push", "pull_request", "schedule"])
    }
    @Test("unknown events sort after known ones, alphabetically")
    func unknownEvents() {
        #expect(DeriveIntegrations.triggerEvents(from: ["zeta", "push", "alpha"]) == ["push", "alpha", "zeta"])
    }
    @Test("a nil or empty `on:` yields no events")
    func emptyish() {
        #expect(DeriveIntegrations.triggerEvents(from: nil).isEmpty)
        #expect(DeriveIntegrations.triggerEvents(from: [String]()).isEmpty)
    }
}

/// Compose grading must come from the file's real contents, not a canned "B"
/// plus an always-true "compose file present" check.
@Suite("compose checks")
struct ComposeCheckTests {
    private func composeItem(_ yaml: String) -> ContainerItem {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("compose-" + UUID().uuidString)
        let path = dir.appendingPathComponent("docker-compose.yml")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? yaml.write(to: path, atomically: true, encoding: .utf8)
        return DeriveIntegrations.composeItem(path.path)
    }

    @Test("a pinned service with restart + healthcheck grades A on real checks")
    func cleanCompose() {
        let item = composeItem("""
        services:
          web:
            image: nginx:1.25
            restart: unless-stopped
            healthcheck:
              test: ["CMD", "curl", "-f", "http://localhost/"]
        """)
        #expect(item.grade == "A")
        #expect(item.checks.contains { $0.ok && $0.text.contains("pinned") })
        #expect(item.checks.allSatisfy { $0.text != "compose file present" })   // the old fake is gone
    }

    @Test("an unpinned :latest image is caught, and the grade is computed not canned")
    func unpinned() {
        let item = composeItem("""
        services:
          web:
            image: nginx:latest
            restart: always
            healthcheck:
              test: ["CMD", "true"]
        """)
        #expect(item.checks.contains { !$0.ok && $0.text.contains("unpinned") })
        #expect(item.grade == "B")   // exactly 1 real fail → B, derived from contents
    }

    @Test("`restart: \"no\"` is the no-restart default and must not be over-credited")
    func restartNoIsNotAPolicy() {
        let item = composeItem("""
        services:
          web:
            image: redis:7
            restart: "no"
        """)
        #expect(item.checks.contains { !$0.ok && $0.text.contains("restart") })
    }

    @Test("a compose we can't assess (no services) is honestly \"n/a\", never a canned letter")
    func unassessable() {
        let item = composeItem("version: \"3.9\"\nvolumes:\n  data:")
        #expect(item.grade == "n/a")
        #expect(item.checks.isEmpty)
    }
}
