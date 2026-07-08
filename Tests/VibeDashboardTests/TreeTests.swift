import Testing
import Foundation
@testable import VibeDashboard

/// The sidebar's whole QOL rewrite hinges on `Fleet.buildSidebarTree` deriving the
/// real filesystem shape from repo absolute paths: plain grouping dirs become inert
/// `group` nodes, real workspaces stay selectable `repo` nodes and nest recursively
/// to any depth, and no absolute path is ever emitted twice. These are pinned here so
/// a regression in the tree builder can't quietly reintroduce the "listed twice" /
/// "won't expand past level 2" / "clickable folders" bugs it was written to kill.
@Suite("Sidebar filesystem tree")
struct TreeTests {

    /// A repo at `path`. `workspace: true` marks a WORKSPACE.yaml workspace. The id is
    /// path-derived (unique per path) exactly like the real scanner's `idFor`.
    private func mk(_ path: String, workspace: Bool = false) -> Repo {
        var r = Repo(id: path.replacingOccurrences(of: "/", with: "·"),
                     name: (path as NSString).lastPathComponent,
                     path: path, absolutePath: path)
        r.kind = workspace ? .workspace : .repo
        return r
    }

    private func byPath(_ nodes: [SidebarNode]) -> [String: SidebarNode] {
        Dictionary(uniqueKeysWithValues: nodes.map { ($0.absolutePath, $0) })
    }

    // A fleet with two plain grouping dirs (__APPS/macOS, __APPS/ios), a two-level
    // nested workspace (tracker-ws → inner-ws → app-core) under another grouping dir,
    // and one repo sitting directly on the scan root.
    private var fixture: [Repo] {
        [
            mk("/Code/__APPS/macOS/vibe-dashboard"),
            mk("/Code/__APPS/macOS/menubar-app"),
            mk("/Code/__APPS/ios/some-ios-app"),
            mk("/Code/__ECOSYSTEMS/bump/tracker-ws", workspace: true),
            mk("/Code/__ECOSYSTEMS/bump/tracker-ws/inner-ws", workspace: true),
            mk("/Code/__ECOSYSTEMS/bump/tracker-ws/inner-ws/app-core"),
            mk("/Code/standalone"),
        ]
    }

    @Test("intermediate directories become non-selectable group nodes")
    func groupsAreStructural() {
        let nodes = Fleet.buildSidebarTree(repos: fixture, roots: ["/Code"])
        let m = byPath(nodes)
        // Every plain grouping dir between the root and a repo is a group node…
        for g in ["/Code/__APPS", "/Code/__APPS/macOS", "/Code/__APPS/ios",
                  "/Code/__ECOSYSTEMS", "/Code/__ECOSYSTEMS/bump"] {
            let node = m[g]
            #expect(node?.kind == .group, "\(g) should be a group node")
            #expect(node?.repoId == nil, "\(g) must not be selectable (no repoId)")
        }
        // …and EVERY group node in the whole tree is non-selectable — the contract the
        // view relies on to refuse navigation on a structural row.
        for node in nodes where node.kind == .group { #expect(node.repoId == nil) }
    }

    @Test("group depths follow the directory nesting")
    func groupDepths() {
        let m = byPath(Fleet.buildSidebarTree(repos: fixture, roots: ["/Code"]))
        #expect(m["/Code/__APPS"]?.depth == 0)
        #expect(m["/Code/__APPS/macOS"]?.depth == 1)
        #expect(m["/Code/__APPS/ios"]?.depth == 1)
        #expect(m["/Code/__ECOSYSTEMS"]?.depth == 0)
        #expect(m["/Code/__ECOSYSTEMS/bump"]?.depth == 1)
    }

    @Test("a real repo under two grouping dirs lands at depth 2")
    func repoUnderGroups() {
        let m = byPath(Fleet.buildSidebarTree(repos: fixture, roots: ["/Code"]))
        let repo = m["/Code/__APPS/macOS/vibe-dashboard"]
        #expect(repo?.kind == .repo)
        #expect(repo?.depth == 2)
        #expect(repo?.repoId == "·Code·__APPS·macOS·vibe-dashboard")   // selectable
        #expect(repo?.isWorkspace == false)
    }

    @Test("a repo sitting on the scan root has no group ancestors and depth 0")
    func repoAtRoot() {
        let m = byPath(Fleet.buildSidebarTree(repos: fixture, roots: ["/Code"]))
        #expect(m["/Code/standalone"]?.kind == .repo)
        #expect(m["/Code/standalone"]?.depth == 0)
    }

    @Test("nested workspaces expand recursively past level 2")
    func nestedWorkspacesRecurse() {
        let nodes = Fleet.buildSidebarTree(repos: fixture, roots: ["/Code"])
        let m = byPath(nodes)
        let outer = m["/Code/__ECOSYSTEMS/bump/tracker-ws"]
        let inner = m["/Code/__ECOSYSTEMS/bump/tracker-ws/inner-ws"]
        let leaf  = m["/Code/__ECOSYSTEMS/bump/tracker-ws/inner-ws/app-core"]
        // Both workspaces are selectable repo nodes flagged as workspaces…
        #expect(outer?.kind == .repo && outer?.isWorkspace == true)
        #expect(inner?.kind == .repo && inner?.isWorkspace == true)
        // …the nested workspace sits BELOW the outer one (the old 2-level cap put it
        // nowhere) — outer at depth 2, inner at depth 3, its leaf repo at depth 4.
        #expect(outer?.depth == 2)
        #expect(inner?.depth == 3)
        #expect(leaf?.depth == 4)
        // The key guarantee: a workspace nested inside a workspace reaches depth >= 2.
        let workspaceDepths = nodes.filter { $0.isWorkspace }.map(\.depth)
        #expect((workspaceDepths.max() ?? 0) >= 2)
        #expect(inner.map { $0.depth >= 2 } == true)
    }

    @Test("workspaces and groups report having children; leaf repos do not")
    func hasChildrenFlag() {
        let m = byPath(Fleet.buildSidebarTree(repos: fixture, roots: ["/Code"]))
        #expect(m["/Code/__APPS"]?.hasChildren == true)                       // group
        #expect(m["/Code/__ECOSYSTEMS/bump/tracker-ws"]?.hasChildren == true) // workspace
        #expect(m["/Code/standalone"]?.hasChildren == false)                  // leaf repo
        #expect(m["/Code/__APPS/macOS/vibe-dashboard"]?.hasChildren == false) // leaf repo
    }

    @Test("group nodes carry an honest count of the repos beneath them")
    func groupRepoCount() {
        let m = byPath(Fleet.buildSidebarTree(repos: fixture, roots: ["/Code"]))
        #expect(m["/Code/__APPS"]?.repoCount == 3)          // 3 apps below
        #expect(m["/Code/__APPS/macOS"]?.repoCount == 2)    // 2 macOS apps
        #expect(m["/Code/__ECOSYSTEMS"]?.repoCount == 3)    // tracker-ws + inner-ws + app-core
        #expect(m["/Code/standalone"]?.repoCount == 0)      // a repo, not a group
    }

    @Test("no absolute path — and no ForEach id — is ever emitted twice")
    func noDuplicates() {
        let nodes = Fleet.buildSidebarTree(repos: fixture, roots: ["/Code"])
        let paths = nodes.map(\.absolutePath)
        let ids = nodes.map(\.id)
        #expect(Set(paths).count == paths.count, "an absolute path was emitted twice")
        #expect(Set(ids).count == ids.count, "a ForEach id was emitted twice")
    }

    @Test("a parent group always precedes its descendants (pre-order)")
    func preOrder() {
        let nodes = Fleet.buildSidebarTree(repos: fixture, roots: ["/Code"])
        func idx(_ p: String) -> Int { nodes.firstIndex { $0.absolutePath == p }! }
        #expect(idx("/Code/__APPS") < idx("/Code/__APPS/macOS"))
        #expect(idx("/Code/__APPS/macOS") < idx("/Code/__APPS/macOS/vibe-dashboard"))
        #expect(idx("/Code/__ECOSYSTEMS/bump/tracker-ws") < idx("/Code/__ECOSYSTEMS/bump/tracker-ws/inner-ws"))
    }

    @Test("two repos sharing a NAME but not a PATH are both kept, never merged")
    func sameNameDistinctPaths() {
        let repos = [mk("/Code/team-a/api"), mk("/Code/team-b/api")]
        let nodes = Fleet.buildSidebarTree(repos: repos, roots: ["/Code"])
        let apis = nodes.filter { $0.name == "api" && $0.kind == .repo }
        #expect(apis.count == 2)                                          // both survive
        #expect(Set(apis.map(\.absolutePath)).count == 2)                // distinct paths
        #expect(Set(apis.map(\.id)).count == 2)                          // distinct ids
        #expect(byPath(nodes)["/Code/team-a"]?.kind == .group)
        #expect(byPath(nodes)["/Code/team-b"]?.kind == .group)
    }

    @Test("the same repo path passed twice is placed only once")
    func defensiveDedupBySamePath() {
        let dup = mk("/Code/x/dup")
        let nodes = Fleet.buildSidebarTree(repos: [dup, dup], roots: ["/Code"])
        #expect(nodes.filter { $0.absolutePath == "/Code/x/dup" }.count == 1)
        #expect(nodes.filter { $0.absolutePath == "/Code/x" }.count == 1)   // its group, once
    }

    @Test("a workspace directly on the root nests its child at depth 1")
    func workspaceOnRoot() {
        let repos = [mk("/Code/ws", workspace: true), mk("/Code/ws/child")]
        let m = byPath(Fleet.buildSidebarTree(repos: repos, roots: ["/Code"]))
        #expect(m["/Code/ws"]?.kind == .repo)
        #expect(m["/Code/ws"]?.isWorkspace == true)
        #expect(m["/Code/ws"]?.depth == 0)
        #expect(m["/Code/ws"]?.hasChildren == true)
        #expect(m["/Code/ws/child"]?.depth == 1)
        #expect(m["/Code/ws/child"]?.kind == .repo)
    }

    @Test("tilde and trailing-slash forms of the root still match")
    func rootNormalization() {
        // Root given with a trailing slash; repo path clean — norm() must reconcile them.
        let repos = [mk("/Code/grp/app")]
        let nodes = Fleet.buildSidebarTree(repos: repos, roots: ["/Code/"])
        let m = byPath(nodes)
        #expect(m["/Code/grp"]?.kind == .group)
        #expect(m["/Code/grp"]?.depth == 0)
        #expect(m["/Code/grp/app"]?.depth == 1)
    }
}
