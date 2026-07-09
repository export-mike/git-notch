#!/usr/bin/env swift
import AppKit

// Generates AppIcon.icns: a dark rounded-square app icon with the white GitHub
// mark and a red notification badge — the same "mark + count" motif the notch
// bar and menu-bar item use. Run:  swift tools/make-icon.swift [outDir]
// Produces <outDir>/AppIcon.icns (default: Resources/).

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources"

// GitHub mark, same path the app embeds (Sources/GitNotch/Views/Icons.swift).
let markSVG = """
<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">\
<path d="M8 0c4.42 0 8 3.58 8 8a8.013 8.013 0 0 1-5.45 7.59c-.4.08-.55-.17-.55-.38 \
0-.27.01-1.13.01-2.2 0-.75-.25-1.23-.54-1.48 1.78-.2 3.65-.88 3.65-3.95 0-.88-.31-1.59-.82-2.15.08-.2.36-1.02-.08-2.12 \
0 0-.67-.22-2.2.82-.64-.18-1.32-.27-2-.27-.68 0-1.36.09-2 .27-1.53-1.03-2.2-.82-2.2-.82-.44 \
1.1-.16 1.92-.08 2.12-.51.56-.82 1.28-.82 2.15 0 3.06 1.86 3.75 3.64 3.95-.23.2-.44.55-.51 \
1.07-.46.21-1.61.55-2.33-.66-.15-.24-.6-.83-1.23-.82-.67.01-.27.38.01.53.34.19.73.9.82 \
1.13.16.45.68 1.31 2.69.94 0 .67.01 1.3.01 1.49 0 .21-.15.45-.55.38A7.995 7.995 0 0 1 0 \
8c0-4.42 3.58-8 8-8Z"/></svg>
"""
let mark = NSImage(data: Data(markSVG.utf8))!

let notchRed = NSColor(srgbRed: 1.0, green: 0.271, blue: 0.227, alpha: 1) // #FF453A

// Tint the (template) mark to `color` in an isolated transparent layer, so the
// sourceAtop fill only touches the glyph's pixels — not an opaque backdrop.
func tinted(_ img: NSImage, _ color: NSColor, px: Int) -> NSImage {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let rect = NSRect(x: 0, y: 0, width: px, height: px)
    img.draw(in: rect)
    color.set()
    rect.fill(using: .sourceAtop)
    NSGraphicsContext.restoreGraphicsState()
    let out = NSImage(size: NSSize(width: px, height: px))
    out.addRepresentation(rep)
    return out
}

func render(_ px: Int) -> NSBitmapImageRep {
    let S = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: S, height: S)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Rounded-square background with a subtle top-to-bottom dark gradient.
    let margin = S * 0.08
    let side = S - margin * 2
    let bg = NSRect(x: margin, y: margin, width: side, height: side)
    let radius = side * 0.2237  // macOS continuous-corner ratio
    let bgPath = NSBezierPath(roundedRect: bg, xRadius: radius, yRadius: radius)
    let grad = NSGradient(colors: [
        NSColor(srgbRed: 0.20, green: 0.20, blue: 0.22, alpha: 1),
        NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1),
    ])!
    grad.draw(in: bgPath, angle: -90)

    // White GitHub mark, centered.
    let markSize = S * 0.5
    let markRect = NSRect(x: (S - markSize) / 2, y: (S - markSize) / 2, width: markSize, height: markSize)
    tinted(mark, .white, px: Int(markSize.rounded())).draw(in: markRect)

    // Red notification badge, top-right, with a dark ring so it separates
    // cleanly from the mark — mirrors the in-app count badge.
    let r = S * 0.15
    let cx = bg.maxX - r * 0.85
    let cy = bg.maxY - r * 0.85
    let ring = r + S * 0.022
    let ringRect = NSRect(x: cx - ring, y: cy - ring, width: ring * 2, height: ring * 2)
    NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1).set()
    NSBezierPath(ovalIn: ringRect).fill()
    let badgeRect = NSRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
    notchRed.set()
    NSBezierPath(ovalIn: badgeRect).fill()

    // Count glyph.
    let text = "3" as NSString
    let font = NSFont.systemFont(ofSize: r * 1.25, weight: .bold)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
    let ts = text.size(withAttributes: attrs)
    text.draw(at: NSPoint(x: cx - ts.width / 2, y: cy - ts.height / 2), withAttributes: attrs)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let fm = FileManager.default
let iconset = NSTemporaryDirectory() + "AppIcon.iconset"
try? fm.removeItem(atPath: iconset)
try! fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)

// (filename, pixel size) pairs iconutil expects.
let variants: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in variants {
    let png = render(px).representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: "\(iconset)/\(name).png"))
}

try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconset, "-o", "\(outDir)/AppIcon.icns"]
try! proc.run()
proc.waitUntilExit()
print("wrote \(outDir)/AppIcon.icns")
