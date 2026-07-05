#!/usr/bin/env swift
// 生成 OCI Start 应用图标
import AppKit

let outDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "OciStart/Assets.xcassets/AppIcon.appiconset"

let sizes = [16, 32, 64, 128, 256, 512, 1024]

for size in sizes {
    let s = CGFloat(size)
    let img = NSImage(size: NSSize(width: s, height: s), flipped: false) { rect in
        // 圆角蓝色背景
        let radius = s * 0.22
        let bgPath = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSColor(calibratedRed: 0.05, green: 0.40, blue: 0.90, alpha: 1.0).setFill()
        bgPath.fill()

        // 白色云图标（用 SF Symbol）
        let symSize = s * 0.52
        let cfg = NSImage.SymbolConfiguration(pointSize: symSize, weight: .medium)
        if let cloud = NSImage(systemSymbolName: "cloud.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg) {
            let cx = (s - cloud.size.width)  / 2
            let cy = (s - cloud.size.height) / 2 + s * 0.08
            NSColor.white.set()
            cloud.draw(in: NSRect(x: cx, y: cy, width: cloud.size.width, height: cloud.size.height),
                       from: .zero, operation: .sourceOver, fraction: 1.0)
        }

        // "OCI" 文字
        let fs = s * 0.19
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: fs),
            .foregroundColor: NSColor.white.withAlphaComponent(0.92)
        ]
        let label = "OCI" as NSString
        let ts = label.size(withAttributes: attrs)
        label.draw(at: NSPoint(x: (s - ts.width) / 2, y: s * 0.09), withAttributes: attrs)

        return true
    }

    guard let tiff = img.tiffRepresentation,
          let rep  = NSBitmapImageRep(data: tiff),
          let png  = rep.representation(using: .png, properties: [:]) else {
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
print("图标生成完毕")
