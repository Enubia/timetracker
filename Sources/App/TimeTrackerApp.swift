import SwiftUI

@main
struct TimeTrackerApp: App {
    var body: some Scene {
        MenuBarExtra("TimeTracker", systemImage: "clock") {
            Text("TimeTracker")
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .menuBarExtraStyle(.window)
    }
}
