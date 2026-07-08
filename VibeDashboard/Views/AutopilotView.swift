// AutopilotView.swift — armable autopilot rules: the aggressive end of the
// read-only → propose-then-apply → autopilot spectrum. Arm a rule and it acts
// on disk unattended; destructive rules ship disarmed.

import SwiftUI

private enum AP {
    static let tile: CGFloat = 34          // rule icon tile
    static let rowGap: CGFloat = 14        // tile → body gap (spec 14pt)
    static let rowPadV: CGFloat = 14       // rule row vertical padding (spec 14pt)
    static let logTs: CGFloat = 34         // log timestamp column
    static let logRepo: CGFloat = 130      // log repo column
    static let switchNudge: CGFloat = 4    // align toggle to title baseline
}

struct AutopilotView: View {
    @Environment(AppState.self) private var app
    @Environment(FleetStore.self) private var store

    // Persisted view-local (UserDefaults) so an armed choice survives a re-scan.
    // This is the arm *toggle* only — no rule executes (see previewBanner).
    @AppStorage("vibe.autopilot.armed") private var armedStore: String = ""
    @State private var armed: [String: Bool] = [:]

    private var rules: [AutopilotRule] { store.fleet.autopilot }
    private var armedCount: Int { armed.values.lazy.filter { $0 }.count }
    private var autoLog: [ActivityEntry] { store.fleet.activity.filter { $0.kind == "autopilot" } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.space.x4) {
                header
                previewBanner
                rulesCard
                logCard
            }
            .padding(Theme.space.x5)
        }
        .task { seed() }
        .onAppear { seed() }
    }

    /// Seed local armed state (only if unseeded): a persisted choice wins, and
    /// any rule not yet in the store falls back to its shipped `.armed` default.
    private func seed() {
        guard armed.isEmpty, !rules.isEmpty else { return }
        var loaded = Self.decode(armedStore)
        for r in rules where loaded[r.ruleId] == nil { loaded[r.ruleId] = r.armed }
        armed = loaded
    }

    private func toggle(_ rule: AutopilotRule) {
        let next = !(armed[rule.ruleId] ?? rule.armed)
        armed[rule.ruleId] = next
        persist()
        // HONEST: arming only saves the toggle. No rule executes yet, so the
        // toast must not claim anything ran "automatically" / "unattended".
        if next {
            app.toast("armed (preview)", rule.label + " — saved; autopilot rules don't run yet", .info)
        } else {
            app.toast("disarmed", rule.label, .info)
        }
    }

    /// Persist the arm map to view-local UserDefaults (survives a re-scan).
    private func persist() {
        if let data = try? JSONEncoder().encode(armed),
           let string = String(data: data, encoding: .utf8) {
            armedStore = string
        }
    }

    private static func decode(_ string: String) -> [String: Bool] {
        guard let data = string.data(using: .utf8),
              let map = try? JSONDecoder().decode([String: Bool].self, from: data)
        else { return [:] }
        return map
    }

    // MARK: header

    private var header: some View {
        HStack(alignment: .bottom, spacing: Theme.space.x5) {
            VStack(alignment: .leading, spacing: Theme.space.x1_5) {
                Text("Autopilot")
                    .font(VibeFont.sans(VibeFont.size.xxl, .semibold))
                    .tracking(VibeFont.size.xxl * VibeFont.track.snug)
                    .foregroundStyle(Theme.color.textBright)
                (Text("read-only watches and chores you trust enough to let run unattended. ")
                    .foregroundStyle(Theme.color.textSecondary)
                 + Text("destructive").foregroundStyle(Theme.color.danger)
                 + Text(" rules ship disarmed — once autopilot executes, arming one will let it act on disk without asking.")
                    .foregroundStyle(Theme.color.textSecondary))
                    .font(VibeFont.mono(VibeFont.size.sm))
                    .lineSpacing(3)
                    .frame(maxWidth: 620, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.space.x4)
            Pill(text: "\(armedCount) of \(rules.count) armed",
                 tone: armedCount > 0 ? .ok : .neutral, icon: "zap")
        }
    }

    // MARK: preview banner

    /// The honest disclosure: the arm toggles are real and persist, but no rule
    /// engine runs them yet. Prevents a "red-dot-means-something" reading of an
    /// armed rule.
    private var previewBanner: some View {
        HStack(alignment: .top, spacing: Theme.space.x2_5) {
            VibeIcon("triangle-alert", size: 15, color: Theme.color.warn)
            (Text("Preview — ")
                .font(VibeFont.mono(VibeFont.size.sm, .bold)).foregroundStyle(Theme.color.warn)
             + Text("armed rules don't execute yet. Arming saves the toggle so your choice survives a re-scan, but nothing runs on disk.")
                .font(VibeFont.mono(VibeFont.size.sm)).foregroundStyle(Theme.color.textSecondary))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.space.x4)
        .padding(.vertical, Theme.space.x3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.color.warnSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius.md, style: .continuous)
            .strokeBorder(Theme.color.warnLine, lineWidth: 1))
    }

    // MARK: rules

    private var rulesCard: some View {
        VibePanel(flushBody: true) {
            if rules.isEmpty {
                EmptyState(icon: "gauge-circle", tone: .neutral, text: "no autopilot rules configured.")
            } else {
                VStack(spacing: 0) {
                    ForEach(rules) { rule in
                        RuleRow(rule: rule, armed: armed[rule.ruleId] ?? rule.armed) { toggle(rule) }
                    }
                }
            }
        }
    }

    // MARK: recent auto-actions log

    private var logCard: some View {
        VibePanel(title: "recent auto-actions", flushBody: true) {
            if autoLog.isEmpty {
                EmptyState(icon: "gauge-circle", tone: .ok, text: "nothing automated yet.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(autoLog.enumerated()), id: \.element.id) { idx, entry in
                        AutoLogRow(entry: entry, last: idx == autoLog.count - 1) {
                            if entry.repo != "—", let r = store.fleet.leaves.first(where: { $0.name == entry.repo }) {
                                app.openRepo(r.id)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - RuleRow

private struct RuleRow: View {
    let rule: AutopilotRule
    let armed: Bool
    var onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: AP.rowGap) {
            iconTile
            VStack(alignment: .leading, spacing: Theme.space.x1) {
                titleRow
                Text(rule.desc)
                    .font(VibeFont.sans(VibeFont.size.sm))
                    .foregroundStyle(Theme.color.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                metaRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VibeSwitch(isOn: Binding(get: { armed }, set: { _ in onToggle() }))
                .padding(.top, AP.switchNudge)
        }
        .padding(.horizontal, Theme.space.x4)
        .padding(.vertical, AP.rowPadV)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(armed && rule.danger ? Theme.color.dangerSurfaceSoft : .clear)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.borderSubtle).frame(height: 1) }
    }

    private var iconTile: some View {
        VibeIcon(rule.danger ? "shield-alert" : "gauge-circle", size: 17, color: iconColor)
            .frame(width: AP.tile, height: AP.tile)
            .background(tileBg)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous)
                .strokeBorder(tileLine, lineWidth: 1))
    }
    private var iconColor: Color {
        armed ? (rule.danger ? Theme.color.danger : Theme.color.accent) : Theme.color.textMuted
    }
    private var tileBg: Color {
        armed ? (rule.danger ? Theme.color.dangerSurface : Theme.color.okSurface) : Theme.color.surfaceSunken
    }
    private var tileLine: Color {
        armed ? (rule.danger ? Theme.color.dangerLine : Theme.color.okLine) : Theme.color.border
    }

    private var titleRow: some View {
        HStack(spacing: Theme.space.x2_5) {
            Text(rule.label)
                .font(VibeFont.mono(VibeFont.size.sm, .bold))
                .foregroundStyle(Theme.color.textPrimary)
            if rule.danger { Pill(text: "destructive", tone: .danger, icon: "triangle-alert") }
            if armed { Pill(text: "armed", tone: .ok) } else { Pill(text: "manual", tone: .neutral) }
            Spacer(minLength: 0)
        }
    }

    private var metaRow: some View {
        HStack(spacing: Theme.space.x3) {
            HStack(spacing: 5) {
                VibeIcon("target", size: 11, color: Theme.color.textFaint)
                Text(rule.scope)
            }
            HStack(spacing: 5) {
                VibeIcon("history", size: 11, color: Theme.color.textFaint)
                Text("last \(rule.lastRan)")
            }
            if rule.runs > 0 {
                Text("\(rule.runs) runs")
            }
        }
        .font(VibeFont.mono(VibeFont.size.xxs))
        .monospacedDigit()
        .foregroundStyle(Theme.color.textFaint)
        .lineLimit(1)
    }
}

// MARK: - AutoLogRow

private struct AutoLogRow: View {
    let entry: ActivityEntry
    let last: Bool
    var onTapRepo: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: Theme.space.x3) {
            Text(entry.t)
                .foregroundStyle(Theme.color.textFaint)
                .frame(width: AP.logTs, alignment: .trailing)
            VibeIcon("gauge-circle", size: 13, color: Theme.color.tone(entry.tone))
            Text(entry.repo)
                .foregroundStyle(hover ? Theme.color.textPrimary : Theme.color.textSecondary)
                .frame(width: AP.logRepo, alignment: .leading)
                .lineLimit(1)
                .contentShape(Rectangle())
                .onHover { hover = $0 && entry.repo != "—" }
                .onTapGesture(perform: onTapRepo)
            Text(entry.msg)
                .foregroundStyle(Theme.color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
        }
        .font(VibeFont.mono(VibeFont.size.xs))
        .monospacedDigit()
        .padding(.horizontal, Theme.space.x4)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            if !last { Rectangle().fill(Theme.color.borderSubtle).frame(height: 1) }
        }
    }
}
