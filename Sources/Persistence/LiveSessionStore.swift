import Foundation

struct LiveSessionStore {
    private var url: URL { AppPaths.directory.appendingPathComponent("live-session.json") }

    func save(_ session: WorkSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func load() -> WorkSession? {
        guard let data = try? Data(contentsOf: url),
              let session = try? JSONDecoder().decode(WorkSession.self, from: data) else { return nil }
        return session
    }

    func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
