import SwiftUI

@main
struct BibliaApp: App {
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(state)
                .task { state.bootstrap() }
        }
        Settings { SettingsView() }
    }
}
