import Foundation

enum SheetSetup {
    static let weeklyTitle = "Weekly"
    static let overhoursHeader = "overhours"
    static let targetCellRef = "Weekly!$B$1"

    static let signedDurationFormat = "+[h]:mm;[h]:mm;0:00"
    static let durationFormat = "[h]:mm"
    static let dateFormat = "yyyy-mm-dd"

    static let greenFill: [String: Any] = ["red": 0.851, "green": 0.918, "blue": 0.827] // #D9EAD3
    static let redFill: [String: Any] = ["red": 0.957, "green": 0.800, "blue": 0.800]   // #F4CCCC

    // Header-anchored array columns: the formula lives in row 1 (the header), which row inserts
    // never push, so the spill always stays aligned with the data rows below it. `={"h"; ARRAY}`
    // renders the header text in row 1 and spills the computed values from row 2 down.
    static let overhoursArray = #"ARRAYFORMULA(IF(B2:B="","",TIMEVALUE(B2:B)-Weekly!$B$1))"#
    static let weekKeyArray = #"ARRAYFORMULA(IF(A2:A="","",DATEVALUE(A2:A)-WEEKDAY(DATEVALUE(A2:A),3)))"#
    static let workedNumericArray = #"ARRAYFORMULA(IF(B2:B="","",TIMEVALUE(B2:B)))"#

    static var overhoursColumnFormula: String { #"={"overhours";"# + overhoursArray + "}" }
    static var weekColumnFormula: String { #"={"week";"# + weekKeyArray + "}" }
    static var workedColumnFormula: String { #"={"worked";"# + workedNumericArray + "}" }

    static func weekListFormula(logTitle: String) -> String {
        let t = quoted(logTitle)
        return "=SORT(UNIQUE(FILTER(\(t)!G2:G,\(t)!G2:G<>\"\")))"
    }
    static func weeklyWorkedFormula(logTitle: String) -> String {
        let t = quoted(logTitle)
        return "=ARRAYFORMULA(IF(A4:A=\"\",\"\",SUMIF(\(t)!G:G,A4:A,\(t)!H:H)))"
    }
    static func weeklyOverhoursFormula(logTitle: String) -> String {
        let t = quoted(logTitle)
        return "=ARRAYFORMULA(IF(A4:A=\"\",\"\",SUMIF(\(t)!G:G,A4:A,\(t)!F:F)))"
    }
    static let weeklyRunningBalanceFormula = #"=ARRAYFORMULA(IF(A4:A="","",SUMIF(A4:A,"<="&A4:A,C4:C)))"#

    private static func quoted(_ title: String) -> String {
        "'" + title.replacingOccurrences(of: "'", with: "''") + "'"
    }

    // MARK: - batchUpdate payload

    static func batchUpdateRequests(logSheetId: Int, logTitle: String,
                                    weeklySheetId: Int, createWeekly: Bool) -> [[String: Any]] {
        var reqs: [[String: Any]] = []

        if createWeekly {
            reqs.append(["addSheet": ["properties": ["sheetId": weeklySheetId, "title": weeklyTitle]]])
        }

        // Clear any stray content in the overhours/helper columns below the anchor row so the
        // spilling ARRAYFORMULAs have room to expand (a single occupied cell collapses them to #REF!).
        reqs.append(clearRange(sheetId: logSheetId, startRow: 1, startCol: 5, endCol: 8))
        // Log sheet F1:H1 — each cell is a header-anchored array column (header + spilled values).
        reqs.append(updateCells(sheetId: logSheetId, row: 0, col: 5, rows: [
            [formula(overhoursColumnFormula), formula(weekColumnFormula), formula(workedColumnFormula)],
        ]))
        // Overhours column display: signed duration.
        reqs.append(numberFormat(sheetId: logSheetId, startRow: 1, startCol: 5, endCol: 6,
                                 type: "NUMBER", pattern: signedDurationFormat))
        // Hide the helper columns G (week key) and H (worked numeric).
        reqs.append(hideColumns(sheetId: logSheetId, startCol: 6, endCol: 8))
        // Sign-based colouring of the overhours column.
        reqs.append(contentsOf: signColorRules(sheetId: logSheetId, startRow: 1, startCol: 5, endCol: 6))

        // Weekly tab.
        reqs.append(updateCells(sheetId: weeklySheetId, row: 0, col: 0, rows: [
            [str("standard workday"), formula("=TIME(6,48,0)")],
        ]))
        reqs.append(numberFormat(sheetId: weeklySheetId, startRow: 0, startCol: 1, endCol: 2,
                                 type: "NUMBER", pattern: durationFormat))
        reqs.append(updateCells(sheetId: weeklySheetId, row: 2, col: 0, rows: [
            [str("week"), str("hours worked"), str("overhours"), str("running balance")],
        ]))
        reqs.append(updateCells(sheetId: weeklySheetId, row: 3, col: 0, rows: [
            [formula(weekListFormula(logTitle: logTitle)),
             formula(weeklyWorkedFormula(logTitle: logTitle)),
             formula(weeklyOverhoursFormula(logTitle: logTitle)),
             formula(weeklyRunningBalanceFormula)],
        ]))
        reqs.append(numberFormat(sheetId: weeklySheetId, startRow: 3, startCol: 0, endCol: 1,
                                 type: "DATE", pattern: dateFormat))
        reqs.append(numberFormat(sheetId: weeklySheetId, startRow: 3, startCol: 1, endCol: 2,
                                 type: "NUMBER", pattern: durationFormat))
        reqs.append(numberFormat(sheetId: weeklySheetId, startRow: 3, startCol: 2, endCol: 4,
                                 type: "NUMBER", pattern: signedDurationFormat))
        reqs.append(contentsOf: signColorRules(sheetId: weeklySheetId, startRow: 3, startCol: 2, endCol: 4))

        return reqs
    }

    // MARK: - request builders

    private static func str(_ s: String) -> [String: Any] { ["userEnteredValue": ["stringValue": s]] }
    private static func formula(_ f: String) -> [String: Any] { ["userEnteredValue": ["formulaValue": f]] }

    private static func updateCells(sheetId: Int, row: Int, col: Int,
                                    rows: [[[String: Any]]]) -> [String: Any] {
        ["updateCells": [
            "start": ["sheetId": sheetId, "rowIndex": row, "columnIndex": col],
            "rows": rows.map { ["values": $0] },
            "fields": "userEnteredValue",
        ]]
    }

    private static func gridRange(_ sheetId: Int, startRow: Int, startCol: Int, endCol: Int) -> [String: Any] {
        ["sheetId": sheetId, "startRowIndex": startRow, "startColumnIndex": startCol, "endColumnIndex": endCol]
    }

    private static func numberFormat(sheetId: Int, startRow: Int, startCol: Int, endCol: Int,
                                     type: String, pattern: String) -> [String: Any] {
        ["repeatCell": [
            "range": gridRange(sheetId, startRow: startRow, startCol: startCol, endCol: endCol),
            "cell": ["userEnteredFormat": ["numberFormat": ["type": type, "pattern": pattern]]],
            "fields": "userEnteredFormat.numberFormat",
        ]]
    }

    private static func clearRange(sheetId: Int, startRow: Int, startCol: Int, endCol: Int) -> [String: Any] {
        ["repeatCell": [
            "range": gridRange(sheetId, startRow: startRow, startCol: startCol, endCol: endCol),
            "cell": [String: Any](),
            "fields": "userEnteredValue",
        ]]
    }

    private static func hideColumns(sheetId: Int, startCol: Int, endCol: Int) -> [String: Any] {
        ["updateDimensionProperties": [
            "range": ["sheetId": sheetId, "dimension": "COLUMNS", "startIndex": startCol, "endIndex": endCol],
            "properties": ["hiddenByUser": true],
            "fields": "hiddenByUser",
        ]]
    }

    private static func signColorRules(sheetId: Int, startRow: Int, startCol: Int, endCol: Int) -> [[String: Any]] {
        let range = gridRange(sheetId, startRow: startRow, startCol: startCol, endCol: endCol)
        func rule(_ type: String, _ fill: [String: Any]) -> [String: Any] {
            ["addConditionalFormatRule": [
                "rule": [
                    "ranges": [range],
                    "booleanRule": [
                        "condition": ["type": type, "values": [["userEnteredValue": "0"]]],
                        "format": ["backgroundColor": fill],
                    ],
                ],
                "index": 0,
            ]]
        }
        return [rule("NUMBER_GREATER", greenFill), rule("NUMBER_LESS", redFill)]
    }
}
