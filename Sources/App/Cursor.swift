import AppKit
import SwiftUI

extension View {
    /// 悬停时切换为手指光标，标示“此处可双击跳转”。
    /// 移出时恢复箭头（相邻可跳转区域之间会有极短暂的 arrow→hand 切换，无感）。
    func linkCursorOnHover() -> some View {
        onHover { hovering in
            if hovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }
}
