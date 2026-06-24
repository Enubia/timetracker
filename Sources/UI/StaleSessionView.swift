import SwiftUI

struct StaleSessionView: View {
    @ObservedObject var app: AppState
    @State private var endTime: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Unfinished session").font(.headline)
            if let start = app.todayStartString {
                Text("Started \(start) on a previous day and is still running.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            DatePicker("End time", selection: $endTime, displayedComponents: [.date, .hourAndMinute])
            HStack {
                Button("End now") { app.endStaleSession(at: Date()) }
                Button("End at selected time") { app.endStaleSession(at: endTime) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 320)
    }
}
