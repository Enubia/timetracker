import Foundation

enum Preferences {
    private static let defaults = UserDefaults.standard

    static var sheetId: String {
        get { defaults.string(forKey: "sheetId") ?? "" }
        set { defaults.set(newValue, forKey: "sheetId") }
    }
    static var lastSyncEpoch: Double {
        get { defaults.double(forKey: "lastSyncEpoch") }
        set { defaults.set(newValue, forKey: "lastSyncEpoch") }
    }
}
