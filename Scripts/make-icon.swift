// Draws the app icon: black square, thin orange frame, orange "M". Writes an .iconset folder.
// Usage: swift Scripts/make-icon.swift Resources/AppIcon.iconset
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let orange = NSColor(srgbRed: 1.0, green: 0.353, blue: 0.212, alpha: 1)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let inset = s * 0.09
    let box = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    NSColor.black.setFill()
    box.fill()
    orange.setFill()
    box.insetBy(dx: s * 0.03, dy: s * 0.03).frame(withWidth: max(1, s * 0.012))
    let font = NSFont.monospacedSystemFont(ofSize: s * 0.52, weight: .bold)
    let str = NSAttributedString(string: "M", attributes: [.font: font, .foregroundColor: orange])
    let size = str.size()
    str.draw(at: NSPoint(x: (s - size.width) / 2, y: (s - size.height) / 2 + s * 0.01))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let names: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in names {
    try! render(px).write(to: out.appendingPathComponent(name + ".png"))
}
print("wrote \(out.path)")
