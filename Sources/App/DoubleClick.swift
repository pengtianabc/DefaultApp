import AppKit
import SwiftUI

/// AppKit 级双击识别。SwiftUI 手势（onTapGesture / simultaneousGesture）
/// 在 List 行与 ScrollView 内会被系统事件处理吞掉，双击经常不触发；
/// NSClickGestureRecognizer 工作在事件层：单击照常透传（选择/悬停不受影响），
/// 第二次点击落下时触发 action。
struct DoubleClickRecognizer: NSViewRepresentable {
    var action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let recognizer = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.doubleClicked)
        )
        recognizer.numberOfClicksRequired = 2
        view.addGestureRecognizer(recognizer)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.action = action
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func doubleClicked() { action() }
    }
}
