// 生成 轻片 的 App 图标：swift scripts/make_icon.swift <输出 png 路径>
import AppKit

let S: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
let space = CGColorSpaceCreateDeviceRGB()

// 1. 底板：macOS 标准留边（824 / 1024），圆角方形 + 渐变
let inset: CGFloat = 100
let base = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
let basePath = CGPath(roundedRect: base, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: rgb(0x000000, 0.35))
ctx.addPath(basePath); ctx.setFillColor(rgb(0x3B82F6)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(basePath); ctx.clip()
let bg = CGGradient(colorsSpace: space, colors: [rgb(0x22D3EE), rgb(0x3B82F6), rgb(0x6D28D9)] as CFArray, locations: [0, 0.5, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: base.minX, y: base.maxY), end: CGPoint(x: base.maxX, y: base.minY), options: [])
// 顶部高光
let gloss = CGGradient(colorsSpace: space, colors: [rgb(0xFFFFFF, 0.22), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gloss, start: CGPoint(x: 0, y: base.maxY), end: CGPoint(x: 0, y: base.midY), options: [])
ctx.restoreGState()

// 2. 白色“视频画面”卡片
let card = CGRect(x: 262, y: 395, width: 500, height: 340)
let cardPath = CGPath(roundedRect: card, cornerWidth: 64, cornerHeight: 64, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: rgb(0x1E1B4B, 0.35))
ctx.addPath(cardPath); ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillPath()
ctx.restoreGState()

// 胶片齿孔（上下各一排），和 YouTube 式的纯白圆角方块区分开
ctx.saveGState()
ctx.addPath(cardPath); ctx.clip()
for row in [card.maxY - 44, card.minY + 44] {
    var x = card.minX + 46
    while x < card.maxX - 40 {
        let hole = CGRect(x: x - 17, y: row - 14, width: 34, height: 28)
        ctx.addPath(CGPath(roundedRect: hole, cornerWidth: 8, cornerHeight: 8, transform: nil))
        x += 58
    }
}
ctx.setFillColor(rgb(0x3B82F6, 0.9)); ctx.fillPath()
ctx.restoreGState()

// 3. 播放三角（渐变填充）
let tri = CGMutablePath()
let cx = card.midX + 14, cy = card.midY
tri.move(to: CGPoint(x: cx - 52, y: cy + 68))
tri.addLine(to: CGPoint(x: cx + 76, y: cy))
tri.addLine(to: CGPoint(x: cx - 52, y: cy - 68))
tri.closeSubpath()
let triRounded = tri.copy(strokingWithWidth: 30, lineCap: .round, lineJoin: .round, miterLimit: 1)
ctx.saveGState()
ctx.addPath(tri); ctx.addPath(triRounded); ctx.clip(using: .winding)
let tg = CGGradient(colorsSpace: space, colors: [rgb(0x06B6D4), rgb(0x6D28D9)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(tg, start: CGPoint(x: cx - 80, y: cy + 90), end: CGPoint(x: cx + 90, y: cy - 90), options: [])
ctx.restoreGState()

// 4. 右上角的叶子：代表“轻”
ctx.saveGState()
ctx.translateBy(x: 742, y: 742)
ctx.rotate(by: -.pi / 4.2)
let leaf = CGMutablePath()
let L: CGFloat = 230, Wd: CGFloat = 92
leaf.move(to: CGPoint(x: 0, y: -L / 2))
leaf.addCurve(to: CGPoint(x: 0, y: L / 2), control1: CGPoint(x: Wd, y: -L / 4), control2: CGPoint(x: Wd * 0.8, y: L / 3))
leaf.addCurve(to: CGPoint(x: 0, y: -L / 2), control1: CGPoint(x: -Wd * 0.8, y: L / 3), control2: CGPoint(x: -Wd, y: -L / 4))
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: rgb(0x1E1B4B, 0.35))
ctx.addPath(leaf)
ctx.setFillColor(rgb(0xA3E635)); ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)
// 叶柄
ctx.setStrokeColor(rgb(0x65A30D)); ctx.setLineWidth(12); ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: 0, y: -L / 2 + 10)); ctx.addLine(to: CGPoint(x: 0, y: -L / 2 - 34)); ctx.strokePath()
// 叶脉（裁剪在叶子内部）
ctx.addPath(leaf); ctx.clip()
ctx.setStrokeColor(rgb(0x4D7C0F, 0.75)); ctx.setLineWidth(10); ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: 0, y: -L / 2)); ctx.addLine(to: CGPoint(x: 0, y: L / 2 - 20)); ctx.strokePath()
ctx.setLineWidth(7)
for (y, dx) in [(-30.0, 38.0), (25.0, 34.0), (72.0, 24.0)] {
    ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: dx, y: y + 30)); ctx.strokePath()
    ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: -dx, y: y + 30)); ctx.strokePath()
}
ctx.restoreGState()

// 5. 下方两道向内收的箭头：代表“压缩”
ctx.setStrokeColor(rgb(0xFFFFFF, 0.92)); ctx.setLineWidth(30); ctx.setLineCap(.round); ctx.setLineJoin(.round)
let ay: CGFloat = 300
for dir in [-1.0, 1.0] {
    let tip = CGPoint(x: 512 + dir * 36, y: ay)
    ctx.move(to: CGPoint(x: 512 + dir * 190, y: ay)); ctx.addLine(to: tip); ctx.strokePath()
    ctx.move(to: CGPoint(x: tip.x + dir * 52, y: ay + 52)); ctx.addLine(to: tip)
    ctx.addLine(to: CGPoint(x: tip.x + dir * 52, y: ay - 52)); ctx.strokePath()
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("已生成 \(out)")
