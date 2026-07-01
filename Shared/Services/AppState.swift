// AppState.swift — navigation + panel + overlay UI state (the action bus).

import SwiftUI

enum AppView: String, Hashable, CaseIterable { case fleet, agents, findings, skills, autopilot, repo }
enum ConsoleTab: String, Hashable, CaseIterable { case output, shell, activity }

enum SheetKind: String, Identifiable, Hashable {
    case about, reconcile, commit, prune, waiver, applySkill, installHooks, palette
    var id: String { rawValue }
}

struct ShellEntry: Identifiable {
    let id = UUID()
    var repoName: String
    var host: String
    var cwd: String
    var cmd: String
    var lines: [(text: String, tone: VibeTone)]
    var ok: Bool
}

@MainActor
@Observable
final class AppState {
    var view: AppView = .fleet
    var selectedId: String?
    var returnView: AppView = .fleet
    var inspectorOpen = true
    var consoleOpen = false
    var consoleTab: ConsoleTab = .activity
    var sheet: SheetKind?
    var toasts: [ToastData] = []
    var shellLog: [ShellEntry] = []
    private var toastSeq = 0

    private static let navKey = "vibe.mac.nav"

    init() {
        if let d = UserDefaults.standard.dictionary(forKey: Self.navKey) {
            if let v = d["view"] as? String, let av = AppView(rawValue: v) { view = av }
            selectedId = d["selectedId"] as? String
            inspectorOpen = (d["inspectorOpen"] as? Bool) ?? true
            consoleOpen = (d["consoleOpen"] as? Bool) ?? false
        }
    }
    private func persist() {
        UserDefaults.standard.set([
            "view": view.rawValue, "selectedId": selectedId ?? "",
            "inspectorOpen": inspectorOpen, "consoleOpen": consoleOpen,
        ], forKey: Self.navKey)
    }

    func goView(_ v: AppView) { view = v; selectedId = nil; persist() }
    func openRepo(_ id: String) {
        if view != .repo { returnView = view }
        view = .repo; selectedId = id; persist()
    }
    func back() { view = returnView; selectedId = nil; persist() }
    func toggleInspector() { inspectorOpen.toggle(); persist() }
    func toggleConsole() { consoleOpen.toggle(); persist() }
    func openConsole(_ tab: ConsoleTab? = nil) { consoleOpen = true; if let tab { consoleTab = tab }; persist() }
    func openSheet(_ k: SheetKind) { sheet = k }
    func closeSheet() { sheet = nil }
    func togglePalette() { sheet = (sheet == .palette) ? nil : .palette }

    @discardableResult
    func toast(_ title: String, _ message: String = "", _ tone: VibeTone = .info) -> Int {
        toastSeq += 1
        let id = toastSeq
        toasts.append(ToastData(id: id, title: title, message: message, tone: tone))
        Task { try? await Task.sleep(for: .seconds(4.4)); dismissToast(id) }
        return id
    }
    func dismissToast(_ id: Int) { toasts.removeAll { $0.id == id } }

    /// Route a finding's fix-it to the matching action.
    func runFix(_ f: Finding) {
        if let rid = f.repoId { selectedId = rid }
        switch f.fix {
        case "reconcile": openRepo(f.repoId ?? selectedId ?? ""); openSheet(.reconcile)
        case "commit…", "sign + push": if let r = f.repoId { openRepo(r) }; openSheet(.commit)
        case "prune": if let r = f.repoId { openRepo(r) }; openSheet(.prune)
        case "apply skill": openSheet(.applySkill)
        case "install hooks": if let r = f.repoId { openRepo(r) }; openSheet(.installHooks)
        case "open console", "re-run", "open tests": if let r = f.repoId { openRepo(r) }; openConsole(.output); toast("console", f.what, .info)
        case "split file": toast("god-file surgery", "opening with suggested split points…", .info)
        case "init serena": toast("serena init", "indexing symbols…", .info)
        case "scope server": toast("mcp · scoped", "\(f.what) narrowed to the repo root", .ok)
        case "reconnect": toast("mcp · reconnect", "refreshing capability token…", .info)
        case "open file": if let r = f.repoId { openRepo(r) }; toast("editor", "opened \(f.what)", .ok)
        default: if let r = f.repoId { openRepo(r) }
        }
    }
}
