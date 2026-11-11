import AppKit
import CoreGraphics
import Foundation

// A2 方案：俯视键盘 + 底部 KeyLayer 字标，透明底、玻璃质感、悬浮投影。
// 小尺寸（16–64px）自动改用无字标的紧凑版，避免文字糊成一团。

let ROOT = FileManager.default.currentDirectoryPath
let ICONS = ROOT + "/assets/icons"
let WINICONS = ROOT + "/windows/src-tauri/icons"
for d in [ICONS, WINICONS] {
    try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
}

func cg(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

func ns(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

func ctx(_ side: Int) -> CGContext? {
    CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
}

func pngData(_ c: CGContext) -> Data? {
    guard let img = c.makeImage() else { return nil }
    return NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])
}

func save(_ data: Data, _ path: String) {
    do {
        try data.write(to: URL(fileURLWithPath: path))
        print("生成 \(path.replacingOccurrences(of: ROOT + "/", with: ""))")
    } catch {
        print("写入失败 \(path): \(error)")
    }
}

func rr(_ c: CGContext, _ rect: CGRect, _ r: CGFloat, fill: CGColor,
        stroke: CGColor? = nil, width: CGFloat = 0) {
    let p = CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
    c.addPath(p); c.setFillColor(fill); c.fillPath()
    if let s = stroke {
        c.addPath(p); c.setStrokeColor(s); c.setLineWidth(width); c.strokePath()
    }
}

func gradientIn(_ c: CGContext, _ path: CGPath, _ top: CGColor, _ bottom: CGColor,
                _ y0: CGFloat, _ y1: CGFloat) {
    c.saveGState()
    c.addPath(path); c.clip()
    if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [top, bottom] as CFArray, locations: [0, 1]) {
        c.drawLinearGradient(g, start: CGPoint(x: 0, y: y0),
                             end: CGPoint(x: 0, y: y1), options: [])
    }
    c.restoreGState()
}

func arrows(_ c: CGContext, _ lines: [[(CGFloat, CGFloat)]], _ col: CGColor, _ lw: CGFloat) {
    c.setStrokeColor(col); c.setLineWidth(lw)
    c.setLineCap(.round); c.setLineJoin(.round)
    for line in lines {
        c.beginPath()
        for (i, p) in line.enumerated() {
            let pt = CGPoint(x: p.0, y: p.1)
            if i == 0 { c.move(to: pt) } else { c.addLine(to: pt) }
        }
        c.strokePath()
    }
}

func label(_ c: CGContext, _ s: String, _ cx: CGFloat, _ cy: CGFloat,
           _ size: CGFloat, _ weight: NSFont.Weight, _ col: NSColor) {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    let attr = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: col])
    let sz = attr.size()
    let rect = CGRect(x: cx - sz.width / 2, y: cy - sz.height / 2,
                      width: sz.width, height: sz.height)
    let g = NSGraphicsContext(cgContext: c, flipped: true)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = g
    attr.draw(in: rect)
    NSGraphicsContext.restoreGraphicsState()
}

let keyArrows: [[[(CGFloat, CGFloat)]]] = [
    [[(16, 16), (16, 66)], [(60, 41), (26, 41)], [(42, 26), (26, 41), (42, 56)]],
    [[(41, 66), (41, 16)], [(25, 32), (41, 16), (57, 32)]],
    [[(66, 16), (66, 66)], [(22, 41), (56, 41)], [(42, 26), (56, 41), (42, 56)]],
    [[(66, 41), (16, 41)], [(32, 26), (16, 41), (32, 56)]],
    [[(41, 16), (41, 66)], [(25, 50), (41, 66), (57, 50)]],
    [[(16, 41), (66, 41)], [(50, 26), (66, 41), (50, 56)]],
]

func drawApp(_ c: CGContext, _ side: CGFloat, wordmark: Bool) {
    let k = side / 1024
    c.saveGState()
    c.translateBy(x: 0, y: side)
    c.scaleBy(x: 1, y: -1)
    c.scaleBy(x: k, y: k)

    let panel = CGRect(x: 100, y: 100, width: 824, height: 824)
    let panelPath = CGPath(roundedRect: panel, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // 悬浮投影 + 半透明底层
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: 24), blur: 64, color: cg(0x0C447C, 0.22))
    c.addPath(panelPath)
    c.setFillColor(cg(0xFFFFFF, 0.88))
    c.fillPath()
    c.restoreGState()

    // 玻璃渐变与内高光
    gradientIn(c, panelPath, cg(0xFFFFFF, 0.96), cg(0xE6F1FB, 0.72), panel.minY, panel.maxY)
    c.addPath(panelPath); c.setStrokeColor(cg(0xFFFFFF, 0.95)); c.setLineWidth(6); c.strokePath()
    c.addPath(panelPath); c.setStrokeColor(cg(0x185FA5, 0.18)); c.setLineWidth(2); c.strokePath()

    // 键盘底板：再抬一层
    let slabY: CGFloat = wordmark ? 250 : 322
    let slab = CGRect(x: 157, y: slabY, width: 711, height: 380)
    let slabPath = CGPath(roundedRect: slab, cornerWidth: 54, cornerHeight: 54, transform: nil)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: 18), blur: 38, color: cg(0x0C447C, 0.16))
    c.addPath(slabPath); c.setFillColor(cg(0xFFFFFF, 0.97)); c.fillPath()
    c.restoreGState()
    c.addPath(slabPath); c.setStrokeColor(cg(0x185FA5)); c.setLineWidth(6); c.strokePath()

    // 键帽
    let cols: [CGFloat] = [178, 276, 374, 472, 570, 668, 766]
    let row0 = slabY + 34
    let rows: [CGFloat] = [row0, row0 + 98, row0 + 196]
    let key: CGFloat = 82
    for (ri, y) in rows.enumerated() {
        for x in cols {
            if ri >= 1 && (x == 472 || x == 570 || x == 668) { continue }
            rr(c, CGRect(x: x, y: y, width: key, height: key), 18,
               fill: cg(0xFFFFFF, 0.96), stroke: cg(0xB5D4F4), width: 2)
        }
    }
    rr(c, CGRect(x: 384, y: slabY + 328, width: 256, height: 36), 12,
       fill: cg(0xFFFFFF, 0.96), stroke: cg(0xB5D4F4), width: 2)

    // 六个被改写的键
    let highlights: [(CGFloat, CGFloat, Int)] = [
        (472, rows[1], 0), (570, rows[1], 1), (668, rows[1], 2),
        (472, rows[2], 3), (570, rows[2], 4), (668, rows[2], 5),
    ]
    for (x, y, idx) in highlights {
        rr(c, CGRect(x: x, y: y, width: key, height: key), 18, fill: cg(0x185FA5))
        c.saveGState()
        c.translateBy(x: x, y: y)
        arrows(c, keyArrows[idx], cg(0xFFFFFF), 6)
        c.restoreGState()
    }

    if wordmark {
        label(c, "KeyLayer", 512, 750, 76, .medium, ns(0x0C447C))
    }

    c.restoreGState()
}

func menuIcon(_ px: Int) {
    guard let c = ctx(px) else { return }
    let s = CGFloat(px) / 32
    c.translateBy(x: 0, y: CGFloat(px))
    c.scaleBy(x: 1, y: -1)
    c.scaleBy(x: s, y: s)
    let frame = CGPath(roundedRect: CGRect(x: 2, y: 3, width: 28, height: 26),
                       cornerWidth: 4, cornerHeight: 4, transform: nil)
    c.addPath(frame); c.setStrokeColor(cg(0x000000)); c.setLineWidth(2); c.strokePath()
    c.setStrokeColor(cg(0x000000)); c.setLineWidth(1.4); c.setLineCap(.round)
    for i in 0..<3 {
        let y = 9 + CGFloat(i) * 6
        c.beginPath()
        c.move(to: CGPoint(x: 6, y: y))
        c.addLine(to: CGPoint(x: 26, y: y))
        c.strokePath()
    }
    c.setFillColor(cg(0x000000))
    c.fill(CGRect(x: 14, y: 13, width: 5, height: 5))
    if let d = pngData(c) {
        save(d, ICONS + (px == 16 ? "/MenuIcon.png" : "/MenuIcon@2x.png"))
    }
}

func trayIcon(_ px: Int) -> Data? {
    guard let c = ctx(px) else { return nil }
    let s = CGFloat(px) / 32
    c.translateBy(x: 0, y: CGFloat(px))
    c.scaleBy(x: 1, y: -1)
    c.scaleBy(x: s, y: s)
    let w: CGFloat = 8
    let gap: CGFloat = 2
    for row in 0..<2 {
        for col in 0..<3 {
            let x = 2 + CGFloat(col) * (w + gap)
            let y = 7 + CGFloat(row) * (w + gap)
            rr(c, CGRect(x: x, y: y, width: w, height: w), 2, fill: cg(0x185FA5))
        }
    }
    return pngData(c)
}

func writeICO(_ png: Data, _ path: String) {
    var data = Data([0, 0, 1, 0, 1, 0])
    var entry = Data([0, 0, 0, 0, 1, 0, 32, 0])
    var size = UInt32(png.count).littleEndian
    withUnsafeBytes(of: &size) { entry.append(contentsOf: $0) }
    var offset = UInt32(22).littleEndian
    withUnsafeBytes(of: &offset) { entry.append(contentsOf: $0) }
    data.append(entry)
    data.append(png)
    save(data, path)
}

// 大尺寸：带字标；小尺寸：紧凑版
if let c = ctx(1024) {
    drawApp(c, 1024, wordmark: true)
    if let d = pngData(c) { save(d, ICONS + "/AppIcon-1024.png") }
}
if let c = ctx(1024) {
    drawApp(c, 1024, wordmark: false)
    if let d = pngData(c) { save(d, ICONS + "/AppIcon-small-1024.png") }
}
if let c = ctx(256) {
    drawApp(c, 256, wordmark: false)
    if let d = pngData(c) {
        save(d, ICONS + "/AppIcon-256.png")
        writeICO(d, WINICONS + "/icon.ico")
    }
}

// 预览图，便于目视检查
if let c = ctx(512) {
    c.setFillColor(cg(0xECEAE4))
    c.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
    drawApp(c, 512, wordmark: true)
    if let d = pngData(c) { save(d, "/tmp/keymap-icon-preview.png") }
}
if let c = ctx(64) {
    c.setFillColor(cg(0xECEAE4))
    c.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
    drawApp(c, 64, wordmark: false)
    if let d = pngData(c) { save(d, "/tmp/keymap-icon-64.png") }
}

menuIcon(16)
menuIcon(32)
if let d = trayIcon(32) { save(d, WINICONS + "/tray.png") }
