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
    private var headerEnsured = false

    init(queue: PendingQueue) {
        self.queue = queue
    }

    func configure(serviceAccountJSON: Data, sheetId: String) throws {
        let account = try ServiceAccount.from(serviceAccountJSON)
        let auth = GoogleAuth(account: account)
        client = SheetsClient(auth: auth, spreadsheetId: sheetId)
        headerEnsured = false
    }

    func testConnection() async throws -> String {
        guard let client else { throw SyncError.notConfigured }
        return try await client.spreadsheetTitle()
    }

    func flush(now: Date = Date()) async -> SyncStatus {
        guard let client else { return .failed("not configured") }
        var items = queue.all()
        guard !items.isEmpty else { return .synced(now) }

        do {
            if !headerEnsured {
                try await client.ensureHeader()
                headerEnsured = true
            }
            while !items.isEmpty {
                try await client.append(row: items[0].row())
                items.removeFirst()
                queue.replace(with: items)
            }
            return .synced(now)
        } catch {
            return .pending(items.count)
        }
    }

    enum SyncError: Error { case notConfigured }
}
