import SwiftUI

struct SettingsView: View {
    @ObservedObject var app: AppState
    @State private var jsonText: String = ""
    @State private var sheetId: String = Preferences.sheetId
    @State private var launchAtLogin: Bool = LaunchAtLogin.isEnabled
    @State private var testResult: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings").font(.title2).bold()

            Text("Service account JSON").font(.headline)
            TextEditor(text: $jsonText)
                .font(.system(.caption, design: .monospaced))
                .frame(height: 120)
                .border(.secondary)

            Text("Google Sheet ID").font(.headline)
            TextField("spreadsheet id from the URL", text: $sheetId)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Save & Test connection") { saveAndTest() }
                Text(testResult).font(.callout).foregroundStyle(.secondary)
            }

            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in LaunchAtLogin.set(newValue) }

            Spacer()
        }
        .padding()
        .frame(width: 420, height: 360)
    }

    private func saveAndTest() {
        guard let data = jsonText.data(using: .utf8), !sheetId.isEmpty else {
            testResult = "Paste JSON and a Sheet ID first."
            return
        }
        testResult = "Testing…"
        Task {
            let result = await app.configureGoogle(json: data, sheetId: sheetId)
            switch result {
            case .success(let title): testResult = "Connected to: \(title)"
            case .failure(let error): testResult = "Failed: \(error.localizedDescription)"
            }
        }
    }
}
