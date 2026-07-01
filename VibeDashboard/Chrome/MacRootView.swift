// MacRootView.swift — the window shell: toolbar · (sidebar | content+console | inspector) · status bar.

import SwiftUI

struct MacRootView: View {
    @Environment(AppState.self) private var app
    @Environment(FleetStore.self) private var store

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                ToolbarView()
                HStack(spacing: 0) {
                    SidebarView()
                    VStack(spacing: 0) {
                        content
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .background(Theme.color.bgApp)
                        if app.consoleOpen { ConsoleView() }
                    }
                    if app.inspectorOpen { InspectorView() }
                }
                StatusBarView()
            }
            .background(Theme.color.bgApp)

            ToastStack(toasts: app.toasts) { app.dismissToast($0) }
        }
        .background(Theme.color.bgVoid)
        .overlay { OverlayHost() }
    }

    @ViewBuilder private var content: some View {
        switch app.view {
        case .fleet: FleetView()
        case .agents: AgentsView()
        case .findings: FindingsView()
        case .skills: SkillsView()
        case .autopilot: AutopilotView()
        case .repo:
            if let r = store.fleet.repo(app.selectedId) {
                if r.isWorkspace { WorkspaceDetailView(workspace: r) } else { RepoDetailView(repo: r) }
            } else { FleetView() }
        }
    }
}
