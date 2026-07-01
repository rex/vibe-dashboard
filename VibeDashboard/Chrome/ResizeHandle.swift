// ResizeHandle.swift — a draggable divider for resizing panes. AppKit-backed so
// it wins over the window's move-by-background drag (isMovableByWindowBackground
// would otherwise swallow the gesture and the handle would do nothing).

import SwiftUI
import AppKit

struct ResizeHandle: View {
    enum Axis { case horizontal, vertical }
    let axis: Axis
    @Binding var value: Double
    let range: ClosedRange<Double>
    var invert: Bool = false   // retained for call-site compatibility; unused (AppKit y-up coords)

    @State private var hovering = false

    var body: some View {
        Rectangle()
            .fill(hovering ? Theme.color.accent.opacity(0.5) : Color.clear)
            .frame(width: axis == .horizontal ? 6 : nil, height: axis == .vertical ? 6 : nil)
            .frame(maxWidth: axis == .vertical ? .infinity : nil,
                   maxHeight: axis == .horizontal ? .infinity : nil)
            .overlay(Rectangle().fill(Theme.color.border).frame(
                width: axis == .horizontal ? 1 : nil, height: axis == .vertical ? 1 : nil))
            .overlay(DividerInteractor(axis: axis, value: $value, range: range, hovering: $hovering))
            .contentShape(Rectangle())
    }
}

/// The AppKit interaction layer: refuses to move the window on mouse-down,
/// shows the resize cursor, and reports clamped drag deltas to the binding.
private struct DividerInteractor: NSViewRepresentable {
    let axis: ResizeHandle.Axis
    @Binding var value: Double
    let range: ClosedRange<Double>
    @Binding var hovering: Bool

    func makeNSView(context: Context) -> DividerNSView { wire(DividerNSView()) }
    func updateNSView(_ nsView: DividerNSView, context: Context) { _ = wire(nsView) }

    @discardableResult
    private func wire(_ v: DividerNSView) -> DividerNSView {
        v.axis = axis
        v.range = range
        v.currentValue = { value }
        v.onDrag = { value = $0 }
        v.onHover = { hovering = $0 }
        return v
    }
}

final class DividerNSView: NSView {
    var axis: ResizeHandle.Axis = .horizontal
    var range: ClosedRange<Double> = 0...1
    var currentValue: () -> Double = { 0 }
    var onDrag: (Double) -> Void = { _ in }
    var onHover: (Bool) -> Void = { _ in }

    private var startLocation: NSPoint = .zero
    private var startValue: Double = 0
    private var tracking: NSTrackingArea?

    override var mouseDownCanMoveWindow: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: axis == .horizontal ? .resizeLeftRight : .resizeUpDown)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self)
        addTrackingArea(t); tracking = t
    }
    override func mouseEntered(with event: NSEvent) { onHover(true) }
    override func mouseExited(with event: NSEvent) { onHover(false) }

    override func mouseDown(with event: NSEvent) {
        startLocation = event.locationInWindow
        startValue = currentValue()
    }
    override func mouseDragged(with event: NSEvent) {
        let loc = event.locationInWindow
        // AppKit y increases upward: dragging the console divider up (Δy>0) grows it;
        // dragging the sidebar divider right (Δx>0) widens it — both add to value.
        let delta = axis == .horizontal ? Double(loc.x - startLocation.x)
                                        : Double(loc.y - startLocation.y)
        onDrag(Swift.min(range.upperBound, Swift.max(range.lowerBound, startValue + delta)))
    }
}
