#!/usr/bin/env swift
// 生成 OCI Start 应用图标 — 方案 B：立体云 + 发光启动箭头
import AppKit
import CoreGraphics

let outDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "OciStart/Assets.xcassets/AppIcon.appiconset"

let sizes = [16, 32, 64, 128, 256, 512, 1024]

// MARK: - Colors

private func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
}

// MARK: - Bitmap

private func makeBitmap(size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)
    return rep
}

private func clipRoundedRect(_ ctx: CGContext, rect: CGRect, radius: CGFloat) {
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path)
    ctx.clip()
}

private func fillRadial(
    _ ctx: CGContext,
    center: CGPoint,
    radius: CGFloat,
    colors: [NSColor],
    locations: [CGFloat]? = nil
) {
    let cgColors = colors.map { $0.cgColor } as CFArray
    guard let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: cgColors,
        locations: locations
    ) else { return }
    ctx.drawRadialGradient(
        gradient,
        startCenter: center, startRadius: 0,
        endCenter: center, endRadius: radius,
        options: [.drawsAfterEndLocation]
    )
}

private func fillLinear(
    _ ctx: CGContext,
    start: CGPoint,
    end: CGPoint,
    colors: [NSColor],
    locations: [CGFloat]? = nil
) {
    let cgColors = colors.map { $0.cgColor } as CFArray
    guard let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: cgColors,
        locations: locations
    ) else { return }
    ctx.drawLinearGradient(gradient, start: start, end: end, options: [])
}

/// 经典云形：单条闭合贝塞尔（干净外轮廓，无内部圆线）
private func cloudPath(in box: CGRect) -> CGPath {
    let path = CGMutablePath()
    let w = box.width
    let h = box.height
    let o = box.origin

    // 归一化点 → box
    func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: o.x + x * w, y: o.y + y * h)
    }

    // 从左下角开始，顺时针走一圈（y 向上）
    path.move(to: P(0.12, 0.32))
    // 左下鼓包
    path.addCurve(to: P(0.08, 0.48), control1: P(0.05, 0.32), control2: P(0.02, 0.40))
    // 左上鼓包
    path.addCurve(to: P(0.22, 0.68), control1: P(0.08, 0.60), control2: P(0.12, 0.68))
    // 中左峰
    path.addCurve(to: P(0.42, 0.78), control1: P(0.28, 0.78), control2: P(0.34, 0.82))
    // 主峰
    path.addCurve(to: P(0.68, 0.72), control1: P(0.52, 0.86), control2: P(0.62, 0.82))
    // 右上
    path.addCurve(to: P(0.88, 0.52), control1: P(0.80, 0.72), control2: P(0.90, 0.64))
    // 右下
    path.addCurve(to: P(0.82, 0.30), control1: P(0.92, 0.42), control2: P(0.90, 0.32))
    // 底边回左
    path.addCurve(to: P(0.12, 0.32), control1: P(0.62, 0.18), control2: P(0.28, 0.18))
    path.closeSubpath()
    return path
}

private func drawIcon(into rep: NSBitmapImageRep, pixelSize: Int) {
    NSGraphicsContext.saveGraphicsState()
    guard let nsCtx = NSGraphicsContext(bitmapImageRep: rep) else {
        NSGraphicsContext.restoreGraphicsState()
        return
    }
    NSGraphicsContext.current = nsCtx
    let ctx = nsCtx.cgContext
    let s = CGFloat(pixelSize)
    let rect = CGRect(x: 0, y: 0, width: s, height: s)

    ctx.clear(rect)

    // —— 圆角裁剪 ——
    let corner = s * 0.223
    clipRoundedRect(ctx, rect: rect, radius: corner)

    // —— 背景：左下靛蓝 → 右上亮青 ——
    fillLinear(
        ctx,
        start: CGPoint(x: 0, y: 0),
        end: CGPoint(x: s * 0.95, y: s),
        colors: [
            rgba(0.16, 0.10, 0.52),
            rgba(0.08, 0.32, 0.92),
            rgba(0.12, 0.52, 1.00),
            rgba(0.30, 0.78, 1.00),
        ],
        locations: [0, 0.32, 0.65, 1.0]
    )

    // —— 右上光晕 ——
    ctx.saveGState()
    ctx.setBlendMode(.plusLighter)
    fillRadial(
        ctx,
        center: CGPoint(x: s * 0.74, y: s * 0.80),
        radius: s * 0.40,
        colors: [
            rgba(1.0, 1.0, 1.0, 0.70),
            rgba(0.55, 0.85, 1.0, 0.28),
            rgba(0.2, 0.5, 1.0, 0.0),
        ],
        locations: [0, 0.35, 1.0]
    )
    ctx.restoreGState()

    // —— 云区域 ——
    let cloudBox = CGRect(x: s * 0.11, y: s * 0.24, width: s * 0.78, height: s * 0.50)
    let cPath = cloudPath(in: cloudBox)

    // 云阴影
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -s * 0.028),
        blur: s * 0.055,
        color: rgba(0.0, 0.05, 0.25, 0.40).cgColor
    )
    ctx.addPath(cPath)
    ctx.setFillColor(rgba(1, 1, 1, 1).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // 云填充渐变（顶白 → 底微蓝）
    ctx.saveGState()
    ctx.addPath(cPath)
    ctx.clip()
    fillLinear(
        ctx,
        start: CGPoint(x: cloudBox.midX, y: cloudBox.maxY),
        end: CGPoint(x: cloudBox.midX, y: cloudBox.minY),
        colors: [
            rgba(1.00, 1.00, 1.00),
            rgba(0.96, 0.97, 1.00),
            rgba(0.86, 0.90, 0.98),
        ],
        locations: [0, 0.5, 1.0]
    )
    // 顶侧高光
    fillRadial(
        ctx,
        center: CGPoint(x: cloudBox.midX + s * 0.04, y: cloudBox.maxY - s * 0.04),
        radius: s * 0.30,
        colors: [
            rgba(1, 1, 1, 0.65),
            rgba(1, 1, 1, 0.0),
        ]
    )
    // 左侧柔和暗部（体积感）
    fillRadial(
        ctx,
        center: CGPoint(x: cloudBox.minX + s * 0.08, y: cloudBox.minY + s * 0.10),
        radius: s * 0.28,
        colors: [
            rgba(0.55, 0.62, 0.82, 0.22),
            rgba(0.55, 0.62, 0.82, 0.0),
        ]
    )
    ctx.restoreGState()

    // —— 启动徽章（深蓝圆 + 发光箭头） ——
    let badgeC = CGPoint(x: s * 0.58, y: s * 0.36)
    let badgeR = s * (pixelSize <= 32 ? 0.155 : 0.138)

    // 徽章阴影
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -s * 0.01),
        blur: s * 0.02,
        color: rgba(0, 0.05, 0.3, 0.35).cgColor
    )
    ctx.setFillColor(rgba(0.03, 0.12, 0.42, 1).cgColor)
    ctx.fillEllipse(in: CGRect(
        x: badgeC.x - badgeR, y: badgeC.y - badgeR,
        width: badgeR * 2, height: badgeR * 2
    ))
    ctx.restoreGState()

    // 徽章底（径向微光）
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(
        x: badgeC.x - badgeR, y: badgeC.y - badgeR,
        width: badgeR * 2, height: badgeR * 2
    ))
    ctx.clip()
    fillRadial(
        ctx,
        center: CGPoint(x: badgeC.x, y: badgeC.y + badgeR * 0.15),
        radius: badgeR * 1.15,
        colors: [
            rgba(0.08, 0.32, 0.78),
            rgba(0.03, 0.14, 0.48),
            rgba(0.02, 0.08, 0.32),
        ],
        locations: [0, 0.55, 1.0]
    )
    ctx.restoreGState()

    // 徽章细描边
    if pixelSize >= 64 {
        ctx.setStrokeColor(rgba(0.35, 0.65, 1.0, 0.35).cgColor)
        ctx.setLineWidth(max(1, s * 0.006))
        ctx.strokeEllipse(in: CGRect(
            x: badgeC.x - badgeR, y: badgeC.y - badgeR,
            width: badgeR * 2, height: badgeR * 2
        ))
    }

    // —— 发光 chevron ^ ——
    let halfW = badgeR * 0.42
    let rise = badgeR * 0.38
    let ay = badgeC.y - badgeR * 0.08

    func strokeChevron(width: CGFloat, color: NSColor, blur: CGFloat) {
        ctx.saveGState()
        if blur > 0 {
            ctx.setShadow(offset: .zero, blur: blur, color: color.cgColor)
        }
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.move(to: CGPoint(x: badgeC.x - halfW, y: ay))
        ctx.addLine(to: CGPoint(x: badgeC.x, y: ay + rise))
        ctx.addLine(to: CGPoint(x: badgeC.x + halfW, y: ay))
        ctx.strokePath()
        ctx.restoreGState()
    }

    if pixelSize >= 32 {
        strokeChevron(width: max(1.5, s * 0.032), color: rgba(0.25, 0.90, 1.0, 0.9), blur: s * 0.028)
    }
    strokeChevron(width: max(1.2, s * 0.024), color: rgba(0.70, 0.97, 1.0, 1.0), blur: 0)

    // —— 放射线（≥64） ——
    if pixelSize >= 64 {
        let rayCount = 5
        let rayInner = badgeR * 0.48
        let rayOuter = badgeR * 0.78
        let baseAngle = CGFloat.pi / 2
        let spread: CGFloat = 0.95
        let rayY = badgeC.y + badgeR * 0.02
        ctx.setStrokeColor(rgba(0.45, 0.92, 1.0, 0.88).cgColor)
        ctx.setLineWidth(max(1.0, s * 0.011))
        ctx.setLineCap(.round)
        for i in 0..<rayCount {
            let t = CGFloat(i) / CGFloat(rayCount - 1)
            let angle = baseAngle - spread + t * (spread * 2)
            let c = cos(angle)
            let sn = sin(angle)
            ctx.move(to: CGPoint(x: badgeC.x + c * rayInner, y: rayY + sn * rayInner))
            ctx.addLine(to: CGPoint(x: badgeC.x + c * rayOuter, y: rayY + sn * rayOuter))
            ctx.strokePath()
        }
    }

    // —— 顶部玻璃高光 ——
    if pixelSize >= 64 {
        ctx.saveGState()
        clipRoundedRect(ctx, rect: rect, radius: corner)
        fillLinear(
            ctx,
            start: CGPoint(x: 0, y: s),
            end: CGPoint(x: 0, y: s * 0.58),
            colors: [
                rgba(1, 1, 1, 0.16),
                rgba(1, 1, 1, 0.0),
            ]
        )
        ctx.restoreGState()
    }

    nsCtx.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
}

// MARK: - Generate

for size in sizes {
    let rep = makeBitmap(size: size)
    drawIcon(into: rep, pixelSize: size)

    guard let png = rep.representation(using: .png, properties: [:]) else {
        print("❌ 生成 icon_\(size).png 失败")
        continue
    }
    let path = "\(outDir)/icon_\(size).png"
    do {
        try png.write(to: URL(fileURLWithPath: path))
        print("✅ \(path)")
    } catch {
        print("❌ 写入 \(path) 失败: \(error)")
    }
}
print("图标生成完毕（方案 B：立体云 + 启动箭头）")
