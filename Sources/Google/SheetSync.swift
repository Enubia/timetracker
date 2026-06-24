import Foundation

enum SyncStatus: Equatable {
    case idle
    case syncing
    case synced(Date)
    case pending(Int)
    case failed(String)
}

actor SheetSync {
    private let queue: PendingQueue
    private var client: SheetsClient?
    private var setupEnsured = false
    private var isFlushing = false

    init(queue: PendingQueue) {
        self.queue = queue
    }

    func enqueue(_ summary: SessionSummary) {
        queue.enqueue(summary)
    }

    func configure(serviceAccountJSON: Data, sheetId: String) throws {
        let account = try ServiceAccount.from(serviceAccountJSON)
        let auth = GoogleAuth(account: account)
        client = SheetsClient(auth: auth, spreadsheetId: sheetId)
        setupEnsured = false
    }

    func testConnection() async throws -> String {
        guard let client else { throw SyncError.notConfigured }
        return try await client.spreadsheetTitle()
    }

    func flush(now: Date = Date()) async -> SyncStatus {
        guard let client else { return .failed("not configured") }
        guard !isFlushing else { return .syncing }
        isFlushing = true
        defer { isFlushing = false }

        guard !queue.all().isEmpty else { return .synced(now) }
        do {
            if !setupEnsured {
                try await client.ensureHeader()
                try await client.ensureOverhoursSetup()
                setupEnsured = true
            }
            while let first = queue.all().first {
                try await client.append(row: first.row())
                var remaining = queue.all()
                if !remaining.isEmpty { remaining.removeFirst() }
                queue.replace(with: remaining)
            }
            return .synced(now)
        } catch {
            return Self.status(for: error, pendingCount: queue.all().count)
        }
    }

    private static func status(for error: Error, pendingCount: Int) -> SyncStatus {
        if case let SheetsClient.SheetsError.http(code) = error,
           (400...499).contains(code), code != 408, code != 429 {
            return .failed("Sheets error \(code)")
        }
        return .pending(pendingCount)
    }

    enum SyncError: Error { case notConfigured }
}
