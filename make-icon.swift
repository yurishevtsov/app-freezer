// Renders the 1024x1024 app icon PNG: blue gradient squircle with a snowflake.
// Usage: swift make-icon.swift <output.png>
import AppKit

let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS icon grid: 824pt body centred on a 1024 canvas.
let body = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824),
                        xRadius: 185, yRadius: 185)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.set()
NSColor.black.setFill()
body.fill()
NSGraphicsContext.restoreGraphicsState()

NSGradient(colors: [NSColor(srgbRed: 0.40, green: 0.88, blue: 1.00, alpha: 1),
                    NSColor(srgbRed: 0.18, green: 0.36, blue: 0.95, alpha: 1)])!
    .draw(in: body, angle: -90)

let config = NSImage.SymbolConfiguration(pointSize: 470, weight: .medium)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
if let symbol = NSImage(systemSymbolName: "snowflake", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let s = symbol.size
    symbol.draw(in: NSRect(x: (CGFloat(size) - s.width) / 2, y: (CGFloat(size) - s.height) / 2,
                           width: s.width, height: s.height))
}
NSGraphicsContext.restoreGraphicsState()

try rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
