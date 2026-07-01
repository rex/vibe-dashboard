// Panel.swift — the card/panel surface (.vibe-panel) + header.

import SwiftUI

enum PanelSurface {
    case plain, raised, sunken
    var color: Color {
        switch self {
        case .plain: return Theme.color.surface1
        case .raised: return Theme.color.surfaceRaised
        case .sunken: return Theme.color.surfaceSunken
        }
    }
}

/// A tracked, uppercase mono panel title (`.vibe-panel__title`).
struct PanelTitle: View {
    let text: String
    var icon: String? = nil
    var body: some View {
        HStack(spacing: Theme.space.x2) {
            if let icon { VibeIcon(icon, size: 13, color: Theme.color.textSecondary) }
            Text(text).vibeMicroLabel(VibeFont.size.xs, color: Theme.color.textSecondary)
        }
    }
}

/// Panel container: solid ink surface, hairline border, tight radius,
/// faint inset top-light, optional header row + glow.
struct VibePanel<Header: View, Content: View>: View {
    var surface: PanelSurface = .plain
    var glow: Bool = false
    var flushBody: Bool = false
    var bodyPadding: CGFloat = Theme.space.x4
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if Header.self != EmptyView.self {
                header()
                    .padding(.horizontal, Theme.space.x4)
                    .frame(minHeight: 44)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Theme.color.border).frame(height: 1)
                    }
            }
            content()
                .padding(flushBody ? 0 : bodyPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(surface.color)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius.md, style: .continuous)
                .strokeBorder(glow ? Theme.color.okLine : Theme.color.border, lineWidth: 1)
        )
        .overlay(alignment: .top) {   // inset top-light
            Rectangle().fill(Color.white.opacity(0.03)).frame(height: 1)
                .padding(.horizontal, 1)
        }
        .modifier(GlowModifier(active: glow, tone: .ok))
    }
}

extension VibePanel where Header == EmptyView {
    init(surface: PanelSurface = .plain, glow: Bool = false, flushBody: Bool = false,
         bodyPadding: CGFloat = Theme.space.x4, @ViewBuilder content: @escaping () -> Content) {
        self.init(surface: surface, glow: glow, flushBody: flushBody,
                  bodyPadding: bodyPadding, header: { EmptyView() }, content: content)
    }
}

extension VibePanel where Header == PanelTitle {
    init(title: String, icon: String? = nil, surface: PanelSurface = .plain,
         glow: Bool = false, flushBody: Bool = false, bodyPadding: CGFloat = Theme.space.x4,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(surface: surface, glow: glow, flushBody: flushBody, bodyPadding: bodyPadding,
                  header: { PanelTitle(text: title, icon: icon) }, content: content)
    }
}

/// Phosphor glow around live/healthy surfaces (`--glow-ok`).
struct GlowModifier: ViewModifier {
    var active: Bool
    var tone: VibeTone = .ok
    func body(content: Content) -> some View {
        let c = Theme.color.tone(tone)
        return content.shadow(color: active ? c.opacity(0.22) : .clear,
                              radius: active ? 10 : 0, x: 0, y: 0)
    }
}
