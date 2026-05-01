#!/usr/bin/env swift
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import CoreText
import AppKit

func renderIcon(size: CGFloat) -> CGImage? {
    let scale: CGFloat = 1
    let pixels = Int(size * scale)
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.scaleBy(x: scale, y: scale)

    // Squircle path (Apple-style continuous corner)
    let r = size * 0.225
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let path = CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()

    // Background: deep amber → gold radial
    let colors = [
        CGColor(red: 0.99, green: 0.78, blue: 0.30, alpha: 1.0), // gold center
        CGColor(red: 0.92, green: 0.55, blue: 0.10, alpha: 1.0), // amber edge
        CGColor(red: 0.60, green: 0.30, blue: 0.04, alpha: 1.0)  // bronze deep
    ] as CFArray
    let locations: [CGFloat] = [0.0, 0.55, 1.0]
    if let grad = CGGradient(colorsSpace: cs, colors: colors, locations: locations) {
        ctx.drawRadialGradient(grad,
                               startCenter: CGPoint(x: size * 0.35, y: size * 0.7),
                               startRadius: 0,
                               endCenter: CGPoint(x: size * 0.5, y: size * 0.5),
                               endRadius: size * 0.85,
                               options: .drawsAfterEndLocation)
    }

    // Subtle inner highlight (top)
    let hlColors = [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.18),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.0)
    ] as CFArray
    if let hl = CGGradient(colorsSpace: cs, colors: hlColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(hl,
                               start: CGPoint(x: size * 0.5, y: size),
                               end: CGPoint(x: size * 0.5, y: size * 0.55),
                               options: [])
    }

    // Coin ring (subtle)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.10))
    ctx.setLineWidth(size * 0.012)
    ctx.strokeEllipse(in: rect.insetBy(dx: size * 0.10, dy: size * 0.10))

    // Letter "K"
    let letter = "K" as NSString
    let fontSize = size * 0.62
    let font = NSFont.systemFont(ofSize: fontSize, weight: .black)
    let shadow = NSShadow()
    shadow.shadowBlurRadius = size * 0.04
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
    shadow.shadowColor = NSColor(red: 0.25, green: 0.10, blue: 0.0, alpha: 0.45)

    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(red: 0.20, green: 0.10, blue: 0.02, alpha: 1.0),
        .shadow: shadow
    ]
    let attr = NSAttributedString(string: letter as String, attributes: attrs)
    let textSize = attr.size()

    NSGraphicsContext.saveGraphicsState()
    let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.current = nsCtx
    attr.draw(at: NSPoint(x: (size - textSize.width) / 2,
                          y: (size - textSize.height) / 2 - size * 0.02))
    NSGraphicsContext.restoreGraphicsState()

    // Gem accent (top right diamond)
    let gemSize = size * 0.13
    let gemX = size * 0.74
    let gemY = size * 0.78
    ctx.saveGState()
    ctx.translateBy(x: gemX, y: gemY)
    ctx.rotate(by: .pi / 4)
    let gemRect = CGRect(x: -gemSize/2, y: -gemSize/2, width: gemSize, height: gemSize)
    let gemColors = [
        CGColor(red: 1.0, green: 0.98, blue: 0.85, alpha: 1.0),
        CGColor(red: 0.99, green: 0.85, blue: 0.45, alpha: 1.0)
    ] as CFArray
    if let gemGrad = CGGradient(colorsSpace: cs, colors: gemColors, locations: [0, 1]) {
        ctx.addRect(gemRect)
        ctx.clip()
        ctx.drawLinearGradient(gemGrad,
                               start: CGPoint(x: -gemSize/2, y: gemSize/2),
                               end: CGPoint(x: gemSize/2, y: -gemSize/2),
                               options: [])
    }
    ctx.restoreGState()

    // Gem stroke
    ctx.saveGState()
    ctx.translateBy(x: gemX, y: gemY)
    ctx.rotate(by: .pi / 4)
    ctx.setStrokeColor(CGColor(red: 0.4, green: 0.2, blue: 0.0, alpha: 0.5))
    ctx.setLineWidth(size * 0.006)
    ctx.stroke(CGRect(x: -gemSize/2, y: -gemSize/2, width: gemSize, height: gemSize))
    ctx.restoreGState()

    ctx.restoreGState()
    return ctx.makeImage()
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let sizes: [(name: String, px: CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (name, px) in sizes {
    if let img = renderIcon(size: px) {
        writePNG(img, to: outDir.appendingPathComponent(name))
        print("wrote \(name)")
    }
}
