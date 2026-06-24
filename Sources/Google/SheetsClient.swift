import Foundation

struct SheetsClient {
    enum SheetsError: Error { case http(Int), badSpreadsheetId }

    private let auth: GoogleAuth
    private let spreadsheetId: String
    private let base = "https://sheets.googleapis.com/v4/spreadsheets"
    static let header = ["date", "total hours", "start", "break", "end"]

    init(auth: GoogleAuth, spreadsheetId: String) {
        self.auth = auth
        self.spreadsheetId = spreadsheetId
    }

    private func makeURL(path: String = "", query: String? = nil) throws -> URL {
        guard let id = spreadsheetId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw SheetsError.badSpreadsheetId
        }
        var string = "\(base)/\(id)\(path)"
        if let query { string += "?\(query)" }
        guard let url = URL(string: string) else { throw SheetsError.badSpreadsheetId }
        return url
    }

    func spreadsheetTitle() async throws -> String {
        let url = try makeURL(query: "fields=properties.title")
        let data = try await send(URLRequest(url: url))
        struct Resp: Decodable { struct P: Decodable { let title: String }; let properties: P }
        return try JSONDecoder().decode(Resp.self, from: data).properties.title
    }

    func ensureHeader() async throws {
        let getURL = try makeURL(path: "/values/A1:E1")
        let data = try await send(URLRequest(url: getURL))
        struct ValuesResp: Decodable { let values: [[String]]? }
        let existing = try JSONDecoder().decode(ValuesResp.self, from: data).values ?? []
        guard existing.isEmpty || existing.first?.isEmpty == true else { return }

        var put = URLRequest(url: try makeURL(path: "/values/A1:E1", query: "valueInputOption=RAW"))
        put.httpMethod = "PUT"
        put.setValue("application/json", forHTTPHeaderField: "Content-Type")
        put.httpBody = try JSONSerialization.data(withJSONObject: ["values": [Self.header]])
        _ = try await send(put)
    }

    struct SheetMeta { let title: String; let sheetId: Int }

    func sheetMetas() async throws -> [SheetMeta] {
        let url = try makeURL(query: "fields=sheets.properties(sheetId,title)")
        let data = try await send(URLRequest(url: url))
        struct Resp: Decodable {
            struct S: Decodable { struct P: Decodable { let sheetId: Int; let title: String }; let properties: P }
            let sheets: [S]
        }
        return try JSONDecoder().decode(Resp.self, from: data).sheets
            .map { SheetMeta(title: $0.properties.title, sheetId: $0.properties.sheetId) }
    }

    func overhoursInstalled() async throws -> Bool {
        let url = try makeURL(path: "/values/F1")
        let data = try await send(URLRequest(url: url))
        struct ValuesResp: Decodable { let values: [[String]]? }
        let values = try JSONDecoder().decode(ValuesResp.self, from: data).values ?? []
        return values.first?.first == SheetSetup.overhoursHeader
    }

    func ensureOverhoursSetup() async throws {
        let metas = try await sheetMetas()
        let existingWeekly = metas.first { $0.title == SheetSetup.weeklyTitle }
        // Consider it installed only if BOTH the header and the Weekly tab exist — otherwise a
        // deleted Weekly tab leaves the column-F formula as a permanent #REF! with no self-repair.
        if existingWeekly != nil, try await overhoursInstalled() { return }
        guard let log = metas.first else { throw SheetsError.badSpreadsheetId }
        let usedIds = Set(metas.map { $0.sheetId })
        let weeklyId = existingWeekly?.sheetId ?? (1...).first { !usedIds.contains($0) }!
        let requests = SheetSetup.batchUpdateRequests(
            logSheetId: log.sheetId, logTitle: log.title,
            weeklySheetId: weeklyId, createWeekly: existingWeekly == nil)
        try await batchUpdate(requests)
    }

    func batchUpdate(_ requests: [[String: Any]]) async throws {
        var req = URLRequest(url: try makeURL(path: ":batchUpdate"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["requests": requests])
        _ = try await send(req)
    }

    func append(row: [String]) async throws {
        // OVERWRITE (the default) writes into the next empty row without inserting one. INSERT_ROWS
        // would shift the spilling array columns' row references down on every append, stranding them.
        var req = URLRequest(url: try makeURL(path: "/values/A:E:append", query: "valueInputOption=RAW"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["values": [row]])
        _ = try await send(req)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        var req = request
        let token = try await auth.accessToken()
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw SheetsError.http(-1) }
        guard (200...299).contains(http.statusCode) else { throw SheetsError.http(http.statusCode) }
        return data
    }
}
