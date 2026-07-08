// AssetProbe.swift — resolve a repo's OWN icon (app icon / favicon / logo) from disk,
// off the main actor, cached and downsampled. macOS/iOS apps: the largest PNG under
// any *.xcassets/AppIcon.appiconset. Web apps: favicon.ico / public/favicon.* / a
// public logo. Nothing found ⇒ nil, and the UI honestly falls back to the stack
// emblem — never a fabricated or mismatched icon.

import Foundation
#if canImport(AppKit)
import AppKit
import ImageIO
#endif

enum AssetProbe {

    // MARK: - Pure path resolution (testable; injectable FileManager, no image decode)

    /// Best on-disk icon path for a repo, or nil. A native app icon wins over web
    /// favicons; within an appiconset the LARGEST png (by byte size — the 1024 master)
    /// is chosen. Pure: given the same tree it always resolves the same path.
    static func resolveIconPath(repoDir: String, fileManager fm: FileManager = .default) -> String? {
        if let app = appIconPath(repoDir: repoDir, fm: fm) { return app }
        if let web = webIconPath(repoDir: repoDir, fm: fm) { return web }
        return nil
    }

    /// The largest PNG inside the first `*.xcassets/AppIcon.appiconset` found.
    static func appIconPath(repoDir: String, fm: FileManager = .default) -> String? {
        guard let iconSet = findAppIconSet(repoDir: repoDir, fm: fm) else { return nil }
        return largestPNG(inDir: iconSet, fm: fm)
    }

    /// Bounded breadth-first walk for a `*.xcassets` directory that contains an
    /// `AppIcon.appiconset`. Skips heavy/vendored/dot dirs so a big monorepo doesn't
    /// turn a glance into a full-tree crawl.
    static func findAppIconSet(repoDir: String, fm: FileManager = .default, maxDepth: Int = 6) -> String? {
        let skip: Set<String> = [".git", "node_modules", "DerivedData", ".build", "Pods",
                                 "vendor", ".venv", "venv", "dist", "build", ".next", "Carthage"]
        var queue: [(path: String, depth: Int)] = [(repoDir, 0)]
        while !queue.isEmpty {
            let (dir, depth) = queue.removeFirst()
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for name in entries.sorted() {
                let full = (dir as NSString).appendingPathComponent(name)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue else { continue }
                if name.hasSuffix(".xcassets") {
                    let candidate = (full as NSString).appendingPathComponent("AppIcon.appiconset")
                    var cIsDir: ObjCBool = false
                    if fm.fileExists(atPath: candidate, isDirectory: &cIsDir), cIsDir.boolValue { return candidate }
                }
                if depth < maxDepth && !skip.contains(name) && !name.hasPrefix(".") {
                    queue.append((full, depth + 1))
                }
            }
        }
        return nil
    }

    /// The `.png` in `dir` with the largest byte size (a decode-free proxy for the
    /// highest-resolution master — the 1024 icon is the fattest file).
    static func largestPNG(inDir dir: String, fm: FileManager = .default) -> String? {
        guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return nil }
        let pngs = entries.filter { $0.lowercased().hasSuffix(".png") }
            .map { (dir as NSString).appendingPathComponent($0) }
        guard !pngs.isEmpty else { return nil }
        return pngs.max { byteSize($0, fm) < byteSize($1, fm) }
    }

    static func byteSize(_ path: String, _ fm: FileManager) -> Int {
        guard let attrs = try? fm.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int else { return 0 }
        return size
    }

    /// First existing web icon from a priority list. Renderable rasters (ico/png)
    /// rank ABOVE vector svg — an SVG we can't decode would otherwise beat a PNG we
    /// can, leaving a blank thumbnail instead of a real logo.
    static func webIconPath(repoDir: String, fm: FileManager = .default) -> String? {
        let candidates = [
            "public/favicon.ico", "public/favicon.png", "public/apple-touch-icon.png",
            "public/logo.png", "public/icon.png",
            "static/favicon.ico", "static/favicon.png",
            "app/icon.png", "src/favicon.ico", "src/assets/favicon.png",
            "assets/favicon.ico", "assets/favicon.png",
            "favicon.ico", "favicon.png", "icon.png",
            // vector last: resolvable, but may not decode to a thumbnail → emblem fallback
            "public/favicon.svg", "public/logo.svg", "app/icon.svg",
        ]
        for rel in candidates {
            let full = (repoDir as NSString).appendingPathComponent(rel)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: full, isDirectory: &isDir), !isDir.boolValue { return full }
        }
        return nil
    }

    // MARK: - Thumbnail decode (AppKit) — downsampled PNG Data (Sendable)

    #if canImport(AppKit)
    /// Resolve + downsample a repo's icon to a small PNG, returned as Sendable `Data`
    /// (so it can cross the actor boundary cleanly — `NSImage` cannot). nil when there
    /// is no icon on disk or it isn't a decodable raster (e.g. an SVG).
    static func thumbnailData(repoDir: String, maxPixel: Int = 128) -> Data? {
        guard let path = resolveIconPath(repoDir: repoDir) else { return nil }
        return downsampledPNG(path: path, maxPixel: maxPixel)
    }

    /// ImageIO downsample — decodes only a `maxPixel`-bounded thumbnail, so a 1024²
    /// app-icon master never sits full-resolution in memory across a fleet of rows.
    static func downsampledPNG(path: String, maxPixel: Int) -> Data? {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let src = CGImageSourceCreateWithURL(url, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }
    #endif
}

#if canImport(AppKit)
/// Process-wide cache of resolved, downsampled repo icons keyed by repo dir. The
/// disk walk + decode happen INSIDE the actor (off the main actor); only Sendable
/// `Data` crosses back, so the view layer can build an `NSImage` on the main actor
/// without tripping strict concurrency. Cached so the fleet list doesn't re-scan on
/// every scroll or sweep.
actor RepoIconCache {
    static let shared = RepoIconCache()
    private var cache: [String: Data?] = [:]

    func thumbnailData(forRepoDir dir: String, maxPixel: Int = 128) -> Data? {
        if let hit = cache[dir] { return hit }
        let data = AssetProbe.thumbnailData(repoDir: dir, maxPixel: maxPixel)
        cache[dir] = data
        return data
    }
}
#endif
