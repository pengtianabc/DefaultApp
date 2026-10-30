import AppKit

// 生成 DefaultApp.app 的应用图标：
// 蓝紫渐变圆角底 + 白色折角文档 + 右下角绿色对勾徽标（“已设为默认”的隐喻）。
// 用法: icongen <输出目录.iconset>

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("usage: icongen <output.iconset dir>\n".utf8))
    exit(2)
}
let outDir = args[1]
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let topColor = NSColor(calibratedRed: 0.24, green: 0.52, blue: 0.96, alpha: 1) // 蓝
let bottomColor = NSColor(calibratedRed: 0.50, green: 0.36, blue: 0.94, alpha: 1) // 紫
let badgeGreen = NSColor(calibratedRed: 0.19, green: 0.82, blue: 0.35, alpha: 1)

func tintedSymbol(_ name: String, pointSize: CGFloat) -> NSImage? {
    guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil),
          let configured = symbol.withSymbolConfiguration(
              NSImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)) else {
        return nil
    }
    let tinted = NSImage(size: configured.size, flipped: false) { r in
        NSColor.clear.set()
        r.fill()
        configured.draw(in: r)
        NSColor.white.set()
        r.fill(using: .sourceAtop)
        return true
    }
    return tinted
}

func makeIcon(pixels: Int, path: String) {
    let s = CGFloat(pixels)
    // 边距：与系统图标观感一致（图形占画布约 85%，四周留白），
    // 否则满幅绘制在访达/程序坞里会显得比 neighboring 图标大一圈。
    let marginRatio: CGFloat = 0.075
    let margin = s * marginRatio
    let scale = 1 - marginRatio * 2
    let image = NSImage(size: NSSize(width: s, height: s), flipped: false) { _ in
        NSColor.clear.set()
        NSRect(x: 0, y: 0, width: s, height: s).fill()
        NSGraphicsContext.current?.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.translateBy(x: margin, y: margin)
        NSGraphicsContext.current?.cgContext.scaleBy(x: scale, y: scale)

        let rect = NSRect(x: 0, y: 0, width: s, height: s)

        // 渐变圆角底
        let bg = NSBezierPath(roundedRect: rect, xRadius: s * 0.22, yRadius: s * 0.22)
        NSGradient(colors: [topColor, bottomColor])?.draw(in: bg, angle: -45)

        // 白色折角文档（AppKit 坐标，原点左下）
        let docLeft = s * 0.27, docRight = s * 0.71
        let docBottom = s * 0.24, docTop = s * 0.84
        let fold = s * 0.15
        let doc = NSBezierPath()
        doc.move(to: NSPoint(x: docLeft, y: docBottom))
        doc.line(to: NSPoint(x: docLeft, y: docTop))
        doc.line(to: NSPoint(x: docRight - fold, y: docTop))
        doc.line(to: NSPoint(x: docRight, y: docTop - fold))
        doc.line(to: NSPoint(x: docRight, y: docBottom))
        doc.close()
        doc.lineJoinStyle = .round

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
        shadow.shadowBlurRadius = s * 0.02
        shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
        NSGraphicsContext.current?.saveGraphicsState()
        shadow.set()
        NSColor.white.set()
        doc.fill()
        NSGraphicsContext.current?.restoreGraphicsState()

        // 折角灰色三角 + 折线
        let foldPath = NSBezierPath()
        foldPath.move(to: NSPoint(x: docRight - fold, y: docTop))
        foldPath.line(to: NSPoint(x: docRight, y: docTop - fold))
        foldPath.line(to: NSPoint(x: docRight - fold, y: docTop - fold))
        foldPath.close()
        NSColor(white: 0.88, alpha: 1).set()
        foldPath.fill()
        let crease = NSBezierPath()
        crease.move(to: NSPoint(x: docRight - fold, y: docTop))
        crease.line(to: NSPoint(x: docRight, y: docTop - fold))
        crease.lineWidth = s * 0.008
        NSColor(white: 0.62, alpha: 1).set()
        crease.stroke()

        // 绿色对勾徽标
        let badgeCenter = NSPoint(x: docRight - s * 0.02, y: docBottom + s * 0.04)
        let badgeRadius = s * 0.125
        let badge = NSBezierPath(
            ovalIn: NSRect(
                x: badgeCenter.x - badgeRadius,
                y: badgeCenter.y - badgeRadius,
                width: badgeRadius * 2,
                height: badgeRadius * 2
            )
        )
        NSGraphicsContext.current?.saveGraphicsState()
        shadow.set()
        badgeGreen.set()
        badge.fill()
        NSGraphicsContext.current?.restoreGraphicsState()

        if let check = tintedSymbol("checkmark", pointSize: badgeRadius * 1.1) {
            let sz = check.size
            let target = NSRect(
                x: badgeCenter.x - sz.width / 2,
                y: badgeCenter.y - sz.height / 2,
                width: sz.width,
                height: sz.height
            )
            check.draw(in: target)
        }
        NSGraphicsContext.current?.restoreGraphicsState()
        return true
    }

    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("failed to render \(path)\n".utf8))
        exit(1)
    }
    try? png.write(to: URL(fileURLWithPath: path))
}

for base in [16, 32, 128, 256, 512] {
    makeIcon(pixels: base, path: "\(outDir)/icon_\(base)x\(base).png")
    makeIcon(pixels: base * 2, path: "\(outDir)/icon_\(base)x\(base)@2x.png")
}
print("iconset written to \(outDir)")
