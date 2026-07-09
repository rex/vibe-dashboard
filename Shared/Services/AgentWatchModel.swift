// AgentWatchModel.swift — the observable model behind one agent watch window.
//
// Owns pane discovery (a workflow's agent transcripts, a session's live subagents)
// and the poll loop that advances each pane's incremental tail. All file IO runs
// off the main actor; the UI reads `panes` and re-renders only when a cheap
// fingerprint says something actually changed.

import Foundation

/// One column in the watch window — a single transcript being tailed.
struct WatchPane: Identifiable, Sendable, Hashable {
    var id: String { path }
    var path: String
    var title: String
    var badge: String?            // agentType / provider label
    var isMain = false            // the session's own transcript (leads the pane order)
    var order: Int = .max         // journal spawn order (workflow agents)
    var phase: Int = 0            // workflow phase group (0 = main/unphased)
    var done = false              // journal recorded a result for this agent
    var outcome: String? = nil    // the recorded result payload (pretty, clipped)
    var tail = WatchTailState()

    var firstEventAt: Date? { tail.events.first(where: { $0.timestamp != nil })?.timestamp }
    var lastEventAt: Date? { tail.events.last(where: { $0.timestamp != nil })?.timestamp }
    func isStreaming(now: Date) -> Bool {
        guard !done, let g = tail.lastGrowth else { return false }
        return now.timeIntervalSince(g) < 20
    }
}

@MainActor
@Observable
final class AgentWatchModel {
    private(set) var panes: [WatchPane] = []
    private(set) var now = Date()
    let target: AgentWatchTarget

    private var loop: Task<Void, Never>?
    private var fingerprint = ""
    private var tickCount = 0

    init(target: AgentWatchTarget) { self.target = target }

    func start(interval: TimeInterval = 0.7) {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }
    func stop() { loop?.cancel(); loop = nil }

    private func tick() async {
        let target = self.target
        let snapshot = panes
        let discover = tickCount % 4 == 0    // re-list agent files every ~3s; tail every tick
        tickCount += 1
        let updated = await Task.detached(priority: .utility) {
            Self.compute(target: target, panes: snapshot, discover: discover, now: Date())
        }.value
        now = Date()
        let fp = Self.fingerprint(updated)
        if fp != fingerprint {
            fingerprint = fp
            panes = updated
        }
    }

    /// Cheap change detector — avoids replacing (and re-diffing) hundreds of event
    /// rows when a tick found nothing new.
    nonisolated static func fingerprint(_ panes: [WatchPane]) -> String {
        panes.map { "\($0.path):\($0.tail.offset):\($0.tail.seq):\($0.done ? 1 : 0)" }
            .joined(separator: "|")
    }

    // MARK: - Off-main tick body (pure functions of the filesystem)

    nonisolated static func compute(target: AgentWatchTarget, panes: [WatchPane],
                                    discover: Bool, now: Date) -> [WatchPane] {
        var list = discover || panes.isEmpty ? discoverPanes(target: target, existing: panes) : panes
        for i in list.indices {
            list[i].tail = WatchTailer.advance(path: list[i].path, state: list[i].tail, now: now)
        }
        return assignPhases(sortPanes(list))
    }

    /// Enumerate the transcripts this target implies. Existing panes keep their tail
    /// state; files that appear mid-watch (the workflow spawning its next agent, a
    /// session forking a subagent) become new panes — the "hop" Pierce asked for.
    nonisolated static func discoverPanes(target: AgentWatchTarget,
                                          existing: [WatchPane]) -> [WatchPane] {
        let byPath = Dictionary(uniqueKeysWithValues: existing.map { ($0.path, $0) })
        var out: [WatchPane] = []

        func add(path: String, title: String, badge: String?, isMain: Bool,
                 order: Int, done: Bool, outcome: String?) {
            var pane = byPath[path] ?? WatchPane(path: path, title: title, badge: badge)
            pane.title = title; pane.badge = badge; pane.isMain = isMain
            pane.order = order; pane.done = done; pane.outcome = outcome
            out.append(pane)
        }

        switch target.kind {
        case .workflow:
            let dir = (target.transcriptPath as NSString).deletingLastPathComponent
            let journal = WatchJournal.read(dir: dir)
            for path in agentFiles(in: dir) {
                let agentId = agentId(of: path)
                let meta = WatchAgentMeta.read(transcriptPath: path)
                add(path: path,
                    title: meta.description ?? "agent \(agentId.prefix(7))",
                    badge: meta.agentType,
                    isMain: false,
                    order: journal.startOrder.firstIndex(of: agentId) ?? .max,
                    done: journal.results[agentId] != nil,
                    outcome: journal.results[agentId])
            }
            if out.isEmpty {   // journal/dir unreadable — at least tail the target itself
                add(path: target.transcriptPath, title: "agent", badge: target.tool,
                    isMain: false, order: 0, done: false, outcome: nil)
            }
        case .standard where target.tool == "claude-code":
            add(path: target.transcriptPath, title: target.repoName, badge: target.tool,
                isMain: true, order: -1, done: false, outcome: nil)
            for path in recentSubagentFiles(mainTranscript: target.transcriptPath) {
                let meta = WatchAgentMeta.read(transcriptPath: path)
                add(path: path,
                    title: meta.description ?? "subagent \(agentId(of: path).prefix(7))",
                    badge: meta.agentType ?? "subagent",
                    isMain: false, order: .max, done: false, outcome: nil)
            }
        default:
            add(path: target.transcriptPath, title: target.repoName, badge: target.tool,
                isMain: true, order: -1, done: false, outcome: nil)
        }
        return out
    }

    nonisolated static func agentFiles(in dir: String) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return names.filter { $0.hasPrefix("agent-") && $0.hasSuffix(".jsonl") }
            .sorted().map { (dir as NSString).appendingPathComponent($0) }
    }

    nonisolated static func agentId(of path: String) -> String {
        let base = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        return base.hasPrefix("agent-") ? String(base.dropFirst("agent-".count)) : base
    }

    /// A live session's own Agent-tool subagents: `<sessionDir>/subagents/agent-*.jsonl`
    /// with recent activity (file mtime inside the session retention window). Workflow
    /// transcripts live deeper (`subagents/workflows/…`) and are watched via their own
    /// workflow card — not duplicated here.
    nonisolated static func recentSubagentFiles(mainTranscript: String,
                                                now: Date = Date()) -> [String] {
        let sessionDir = (mainTranscript as NSString).deletingPathExtension
        let dir = (sessionDir as NSString).appendingPathComponent("subagents")
        return agentFiles(in: dir).filter { path in
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                  let m = attrs[.modificationDate] as? Date else { return false }
            return now.timeIntervalSince(m) < AgentProbe.retentionWindow
        }
    }

    /// Main pane first, then journal spawn order, then first activity, then path —
    /// a stable order that never reshuffles panes mid-watch.
    nonisolated static func sortPanes(_ panes: [WatchPane]) -> [WatchPane] {
        panes.sorted { a, b in
            if a.isMain != b.isMain { return a.isMain }
            if a.order != b.order { return a.order < b.order }
            let fa = a.firstEventAt ?? .distantFuture, fb = b.firstEventAt ?? .distantFuture
            if fa != fb { return fa < fb }
            return a.path < b.path
        }
    }

    /// Workflow phase grouping: agents whose first activity starts > `gap` apart are
    /// different phases (parallel waves start within milliseconds of each other). The
    /// divider between phases is the visual "hop" marker.
    nonisolated static func assignPhases(_ panes: [WatchPane],
                                         gap: TimeInterval = 5) -> [WatchPane] {
        var out = panes
        var phase = 0
        var previous: Date?
        for i in out.indices {
            guard !out[i].isMain else { out[i].phase = 0; continue }
            let first = out[i].firstEventAt
            if let f = first {
                if let p = previous, f.timeIntervalSince(p) > gap { phase += 1 }
                else if previous == nil { phase = max(phase, 1) }
                previous = f
            }
            out[i].phase = max(phase, 1)
        }
        return out
    }
}
