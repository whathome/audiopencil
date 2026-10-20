// Renders the app icons: the Mac's into App/macOS/Resources/Assets.xcassets/AppIcon.appiconset, and the
// iPhone's (full-bleed and opaque: iOS applies its own mask) into App/iOS/Resources/Assets.xcassets.
// Usage: swift scripts/make-icon.swift
import AppKit

let folder = URL(fileURLWithPath: "App/macOS/Resources/Assets.xcassets/AppIcon.appiconset")
let sizes: [(points: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]

func render(pixels: Int, fullBleed: Bool = false) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let size = CGFloat(pixels)
    // macOS icon grid: the tile is 824/1024 of the canvas, corner radius ~185/1024. iOS: the whole canvas.
    let inset = fullBleed ? 0 : size * 100 / 1024
    let tile = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let path = fullBleed ? NSBezierPath(rect: tile) : NSBezierPath(roundedRect: tile, xRadius: size * 185 / 1024, yRadius: size * 185 / 1024)
    // Symbols keep the same proportion of the tile on both.
    let scale = tile.width / (size * 824 / 1024)

    NSGraphicsContext.current?.saveGraphicsState()
    if !fullBleed {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowBlurRadius = size * 10 / 1024
        shadow.shadowOffset = NSSize(width: 0, height: -size * 6 / 1024)
        shadow.set()
    }
    NSGradient(starting: NSColor(srgbRed: 0.98, green: 0.78, blue: 0.36, alpha: 1),
               ending: NSColor(srgbRed: 0.91, green: 0.58, blue: 0.13, alpha: 1))!.draw(in: path, angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()

    // Waveform behind, pencil in front.
    let ink = NSColor(srgbRed: 0.25, green: 0.14, blue: 0.01, alpha: 1)
    func symbol(_ name: String, pointSize: CGFloat, alpha: CGFloat) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
            .applying(.init(paletteColors: [ink.withAlphaComponent(alpha)]))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(config)!
    }
    let wave = symbol("waveform", pointSize: size * 0.40 * scale, alpha: 0.22)
    wave.draw(in: NSRect(x: tile.midX - wave.size.width / 2, y: tile.midY - wave.size.height / 2, width: wave.size.width, height: wave.size.height))
    let pencil = symbol("pencil", pointSize: size * 0.42 * scale, alpha: 1)
    pencil.draw(in: NSRect(x: tile.midX - pencil.size.width / 2, y: tile.midY - pencil.size.height / 2, width: pencil.size.width, height: pencil.size.height))

    NSGraphicsContext.restoreGraphicsState()
    guard fullBleed else { return rep.representation(using: .png, properties: [:])! }
    // The App Store wants no alpha channel: flatten onto an opaque bitmap (AppKit can't draw into one).
    let opaque = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                           space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    opaque.draw(rep.cgImage!, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    return NSBitmapImageRep(cgImage: opaque.makeImage()!).representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for (points, scale) in sizes {
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try! render(pixels: points * scale).write(to: folder.appending(path: name))
    images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appending(path: "Contents.json"))
print("Wrote \(images.count) icon sizes")

let phone = URL(fileURLWithPath: "App/iOS/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
try! render(pixels: 1024, fullBleed: true).write(to: phone)
print("Wrote the iPhone icon")
