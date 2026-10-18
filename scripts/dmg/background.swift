// draws the dmg window background: swift scripts/dmg/background.swift <out.png> <scale>
import AppKit

let args = CommandLine.arguments
let out = URL(fileURLWithPath: args[1])
let scale = CGFloat(Double(args[2]) ?? 1)
let size = NSSize(width: 600, height: 380)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func gray(_ v: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(srgbRed: v / 255, green: v / 255, blue: v / 255, alpha: a) }

// light, so Finder's black icon labels stay readable; the dark app icon carries the brand
NSGradient(starting: gray(246), ending: gray(234))!.draw(in: NSRect(origin: .zero, size: size), angle: -90)

// the arrow between the app (x 170) and Applications (x 430), at icon height (y 190 from the top)
let y = size.height - 190
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 252, y: y)); arrow.line(to: NSPoint(x: 344, y: y))
arrow.move(to: NSPoint(x: 334, y: y + 8)); arrow.line(to: NSPoint(x: 345, y: y)); arrow.line(to: NSPoint(x: 334, y: y - 8))
arrow.lineWidth = 2; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
gray(176).setStroke(); arrow.stroke()

// one quiet line of instruction near the bottom
let style = NSMutableParagraphStyle(); style.alignment = .center
let text = NSAttributedString(string: "Drag Lamport Build into Applications", attributes: [
    .font: NSFont.systemFont(ofSize: 12, weight: .regular), .foregroundColor: gray(140), .paragraphStyle: style,
])
text.draw(in: NSRect(x: 0, y: 44, width: size.width, height: 18))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: out)
