import SwiftUI

struct MenuBarLabel: View {
    @ObservedObject var app: AppState

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: app.stateGlyph)
            if let text = app.menuBarText {
                Text(text)
            }
        }
    }
}
