import SwiftUI

@main
struct DefaultApp: App {
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(state)
                .environment(I18n.shared)
                .frame(minWidth: 800, minHeight: 540)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1040, height: 640)
    }
}
