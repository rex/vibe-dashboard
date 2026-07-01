// ResizeHandle.swift — a thin draggable divider for resizing panes.

import SwiftUI
import AppKit

struct ResizeHandle: View {
    enum Axis { case horizontal, vertical }
    let axis: Axis
    @Binding var value: Double
    let range: ClosedRange<Double>
    var invert: Bool = false

    @State private var base: Double?
    @State private var hovering = false

    var body: some View {
        Rectangle()
            .fill(hovering ? Theme.color.accent.opacity(0.5) : Color.clear)
            .frame(width: axis == .horizontal ? 5 : nil, height: axis == .vertical ? 5 : nil)
            .frame(maxWidth: axis == .vertical ? .infinity : nil,
                   maxHeight: axis == .horizontal ? .infinity : nil)
            .overlay(Rectangle().fill(Theme.color.border).frame(
                width: axis == .horizontal ? 1 : nil, height: axis == .vertical ? 1 : nil))
            .contentShape(Rectangle())
            .onHover { h in
                hovering = h
                if h { (axis == .horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push() }
                else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { v in
                        if base == nil { base = value }
                        let t = Double(axis == .horizontal ? v.translation.width : v.translation.height)
                        let next = (base ?? value) + (invert ? -t : t)
                        value = Swift.min(range.upperBound, Swift.max(range.lowerBound, next))
                    }
                    .onEnded { _ in base = nil }
            )
    }
}
