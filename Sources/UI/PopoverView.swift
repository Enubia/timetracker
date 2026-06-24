import SwiftUI
import AppKit

struct PopoverView: View {
    @ObservedObject var app: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var editingStart = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if app.hasStaleSession {
                StaleSessionView(app: app)
                Divider()
            }

            statusLine
            if app.session.start != nil {
                figures
            }
            Divider()
            buttons
            Divider()
            footer
        }
        .padding()
        .frame(width: 300)
    }

    private var statusLine: some View {
        Group {
            switch app.session.state {
            case .idle, .ended:
                Text("Not working").font(.headline)
            case .working:
                Text("Working — \(app.todayNetString)").font(.headline)
            case .onBreak:
                Text("On break — \(app.todayBreakString)").font(.headline)
            }
        }
    }

    private var figures: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let start = app.todayStartString {
                HStack {
                    Text("Start: \(start)")
                    Spacer()
                    Button(editingStart ? "Done" : "Edit") { editingStart.toggle() }
                        .buttonStyle(.link)
                }
                if editingStart {
                    DatePicker("", selection: Binding(
                        get: { app.session.start ?? Date() },
                        set: { app.adjustStart(to: $0) }
                    ), displayedComponents: [.hourAndMinute])
                    .labelsHidden()
                }
            }
            Text("Break: \(app.todayBreakString)")
            Text("Worked: \(app.todayNetString)")
        }
        .font(.callout).foregroundStyle(.secondary)
        .onChange(of: app.session.start) { _, newValue in
            if newValue == nil { editingStart = false }
        }
    }

    @ViewBuilder private var buttons: some View {
        switch app.session.state {
        case .idle, .ended:
            Button("Start") { app.startDay() }.keyboardShortcut(.defaultAction)
        case .working:
            HStack {
                Button("Pause") { app.pause() }
                Button("End") { app.endDay() }
            }
        case .onBreak:
            HStack {
                Button("Resume") { app.resume() }
                Button("End") { app.endDay() }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            syncFooter
            HStack {
                Button("Open Sheet") { openSheet() }
                    .disabled(Preferences.sheetId.isEmpty)
                Spacer()
                Button("Settings") {
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
    }

    private var syncFooter: some View {
        HStack(spacing: 6) {
            switch app.syncStatus {
            case .idle: Text("—").foregroundStyle(.secondary)
            case .syncing: Text("Syncing…").foregroundStyle(.secondary)
            case .synced: Text("Synced ✓").foregroundStyle(.green)
            case .pending(let n):
                Text("⚠️ \(n) pending").foregroundStyle(.orange)
                Button("Retry") { app.retrySync() }
            case .failed(let msg):
                Text("⚠️ \(msg)").foregroundStyle(.red)
                Button("Retry") { app.retrySync() }
            }
        }
        .font(.callout)
    }

    private func openSheet() {
        guard !Preferences.sheetId.isEmpty,
              let url = URL(string: "https://docs.google.com/spreadsheets/d/\(Preferences.sheetId)/edit") else { return }
        NSWorkspace.shared.open(url)
    }
}
