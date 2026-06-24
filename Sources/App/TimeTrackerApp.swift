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
                    NSWorkspace.shared.notificationCenter.addObserver(
                        forName: NSWorkspace.didWakeNotification,
                        object: nil, queue: .main
                    ) { _ in app.onWake() }
                }
        } label: {
            MenuBarLabel(app: app)
        }
        .menuBarExtraStyle(.window)
    }
}
