import SwiftUI

@main
struct DefaultApp: App {
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(state)
                .environment(I18n.shared)
                .frame(minWidth: 940, minHeight: 580)
        }
        .defaultSize(width: 1040, height: 640)
    }
}
