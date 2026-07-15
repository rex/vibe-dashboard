import Testing
@testable import VibeDashboard

@Suite("fleet-wide agent scope")
struct FleetAgentScopeTests {
    @Test("VIBE-only policy filtering does not suppress live agents")
    func uninstrumentedLiveRepoRemainsInAgentScope() {
        var instrumented = Repo(id: "instrumented", name: "instrumented", path: "~/Code/instrumented",
                                absolutePath: "/Users/dev/Code/instrumented")
        instrumented.vibePresent = true
        var uninstrumented = Repo(id: "plain", name: "plain", path: "~/Code/plain",
                                  absolutePath: "/Users/dev/Code/plain")
        uninstrumented.agents = [AgentInfo(id: "codex:live", active: true, tool: "codex")]

        let scoped = FleetStore.agentSessionRepos([instrumented, uninstrumented],
                                                  ignoredIds: [], showIgnored: false)
        #expect(Fleet.sessions(for: scoped).map(\.repo.id) == ["plain"])
    }

    @Test("explicitly ignored repos remain absent from fleet-wide agent scope")
    func ignoredRepoIsExcludedUnlessRevealed() {
        var repo = Repo(id: "ignored", name: "ignored", path: "~/Code/ignored",
                        absolutePath: "/Users/dev/Code/ignored")
        repo.agents = [AgentInfo(id: "codex:live", active: true, tool: "codex")]

        let hidden = FleetStore.agentSessionRepos([repo], ignoredIds: [repo.id], showIgnored: false)
        let shown = FleetStore.agentSessionRepos([repo], ignoredIds: [repo.id], showIgnored: true)
        #expect(Fleet.sessions(for: hidden).isEmpty)
        #expect(Fleet.sessions(for: shown).map(\.repo.id) == [repo.id])
    }
}
