import SwiftUI

@main
struct FlowApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
        }
        #if os(macOS)
        .defaultSize(width: 1200, height: 800)
        #endif
    }
}
