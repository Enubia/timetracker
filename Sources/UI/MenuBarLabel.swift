import SwiftUI

struct MenuBarLabel: View {
    @ObservedObject var app: AppState

    var body: some View {
        HStack {
            Image(systemName: app.stateGlyph)
            if let text = app.menuBarText {
                Text(text).monospacedDigit()
            }
        }
        .padding()
        .font(.system(size: 20))
    }
}
