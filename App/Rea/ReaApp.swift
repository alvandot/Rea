import SwiftUI
import ReaCore

@main
struct ReaApp: App {
    @StateObject private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .task { await app.boot() }
                .onChange(of: app.settings) { _, settings in
                    settings.save()
                }
        }
    }
}
