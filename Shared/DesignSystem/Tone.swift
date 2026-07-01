// Tone.swift — presentation enums shared by the design system + models.

import Foundation

/// Chip / row / signal tone. Mirrors the design system's status model.
enum VibeTone: String, Sendable, CaseIterable {
    case ok, warn, danger, info, policy, neutral
}

/// A repo / fleet health rollup.
enum Health: String, Sendable, CaseIterable, Comparable {
    case ok, warn, danger, idle

    /// danger > warn > ok > idle for "worst-wins" rollups.
    private var rank: Int {
        switch self {
        case .danger: return 3
        case .warn: return 2
        case .ok: return 1
        case .idle: return 0
        }
    }
    static func < (a: Health, b: Health) -> Bool { a.rank < b.rank }

    var tone: VibeTone {
        switch self {
        case .ok: return .ok
        case .warn: return .warn
        case .danger: return .danger
        case .idle: return .neutral
        }
    }
}

/// Finding severity.
enum Severity: String, Sendable, CaseIterable, Comparable {
    case high, med, low
    private var rank: Int { self == .high ? 0 : self == .med ? 1 : 2 }
    static func < (a: Severity, b: Severity) -> Bool { a.rank < b.rank }
    var tone: VibeTone {
        switch self {
        case .high: return .danger
        case .med: return .warn
        case .low: return .neutral
        }
    }
    var label: String { rawValue.uppercased() }
}

/// A single quality-gate result state.
enum GateStatus: String, Sendable, CaseIterable {
    case ok, warn, fail, skip
    var tone: VibeTone {
        switch self {
        case .ok: return .ok
        case .warn: return .warn
        case .fail: return .danger
        case .skip: return .neutral
        }
    }
    /// Lucide-equivalent SF Symbol for the intrinsic gate mark.
    var symbol: String {
        switch self {
        case .ok: return "checkmark"
        case .warn: return "exclamationmark.triangle"
        case .fail: return "xmark"
        case .skip: return "minus"
        }
    }
}
