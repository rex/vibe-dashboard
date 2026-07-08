import Testing
import Foundation
@testable import VibeDashboard

/// Live-agent telemetry must be REAL or HONEST. These pin the two pure decisions
/// behind that: how a `ps` elapsed-time is humanized, and how a process command is
/// classified as a coding-agent session. Both are near-zero-false-positive by
/// design — a session card that lies (a collapsed "0h", a flagged log tail, a
/// flagged desktop app) is the bug this slice exists to kill.
@Suite("AgentProbe duration")
struct AgentProbeDurationTests {
    @Test("a 45-minute session is '45m', never a collapsed '0h'")
    func fortyFiveMinutes() {
        #expect(AgentProbe.humanize("45:00") == "45m")        // ps MM:SS
        #expect(AgentProbe.humanize("00:45:00") == "45m")     // ps HH:MM:SS with 0 hours
        #expect(AgentProbe.humanize("45:00") != "0h")
        #expect(AgentProbe.humanize("00:45:00") != "0h")
    }

    @Test("hours and minutes compose — a unit is dropped only when zero")
    func composesUnits() {
        #expect(AgentProbe.humanize("2:15:30") == "2h15m")    // drops the trailing seconds, keeps 15m
        #expect(AgentProbe.humanize("02:15:30") == "2h15m")   // leading zeros parse the same
        #expect(AgentProbe.humanize("1:00:00") == "1h")       // zero minutes → just "1h"
        #expect(AgentProbe.humanize("3-04:15:30") == "3d4h")  // D-HH:MM:SS
        #expect(AgentProbe.humanize("5-00:00:00") == "5d")    // zero hours → just "5d"
    }

    @Test("sub-minute and malformed inputs stay honest")
    func edges() {
        #expect(AgentProbe.humanize("00:30") == "30s")        // MM:SS, zero minutes → seconds
        #expect(AgentProbe.humanize("07") == "7s")            // single component
        #expect(AgentProbe.humanize("garbage") == "garbage")  // unparseable → raw, not a fake value
    }
}

@Suite("AgentProbe process match")
struct AgentProbeMatchTests {
    @Test("a real claude / claude-code / codex process IS flagged")
    func flagsRealAgents() {
        #expect(AgentProbe.matchTool(command: "claude") == "claude-code")
        #expect(AgentProbe.matchTool(command: "claude-code --resume abc123") == "claude-code")
        #expect(AgentProbe.matchTool(command: "/opt/homebrew/bin/claude --dangerously-skip-permissions") == "claude-code")
        #expect(AgentProbe.matchTool(command: "codex") == "codex")
        #expect(AgentProbe.matchTool(command: "/usr/local/bin/aider --model gpt") == "aider")
        #expect(AgentProbe.matchTool(command: "gemini") == "gemini")
        #expect(AgentProbe.matchTool(command: "opencode") == "opencode")
    }

    @Test("a log tail or a path containing 'claude' is NOT flagged")
    func rejectsSubstrings() {
        #expect(AgentProbe.matchTool(command: "tail -f claude.log") == nil)
        #expect(AgentProbe.matchTool(command: "/Users/dev/Code/claude-notes/x") == nil)
        #expect(AgentProbe.matchTool(command: "/Users/dev/claude-notes/run.sh") == nil)
        #expect(AgentProbe.matchTool(command: "vim claude.md") == nil)
        #expect(AgentProbe.matchTool(command: "grep -r claude .") == nil)
    }

    @Test("the Claude.app / Codex.app GUI processes are NOT flagged")
    func rejectsDesktopApps() {
        // These are real `ps` lines on a Mac running the desktop apps — the naive
        // substring/anchored-regex approaches both wrongly flag them (basename
        // "Claude"/"codex"), so the `.app/` bundle guard is load-bearing.
        #expect(AgentProbe.matchTool(command: "/Applications/Claude.app/Contents/MacOS/Claude") == nil)
        #expect(AgentProbe.matchTool(command: "/Applications/Codex.app/Contents/Resources/codex app-server --analytics-default-enabled") == nil)
        #expect(AgentProbe.matchTool(command: "./Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient mcp") == nil)
    }
}

/// The live-session signal now comes from the transcript's real `cwd`, not `ps` — this
/// is what makes detection work for node/SDK/headless Claude Code (the "broken" bug).
@Suite("transcript cwd extraction")
struct TranscriptCwdTests {
    @Test("cwd is pulled from a real Claude Code transcript first line")
    func extractsCwd() {
        let head = #"{"type":"assistant","cwd":"/Users/dev/Code/__APPS/macOS/vibe-dashboard","sessionId":"abc","message":{"content":[]}}"#
        #expect(AgentProbe.extractJSONString(head, key: "cwd") == "/Users/dev/Code/__APPS/macOS/vibe-dashboard")
    }

    @Test("timestamp is extractable; a missing key returns nil, not a crash")
    func extractsTimestampAndMissing() {
        let head = #"{"cwd":"/x/y","timestamp":"2026-07-08T05:50:56Z"}"#
        #expect(AgentProbe.extractJSONString(head, key: "timestamp") == "2026-07-08T05:50:56Z")
        #expect(AgentProbe.extractJSONString(head, key: "gitBranch") == nil)   // absent ⇒ nil
        #expect(AgentProbe.extractJSONString("not json at all", key: "cwd") == nil)
    }

    @Test("session lifecycle: active <15m, idle <1h, complete (nil) after")
    func lifecycleWindows() {
        #expect(AgentProbe.lifecycle(age: -5) == .active)          // clock skew / future mtime
        #expect(AgentProbe.lifecycle(age: 60) == .active)          // 1 min
        #expect(AgentProbe.lifecycle(age: 14 * 60) == .active)     // 14 min
        #expect(AgentProbe.lifecycle(age: 15 * 60) == .idle)       // exactly 15 min → idle
        #expect(AgentProbe.lifecycle(age: 45 * 60) == .idle)       // 45 min
        #expect(AgentProbe.lifecycle(age: 60 * 60) == nil)         // exactly 1h → complete (dropped)
        #expect(AgentProbe.lifecycle(age: 3 * 3600) == nil)        // long done
    }
}
