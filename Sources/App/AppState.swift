import Foundation
import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var session: WorkSession = .idle()
    @Published private(set) var syncStatus: SyncStatus = .idle
    @Published var nowTick: Date = Date()

    let timeZone = TimeZone(identifier: "Europe/Vienna")!

    private let liveStore = LiveSessionStore()
    private let history = HistoryLog()
    private let pending = PendingQueue()
    private let sync: SheetSync
    private var timer: Timer?
    private var nudgedTenHours = false

    init() {
        self.sync = SheetSync(queue: PendingQueue())
    }

    var menuBarText: String? {
        switch session.state {
        case .idle, .ended: return nil
        case .working, .onBreak:
            return Duration.hmString(seconds: session.netSeconds(asOf: nowTick))
        }
    }

    var stateGlyph: String {
        switch session.state {
        case .idle, .ended: return "clock"
        case .working: return "play.circle.fill"
        case .onBreak: return "pause.circle.fill"
        }
    }

    var todayStartString: String? {
        guard let start = session.start else { return nil }
        return clock(start)
    }
    var todayBreakString: String { Duration.hmString(seconds: session.breakSeconds(asOf: nowTick)) }
    var todayNetString: String { Duration.hmString(seconds: session.netSeconds(asOf: nowTick)) }

    func startDay() {
        try? session.start(at: Date())
        nudgedTenHours = false
        persist()
    }
    func pause() { try? session.beginBreak(at: Date()); persist() }
    func resume() { try? session.endBreak(at: Date()); persist() }

    func endDay() {
        try? session.end(at: Date())
        finalizeAndReset()
    }

    func adjustStart(to newStart: Date) {
        guard session.state == .working || session.state == .onBreak else { return }
        session.start = newStart
        persist()
    }

    var hasStaleSession: Bool {
        guard let start = session.start, session.state == .working || session.state == .onBreak else { return false }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        return !cal.isDate(start, inSameDayAs: nowTick)
    }

    func endStaleSession(at end: Date) {
        guard session.state == .working || session.state == .onBreak else { return }
        try? session.end(at: end)
        finalizeAndReset()
    }

    func configureGoogle(json: Data, sheetId: String) async -> Result<String, Error> {
        guard KeychainStore.save(json: json) else {
            return .failure(NSError(domain: "TimeTracker", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not save key to Keychain"]))
        }
        Preferences.sheetId = sheetId
        do {
            try await sync.configure(serviceAccountJSON: json, sheetId: sheetId)
            let title = try await sync.testConnection()
            return .success(title)
        } catch {
            return .failure(error)
        }
    }

    func retrySync() { Task { await flush() } }

    func onLaunch() {
        if let restored = liveStore.load() { session = restored }
        if let json = KeychainStore.load(), !Preferences.sheetId.isEmpty {
            let sheetId = Preferences.sheetId
            Task { try? await self.sync.configure(serviceAccountJSON: json, sheetId: sheetId); await self.flush() }
        }
        Notifier.requestAuthorization()
        startTimer()
        Task { await flush() }
        if !UserDefaults.standard.bool(forKey: "didSetInitialLaunchAtLogin") {
            LaunchAtLogin.set(true)
            UserDefaults.standard.set(true, forKey: "didSetInitialLaunchAtLogin")
        }
    }

    func onWake() {
        nowTick = Date()
        Task { await flush() }
    }

    private func finalizeAndReset() {
        let summary = AutoBreak.summarize(session, timeZone: timeZone)
        history.append(summary)
        pending.enqueue(summary)
        session = .idle()
        liveStore.clear()
        Task { await flush() }
    }

    private func flush() async {
        syncStatus = .syncing
        let status = await sync.flush()
        syncStatus = status
        if case .synced(let date) = status { Preferences.lastSyncEpoch = date.timeIntervalSince1970 }
    }

    private func persist() { liveStore.save(session) }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        nowTick = Date()
        if (session.state == .working || session.state == .onBreak),
           session.grossSeconds(asOf: nowTick) >= 10 * 3600, !nudgedTenHours {
            nudgedTenHours = true
            Notifier.nudgeTenHours()
        }
    }

    private func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeZone = timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
