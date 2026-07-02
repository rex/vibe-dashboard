#!/usr/bin/env swift
// make-appicon.swift — draws Vibe's app icon (concept #2 "Prompt v", enlarged so
// the lime v▮ fills most of the tile) at every macOS size and writes the
// AppIcon.appiconset. Vector-drawn per size, so it's crisp at 16px and 1024px.
//
// Usage: swift Scripts/make-appicon.swift <AppIcon.appiconset dir>

import AppKit
import CoreGraphics
import Foundation

let ink = CGColor(red: 10/255, green: 15/255, blue: 12/255, alpha: 1)       // #0a0f0c
let lime = CGColor(red: 180/255, green: 255/255, blue: 52/255, alpha: 1)    // #B4FF34
let limeFaint = CGColor(red: 180/255, green: 255/255, blue: 52/255, alpha: 0.16)

func drawIcon(_ px: Int) -> CGImage {
    let s = CGFloat(px)
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    func y(_ t: CGFloat) -> CGFloat { s - t }   // CG is bottom-left; author top-based

    // macOS icon squircle — ~80% of the tile, matching the dock grid.
    let m = s * 0.10
    let w = s - 2 * m
    let squircle = CGPath(roundedRect: CGRect(x: m, y: m, width: w, height: w),
                          cornerWidth: w * 0.2237, cornerHeight: w * 0.2237, transform: nil)
    ctx.addPath(squircle); ctx.setFillColor(ink); ctx.fillPath()
    ctx.addPath(squircle); ctx.setStrokeColor(limeFaint); ctx.setLineWidth(s * 0.006); ctx.strokePath()

    // The mark: a big "v" + a terminal cursor block, optically centered.
    ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.setStrokeColor(lime); ctx.setLineWidth(s * 0.12)
    ctx.beginPath()
    ctx.move(to: CGPoint(x: s * 0.20, y: y(s * 0.28)))
    ctx.addLine(to: CGPoint(x: s * 0.42, y: y(s * 0.72)))
    ctx.addLine(to: CGPoint(x: s * 0.64, y: y(s * 0.28)))
    ctx.strokePath()

    let bx = s * 0.68, bw = s * 0.12, bTop = s * 0.28, bh = s * 0.44
    let block = CGPath(roundedRect: CGRect(x: bx, y: y(bTop + bh), width: bw, height: bh),
                       cornerWidth: s * 0.025, cornerHeight: s * 0.025, transform: nil)
    ctx.addPath(block); ctx.setFillColor(lime); ctx.fillPath()

    return ctx.makeImage()!
}

func writePNG(_ img: CGImage, to path: String) {
    let rep = NSBitmapImageRep(cgImage: img)
    rep.size = NSSize(width: img.width, height: img.height)
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("png encode failed") }
    try! data.write(to: URL(fileURLWithPath: path))
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "VibeDashboard/Assets.xcassets/AppIcon.appiconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// (filename, pixels) for the standard macOS iconset.
let specs: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
var cache: [Int: CGImage] = [:]
for (name, px) in specs {
    let img = cache[px] ?? drawIcon(px)
    cache[px] = img
    writePNG(img, to: "\(outDir)/\(name)")
}

let contents = """
{
  "images" : [
    { "idiom" : "mac", "scale" : "1x", "size" : "16x16", "filename" : "icon_16x16.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "16x16", "filename" : "icon_16x16@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "32x32", "filename" : "icon_32x32.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "32x32", "filename" : "icon_32x32@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "128x128", "filename" : "icon_128x128.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "128x128", "filename" : "icon_128x128@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "256x256", "filename" : "icon_256x256.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "256x256", "filename" : "icon_256x256@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "512x512", "filename" : "icon_512x512.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "512x512", "filename" : "icon_512x512@2x.png" }
  ],
  "info" : { "version" : 1, "author" : "xcode" }
}
"""
try! contents.write(toFile: "\(outDir)/Contents.json", atomically: true, encoding: .utf8)
print("wrote \(specs.count) PNGs + Contents.json to \(outDir)")
