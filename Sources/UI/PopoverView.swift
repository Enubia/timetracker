import SwiftUI
import AppKit

struct PopoverView: View {
    @ObservedObject var app: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var editMode: EditMode?
    @State private var draftBreakHours = 0
    @State private var draftBreakMinutes = 0

    private enum EditMode {
        case start
        case breakTime
    }

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
            startFigure
            breakFigure
            Text("Worked: \(app.todayNetString)")
        }
        .font(.callout).foregroundStyle(.secondary)
        .onChange(of: app.session.start) { _, newValue in
            if newValue == nil { editMode = nil }
        }
        .onChange(of: app.session.state) { _, newValue in
            if newValue == .idle || newValue == .ended { editMode = nil }
        }
    }

    @ViewBuilder private var startFigure: some View {
        if let start = app.todayStartString {
            HStack {
                Text("Start: \(start)")
                Spacer()
                Button(editMode == .start ? "Done" : "Edit") { toggleStartEdit() }
                    .buttonStyle(.link)
            }
            if editMode == .start {
                DatePicker("", selection: Binding(
                    get: { app.session.start ?? Date() },
                    set: { app.adjustStart(to: $0) }
                ), displayedComponents: [.hourAndMinute])
                .labelsHidden()
            }
        }
    }

    private var breakFigure: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Break: \(app.todayBreakString)")
                Spacer()
                if editMode != .breakTime {
                    Button("Edit") { beginBreakEdit() }
                        .buttonStyle(.link)
                }
            }
            if editMode == .breakTime {
                breakEditor
            }
        }
    }

    private var breakEditor: some View {
        HStack(spacing: 6) {
            TextField("0", value: $draftBreakHours, format: .number)
                .frame(width: 44)
                .multilineTextAlignment(.trailing)
            Text("h")
            TextField("0", value: $draftBreakMinutes, format: .number)
                .frame(width: 44)
                .multilineTextAlignment(.trailing)
            Text("min")
            Spacer()
            Button("Save") { saveBreakEdit() }
            Button("Cancel") { editMode = nil }
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

    private func toggleStartEdit() {
        editMode = editMode == .start ? nil : .start
    }

    private func beginBreakEdit() {
        let minutes = max(0, app.session.breakSeconds(asOf: app.nowTick) / 60)
        draftBreakHours = minutes / 60
        draftBreakMinutes = minutes % 60
        editMode = .breakTime
    }

    private func saveBreakEdit() {
        app.adjustBreak(hours: draftBreakHours, minutes: draftBreakMinutes)
        editMode = nil
    }

    private func openSheet() {
        guard !Preferences.sheetId.isEmpty,
              let url = URL(string: "https://docs.google.com/spreadsheets/d/\(Preferences.sheetId)/edit") else { return }
        NSWorkspace.shared.open(url)
    }
}
