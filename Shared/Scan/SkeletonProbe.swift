// SkeletonProbe.swift — real skeleton-drift detection from .claude/skeleton-version.
//
// The agentic skeleton stamps each repo it scaffolds with a version in
// `.claude/skeleton-version`. There is no per-repo skill manifest (a genuine hole
// in the skeleton), so the cheapest honest drift signal is: how far behind the
// NEWEST skeleton-version in your own fleet is this repo? Repos trailing the max
// are ones you've stopped syncing — exactly the drift this app exists to surface.

import Foundation

enum SkeletonProbe {
    private static var fm: FileManager { .default }

    /// The stamped skeleton version, or nil if the repo was never scaffolded/stamped.
    static func version(_ abs: String) -> String? {
        let p = (abs as NSString).appendingPathComponent(".claude/skeleton-version")
        guard let s = try? String(contentsOfFile: p, encoding: .utf8) else { return nil }
        let v = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    /// Drift of `version` relative to the fleet-wide `latest` skeleton version.
    static func drift(version: String?, latest: String?) -> Drift {
        var d = Drift(); d.version = version; d.latest = latest
        guard let v = version, let l = latest, compare(v, l) < 0 else { return d }
        d.behind = behindPhrase(v, l)
        return d
    }

    /// The newest skeleton version across a set of stamped versions.
    static func latest(_ versions: [String]) -> String? {
        versions.max { compare($0, $1) < 0 }
    }

    // ---- semver-ish comparison (dotted integers) ----
    private static func parts(_ s: String) -> [Int] {
        s.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
    }
    /// -1 / 0 / 1 for a<b / a==b / a>b.
    static func compare(_ a: String, _ b: String) -> Int {
        let pa = parts(a), pb = parts(b)
        for i in 0..<Swift.max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }
    private static func behindPhrase(_ v: String, _ l: String) -> String {
        let pv = parts(v), pl = parts(l)
        func at(_ a: [Int], _ i: Int) -> Int { i < a.count ? a[i] : 0 }
        if at(pv, 0) != at(pl, 0) { return "\(at(pl, 0) - at(pv, 0)) major behind" }
        if at(pv, 1) != at(pl, 1) { return "\(at(pl, 1) - at(pv, 1)) minor behind" }
        let p = at(pl, 2) - at(pv, 2)
        return "\(p) patch behind"
    }
}
