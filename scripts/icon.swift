// app icon and the in-app mark from the logo: swift scripts/icon.swift <logo.jpg> <appiconset dir> [mark imageset dir]
// the mark is cropped from the logo's black square and set on a macOS squircle at every size the asset catalog wants
import AppKit

let args = CommandLine.arguments
let logo = NSImage(contentsOfFile: args[1])!
let outDir = URL(fileURLWithPath: args[2])
var rect = NSRect(origin: .zero, size: logo.size)
let src = logo.cgImage(forProposedRect: &rect, context: nil, hints: nil)!

/// the bounding box of everything brighter than the background
func markBox(_ img: CGImage) -> CGRect {
    let w = img.width, h = img.height
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    let p = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
    var minX = w, minY = h, maxX = 0, maxY = 0
    for y in 0..<h { for x in 0..<w where p[(y * w + x) * 4] > 90 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) } }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)  // bitmap rows, top-left origin
}
let box = markBox(src)
let crop = src.cropping(to: box)!
/// the mark as a grey mask (bright = ink), so it paints onto the tile without the logo's own black square
let mark: CGImage = {
    let g = CGContext(data: nil, width: crop.width, height: crop.height, bitsPerComponent: 8, bytesPerRow: crop.width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    g.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
    return g.makeImage()!
}()
let ink = NSColor(srgbRed: 245 / 255, green: 239 / 255, blue: 226 / 255, alpha: 1).cgColor

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: px * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    // apple's grid: an 824 squircle in a 1024 canvas, a soft shadow under it
    let inset = s * 100 / 1024, side = s - inset * 2
    let tile = CGRect(x: inset, y: inset + s * 6 / 1024, width: side, height: side)
    let path = CGPath(roundedRect: tile, cornerWidth: side * 0.2237, cornerHeight: side * 0.2237, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 8 / 1024), blur: s * 22 / 1024, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(path); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    // the faintest lift at the top so the tile reads as a surface on a black dock
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [NSColor(white: 0.11, alpha: 1).cgColor, NSColor(white: 0.0, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])
    // the mark, 52% of the tile tall (bigger at the small sizes, where its thin bars thin out), a hair above the middle
    let mh = side * (px <= 64 ? 0.64 : 0.52), mw = mh * CGFloat(mark.width) / CGFloat(mark.height)
    let where_ = CGRect(x: tile.midX - mw / 2, y: tile.midY - mh / 2 + side * 0.01, width: mw, height: mh)
    ctx.clip(to: where_, mask: mark)
    ctx.setFillColor(ink); ctx.fill(where_)
    ctx.restoreGState()
    ctx.addPath(path); ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.09).cgColor); ctx.setLineWidth(max(1, s / 512)); ctx.strokePath()
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

for px in [16, 32, 64, 128, 256, 512, 1024] {
    try! render(px).write(to: outDir.appendingPathComponent("icon_\(px).png"))
}
/// the bare mark in the logo's cream on transparent, for the sidebar and the empty state
func renderMark(height: Int) -> Data {
    let w = Int((CGFloat(height) * CGFloat(mark.width) / CGFloat(mark.height)).rounded(.up))
    let ctx = CGContext(data: nil, width: w, height: height, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    let r = CGRect(x: 0, y: 0, width: w, height: height)
    ctx.clip(to: r, mask: mark); ctx.setFillColor(ink); ctx.fill(r)
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}
if args.count > 3 {
    let dir = URL(fileURLWithPath: args[3])
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for (scale, name) in [(1, "mark.png"), (2, "mark@2x.png"), (3, "mark@3x.png")] { try! renderMark(height: 64 * scale).write(to: dir.appendingPathComponent(name)) }
    let json = #"{"images":[{"idiom":"universal","filename":"mark.png","scale":"1x"},{"idiom":"universal","filename":"mark@2x.png","scale":"2x"},{"idiom":"universal","filename":"mark@3x.png","scale":"3x"}],"info":{"author":"xcode","version":1}}"#
    try! json.write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}
print("mark \(box) -> \(outDir.path)")
