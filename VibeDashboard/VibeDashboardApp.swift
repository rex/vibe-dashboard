// VibeDashboardApp.swift — @main entry (scaffold shell; real chrome lands next).

import SwiftUI

@main
struct VibeDashboardApp: App {
    var body: some Scene {
        WindowGroup {
            ScaffoldRootView()
                .frame(minWidth: 960, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

private struct ScaffoldRootView: View {
    var body: some View {
        ZStack {
            Color(hex: 0x07090A).ignoresSafeArea()
            VStack(spacing: 8) {
                Text("vibe▮")
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: 0xB4FF34))
                Text("mission control for vibe coding")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color(hex: 0x97A39E))
            }
        }
    }
}
