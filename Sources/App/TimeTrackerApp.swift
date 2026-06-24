import SwiftUI
import AppKit

@main
struct TimeTrackerApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(app: app)
                .onAppear {
                    app.onLaunch()
                }
        } label: {
            MenuBarLabel(app: app)
        }
        .menuBarExtraStyle(.window)

        Window("TimeTracker Settings", id: "settings") {
            SettingsView(app: app)
        }
        .windowResizability(.contentSize)
    }
}
