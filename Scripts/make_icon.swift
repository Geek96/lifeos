#!/usr/bin/env swift
// 生成 App 图标：青绿→翠绿渐变的圆角方形（与 CourseOS 同一形制），白色日历页 + 右下太阳徽章。
// 没有对勾：LifeOS 不是清单。
// 用法：swift Scripts/make_icon.swift LifeOS/Resources/Assets.xcassets/AppIcon.appiconset
// 不使用 SF Symbols（其授权不允许用于 App 图标），全部用路径绘制。
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

/// 在 1024 画布上画（坐标以左上为原点，内部翻转）
func render(size: Int) -> Data {
    let s = CGFloat(size) / 1024
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: s, y: s)
    ctx.translateBy(x: 0, y: 1024)
    ctx.scaleBy(x: 1, y: -1)

    // 主体：824×824，居中，留阴影位（与 CourseOS 一致）
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: color(0x000000, 0.28))
    ctx.addPath(bodyPath)
    ctx.setFillColor(color(0x0F9F8F))
    ctx.fillPath()
    ctx.restoreGState()

    // 渐变：左上青 → 右下翠绿
    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    let grad = CGGradient(colorsSpace: cs, colors: [color(0x22C1C3), color(0x14A89A), color(0x22B573)] as CFArray,
                          locations: [0, 0.45, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 100, y: 100), end: CGPoint(x: 924, y: 924), options: [])
    let gloss = CGGradient(colorsSpace: cs, colors: [color(0xFFFFFF, 0.16), color(0xFFFFFF, 0)] as CFArray,
                           locations: [0, 1])!
    ctx.drawLinearGradient(gloss, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 520), options: [])
    ctx.restoreGState()

    // 日历页：白色圆角卡片
    let page = CGRect(x: 214, y: 250, width: 596, height: 540)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 24, color: color(0x064E3B, 0.30))
    ctx.addPath(CGPath(roundedRect: page, cornerWidth: 70, cornerHeight: 70, transform: nil))
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()
    // 页眉色带
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: page, cornerWidth: 70, cornerHeight: 70, transform: nil))
    ctx.clip()
    ctx.setFillColor(color(0xD7F5EE))
    ctx.fill(CGRect(x: page.minX, y: page.minY, width: page.width, height: 132))
    ctx.restoreGState()
    // 两个装订环
    for x in [CGFloat(360), 664] {
        ctx.addPath(CGPath(roundedRect: CGRect(x: x - 22, y: 200, width: 44, height: 110),
                           cornerWidth: 22, cornerHeight: 22, transform: nil))
        ctx.setFillColor(color(0xFFFFFF))
        ctx.fillPath()
        ctx.addPath(CGPath(roundedRect: CGRect(x: x - 22, y: 200, width: 44, height: 110),
                           cornerWidth: 22, cornerHeight: 22, transform: nil))
        ctx.setStrokeColor(color(0x0F9F8F, 0.35))
        ctx.setLineWidth(8)
        ctx.strokePath()
    }

    // 格子：3 行 × 4 列的小圆角方块
    let cols = 4, rows = 3
    let gx: CGFloat = 268, gy: CGFloat = 438, cw: CGFloat = 104, ch: CGFloat = 84, gap: CGFloat = 26
    func cell(_ r: Int, _ c: Int) -> CGRect {
        CGRect(x: gx + CGFloat(c) * (cw + gap), y: gy + CGFloat(r) * (ch + gap), width: cw, height: ch)
    }
    for r in 0..<rows {
        for c in 0..<cols {
            ctx.addPath(CGPath(roundedRect: cell(r, c), cornerWidth: 18, cornerHeight: 18, transform: nil))
            ctx.setFillColor(color(0xE6EEF0))
            ctx.fillPath()
        }
    }
    // 一条跨几天的浅色时间窗
    let band = cell(1, 0).union(cell(1, 2))
    ctx.addPath(CGPath(roundedRect: band, cornerWidth: 18, cornerHeight: 18, transform: nil))
    ctx.setFillColor(color(0x8EE3C8))
    ctx.fillPath()
    // 一个约定（蓝）
    ctx.addPath(CGPath(roundedRect: cell(0, 1), cornerWidth: 18, cornerHeight: 18, transform: nil))
    ctx.setFillColor(color(0x5B8DEF))
    ctx.fillPath()
    // 今天（橙）
    ctx.addPath(CGPath(roundedRect: cell(0, 3), cornerWidth: 18, cornerHeight: 18, transform: nil))
    ctx.setFillColor(color(0xF59E0B))
    ctx.fillPath()

    // 右下：太阳徽章
    let badge = CGPoint(x: 748, y: 724)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 6), blur: 16, color: color(0x064E3B, 0.35))
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillEllipse(in: CGRect(x: badge.x - 118, y: badge.y - 118, width: 236, height: 236))
    ctx.restoreGState()
    ctx.setFillColor(color(0xF59E0B))
    ctx.fillEllipse(in: CGRect(x: badge.x - 44, y: badge.y - 44, width: 88, height: 88))
    ctx.setStrokeColor(color(0xF59E0B))
    ctx.setLineWidth(22)
    ctx.setLineCap(.round)
    for i in 0..<8 {
        let a = CGFloat(i) * .pi / 4
        ctx.move(to: CGPoint(x: badge.x + cos(a) * 66, y: badge.y + sin(a) * 66))
        ctx.addLine(to: CGPoint(x: badge.x + cos(a) * 88, y: badge.y + sin(a) * 88))
    }
    ctx.strokePath()

    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .png, properties: [:])!
}

let specs: [(points: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var images: [[String: String]] = []
for spec in specs {
    let px = spec.points * spec.scale
    let name = "icon_\(spec.points)x\(spec.points)\(spec.scale == 2 ? "@2x" : "").png"
    try render(size: px).write(to: outDir.appendingPathComponent(name))
    images.append(["idiom": "mac", "size": "\(spec.points)x\(spec.points)", "scale": "\(spec.scale)x", "filename": name])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: outDir.appendingPathComponent("Contents.json"))
print("wrote \(specs.count) icons to \(outDir.path)")
