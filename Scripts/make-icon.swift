import AppKit
import CoreGraphics

// Usage: swift icon2.swift <variant: default|dark|tinted> <out.png>
let variant = CommandLine.arguments[1]
let outPath = CommandLine.arguments[2]
let S: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: variant == "default" ? CGImageAlphaInfo.noneSkipLast.rawValue
                                                     : CGImageAlphaInfo.premultipliedLast.rawValue)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

let c = CGPoint(x: S / 2, y: S / 2)

// Background
if variant == "default" {
    let bg = CGGradient(colorsSpace: cs, colors: [rgb(0x2E2E34), rgb(0x0C0C0E)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: S * 0.2, y: S), end: CGPoint(x: S * 0.8, y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    // soft warm glow behind the ring
    let glow = CGGradient(colorsSpace: cs, colors: [rgb(0xFF6A2B, 0.22), rgb(0xFF6A2B, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: c, startRadius: 0, endCenter: c, endRadius: S * 0.5, options: [])
} else {
    ctx.clear(CGRect(x: 0, y: 0, width: S, height: S))
}

// Ring: faint full track + gradient arc (like a countdown with a bit left)
let radius: CGFloat = 338
let lineW: CGFloat = 88
ctx.setLineWidth(lineW)
ctx.setLineCap(.round)
ctx.setStrokeColor(variant == "tinted" ? rgb(0xFFFFFF, 0.18) : rgb(0xFFFFFF, 0.08))
ctx.addArc(center: c, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
ctx.strokePath()

let startA = CGFloat.pi / 2              // 12 o'clock
let sweep = CGFloat.pi * 2 * 0.78
ctx.saveGState()
ctx.addArc(center: c, radius: radius, startAngle: startA, endAngle: startA - sweep, clockwise: true)
ctx.replacePathWithStrokedPath()
ctx.clip()
if variant == "tinted" {
    ctx.setFillColor(rgb(0xFFFFFF))
    ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))
} else {
    // Conic gradient by hand: thin wedges, colour by position along the sweep.
    let stops: [(CGFloat, (CGFloat, CGFloat, CGFloat))] = [(0, (1.00, 0.69, 0.18)), (0.45, (1.00, 0.42, 0.17)), (1, (0.91, 0.20, 0.11))]
    func color(_ f: CGFloat) -> CGColor {
        let f = min(max(f, 0), 1)
        let i = stops.lastIndex { $0.0 <= f } ?? 0
        let (f0, a) = stops[i], (f1, b) = stops[min(i + 1, stops.count - 1)]
        let t = f1 > f0 ? (f - f0) / (f1 - f0) : 0
        return CGColor(srgbRed: a.0 + (b.0 - a.0) * t, green: a.1 + (b.1 - a.1) * t, blue: a.2 + (b.2 - a.2) * t, alpha: 1)
    }
    let n = 720
    for k in 0..<n {
        let cw = CGFloat(k) / CGFloat(n) * .pi * 2          // clockwise distance from 12 o'clock
        var f = cw / sweep
        if f > 1 { f = cw > sweep + (.pi * 2 - sweep) / 2 ? 0 : 1 }  // round caps take the end colours
        let a0 = startA - cw, a1 = startA - cw - (.pi * 2 / CGFloat(n)) * 1.5
        ctx.move(to: c)
        ctx.addArc(center: c, radius: S, startAngle: a0, endAngle: a1, clockwise: true)
        ctx.closePath()
        ctx.setFillColor(color(f))
        ctx.fillPath()
    }
}
ctx.restoreGState()

// Dumbbell, rotated 45°
ctx.saveGState()
ctx.translateBy(x: c.x, y: c.y)
ctx.rotate(by: .pi / 4)
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0x000000, variant == "tinted" ? 0 : 0.45))
let fg = variant == "tinted" ? rgb(0xD9D9D9) : rgb(0xFFFFFF)
ctx.setFillColor(fg)
func rr(_ r: CGRect, _ corner: CGFloat) {
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: corner, cornerHeight: corner, transform: nil))
    ctx.fillPath()
}
ctx.beginTransparencyLayer(auxiliaryInfo: nil)
rr(CGRect(x: -200, y: -24, width: 400, height: 48), 24)                 // bar
for sx in [-1.0, 1.0] as [CGFloat] {
    rr(CGRect(x: sx * 150 - 36, y: -132, width: 72, height: 264), 26)   // inner plate
    rr(CGRect(x: sx * 222 - 28, y: -94, width: 56, height: 188), 22)    // outer plate
}
ctx.endTransparencyLayer()
ctx.restoreGState()

let img = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
