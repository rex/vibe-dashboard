// PolicyProbe.swift — parse a repo's VIBE.yaml (Yams) into the inspector model.

import Foundation
import Yams

enum PolicyProbe {
    static func load(_ abs: String) -> [String: Any]? {
        let path = (abs as NSString).appendingPathComponent("VIBE.yaml")
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return (try? Yams.load(yaml: text)) as? [String: Any]
    }

    /// The sections + rows for the Policy tab, with a skeleton-diff mark.
    static func sections(_ dict: [String: Any]) -> [PolicySection] {
        let order = ["project", "stack", "architecture", "quality_gates", "security", "workflow", "docs", "apple", "deployment"]
        var out: [PolicySection] = []
        for section in order {
            guard let sub = dict[section] as? [String: Any] else { continue }
            var rows: [PolicyRow] = []
            for (k, v) in flatten(sub).sorted(by: { $0.0 < $1.0 }) {
                let flatKey = "\(section).\(k)"
                var row = PolicyRow(k: k, v: fmt(v))
                if let skel = Reference.skeletonDefaults[flatKey], skel != row.v {
                    row.note = "delta"; row.skel = skel
                }
                // Keep the full list for array-valued keys so the UI can expand it —
                // the collapsed `v` summary otherwise hides entries (e.g. exclude_globs).
                if let arr = v as? [Any], arr.count > 3 {
                    row.values = arr.map { fmt($0) }
                }
                rows.append(row)
            }
            if !rows.isEmpty { out.append(PolicySection(section: section, rows: rows)) }
        }
        return out
    }

    /// Flatten one level of nesting: {a: 1, b: {c: 2}} → [a: 1, b.c: 2].
    private static func flatten(_ dict: [String: Any], prefix: String = "") -> [(String, Any)] {
        var rows: [(String, Any)] = []
        for (k, v) in dict {
            let key = prefix.isEmpty ? k : "\(prefix).\(k)"
            if let nested = v as? [String: Any] {
                rows.append(contentsOf: flatten(nested, prefix: key))
            } else {
                rows.append((key, v))
            }
        }
        return rows
    }

    private static func fmt(_ v: Any) -> String {
        switch v {
        case let s as String: return s
        case let b as Bool: return b ? "true" : "false"
        case let i as Int: return String(i)
        case let d as Double: return d == d.rounded() ? String(Int(d)) : String(d)
        case let arr as [Any]:
            let items = arr.map { fmt($0) }
            if items.count <= 3 { return items.joined(separator: ", ") }
            return items.prefix(2).joined(separator: ", ") + ", +\(items.count - 2)"
        default: return String(describing: v)
        }
    }

    /// Count files matching architecture.scope_globs (best-effort).
    static func scopeMatched(_ abs: String, dict: [String: Any]) -> Int? {
        guard let arch = dict["architecture"] as? [String: Any],
              let globs = arch["scope_globs"] as? [String], !globs.isEmpty else { return nil }
        // Approximate: count code files under the repo (the census already does this).
        return nil
    }
}
