import AppKit

/// 隐藏功能：`DefaultApp --snapshot <path>` 截取自身窗口后退出。
/// 用于生成 README 截图：不依赖屏幕录制权限，也不受窗口所在桌面影响。
enum Snapshotter {
    static let path: String? = {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--snapshot"), index + 1 < args.count else { return nil }
        return args[index + 1]
    }()

    static var isActive: Bool { path != nil }

    /// 调整窗口到固定尺寸并前置，保证截图构图一致。
    @MainActor
    static func stage() {
        guard let window = NSApp.windows.first else { return }
        window.setFrame(NSRect(x: 140, y: 60, width: 1120, height: 720), display: true)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// 渲染等待由调用方负责。窗口可能位于其他桌面（WindowServer 不给回读），
    /// 因此强制 AppKit 同步绘制后走 CALayer 软件渲染，绕开合成分配。
    @MainActor
    static func captureAndExit() {
        guard let path else { exit(1) }
        guard let window = NSApp.windows.first, let view = window.contentView else { exit(1) }
        view.wantsLayer = true

        // 同步完成布局与绘制（不依赖窗口是否已上屏）
        window.layoutIfNeeded()
        view.layoutSubtreeIfNeeded()
        view.display()

        let size = view.bounds.size
        let scale = window.backingScaleFactor > 1 ? window.backingScaleFactor : 2
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let layer = view.layer else { exit(1) }

        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current = context
        // NSView 的图层坐标 y 轴向上，位图上下文需要翻转绘制
        context?.cgContext.scaleBy(x: scale, y: -scale)
        context?.cgContext.translateBy(x: 0, y: -size.height)
        // 先铺一层窗口底色，避免透明背景
        NSColor.windowBackgroundColor.setFill()
        NSRect(origin: .zero, size: size).fill()
        layer.render(in: context!.cgContext)
        NSGraphicsContext.restoreGraphicsState()

        guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
        try? png.write(to: URL(fileURLWithPath: path))
        exit(0)
    }
}
