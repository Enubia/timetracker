import XCTest
@testable import TimeTracker

final class SheetSetupTests: XCTestCase {
    func testOverhoursColumnIsHeaderAnchoredArraySubtractingTarget() {
        // Header text + spilling array in one row-1 cell, so row inserts never strand the anchor.
        XCTAssertEqual(
            SheetSetup.overhoursColumnFormula,
            #"={"overhours";ARRAYFORMULA(IF(B2:B="","",TIMEVALUE(B2:B)-Weekly!$B$1))}"#
        )
    }

    // Helpers ---------------------------------------------------------------
    private func requests(logSheetId: Int = 0, logTitle: String = "Sheet1",
                          weeklySheetId: Int = 1234, createWeekly: Bool = true) throws -> [[String: Any]] {
        let reqs = SheetSetup.batchUpdateRequests(logSheetId: logSheetId, logTitle: logTitle,
                                                  weeklySheetId: weeklySheetId, createWeekly: createWeekly)
        // Round-trips through JSON to prove the payload is serializable (no NaN/invalid values).
        let data = try JSONSerialization.data(withJSONObject: ["requests": reqs])
        let back = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        return back["requests"] as! [[String: Any]]
    }
    private func requestsWith(_ key: String, in reqs: [[String: Any]]) -> [[String: Any]] {
        reqs.compactMap { $0[key] as? [String: Any] }
    }

    func testIncludesAddSheetForWeeklyWhenItDoesNotExist() throws {
        let adds = requestsWith("addSheet", in: try requests(createWeekly: true))
        XCTAssertEqual(adds.count, 1)
        let props = adds[0]["properties"] as! [String: Any]
        XCTAssertEqual(props["title"] as? String, "Weekly")
        XCTAssertEqual(props["sheetId"] as? Int, 1234)
    }

    func testOmitsAddSheetWhenWeeklyAlreadyExists() throws {
        let adds = requestsWith("addSheet", in: try requests(createWeekly: false))
        XCTAssertTrue(adds.isEmpty)
    }

    func testWritesOverhoursColumnFormulaInHeaderRowOnLogSheetColumnF() throws {
        let updates = requestsWith("updateCells", in: try requests(logSheetId: 0))
        // Written into the header row (rowIndex 0) at column F (index 5) on the log sheet.
        let logBlock = updates.first { ($0["start"] as? [String: Any])?["columnIndex"] as? Int == 5 }
        let start = logBlock?["start"] as! [String: Any]
        XCTAssertEqual(start["sheetId"] as? Int, 0)
        XCTAssertEqual(start["rowIndex"] as? Int, 0)
        let rows = logBlock?["rows"] as! [[String: Any]]
        let formula = ((rows[0]["values"] as! [[String: Any]])[0]["userEnteredValue"] as! [String: Any])["formulaValue"] as? String
        XCTAssertEqual(formula, SheetSetup.overhoursColumnFormula)
    }

    func testColumnFGetsSignedDurationNumberFormat() throws {
        let formats = requestsWith("repeatCell", in: try requests(logSheetId: 0))
        let fFormat = formats.first {
            let r = $0["range"] as! [String: Any]
            return r["sheetId"] as? Int == 0 && r["startColumnIndex"] as? Int == 5
                && r["endColumnIndex"] as? Int == 6
                && ($0["cell"] as? [String: Any])?["userEnteredFormat"] != nil
        }
        let nf = ((fFormat?["cell"] as! [String: Any])["userEnteredFormat"] as! [String: Any])["numberFormat"] as! [String: Any]
        XCTAssertEqual(nf["pattern"] as? String, "+[h]:mm;[h]:mm;0:00")
    }

    func testConditionalFormattingColorsBySignGreenOverRedUnder() throws {
        let rules = requestsWith("addConditionalFormatRule", in: try requests(logSheetId: 0))
        // Two rules on the log sheet's F column.
        let fRules = rules.filter {
            let range = (($0["rule"] as! [String: Any])["ranges"] as! [[String: Any]])[0]
            return range["sheetId"] as? Int == 0 && range["startColumnIndex"] as? Int == 5
        }
        XCTAssertEqual(fRules.count, 2)
        func boolRule(_ r: [String: Any]) -> (type: String, fill: [String: Any]) {
            let br = (r["rule"] as! [String: Any])["booleanRule"] as! [String: Any]
            let type = (br["condition"] as! [String: Any])["type"] as! String
            let fill = (br["format"] as! [String: Any])["backgroundColor"] as! [String: Any]
            return (type, fill)
        }
        let green = fRules.map(boolRule).first { $0.type == "NUMBER_GREATER" }
        let red = fRules.map(boolRule).first { $0.type == "NUMBER_LESS" }
        XCTAssertEqual(green?.fill["green"] as? Double, 0.918)
        XCTAssertEqual(red?.fill["red"] as? Double, 0.957)
    }

    func testWeeklyTargetCellHoldsSixFortyEight() throws {
        let updates = requestsWith("updateCells", in: try requests(weeklySheetId: 1234))
        let targetBlock = updates.first {
            ($0["start"] as? [String: Any])?["sheetId"] as? Int == 1234
                && ($0["start"] as? [String: Any])?["rowIndex"] as? Int == 0
        }
        let cells = (targetBlock?["rows"] as! [[String: Any]])[0]["values"] as! [[String: Any]]
        let target = (cells[1]["userEnteredValue"] as! [String: Any])["formulaValue"] as? String
        XCTAssertEqual(target, "=TIME(6,48,0)")
    }

    func testClearsHelperColumnsBelowAnchorBeforeWritingFormulas() throws {
        let reqs = try requests(logSheetId: 0)
        // A clear (repeatCell, empty userEnteredValue) spanning F:H (cols 5–8) from row 2 down.
        let clearIdx = reqs.firstIndex { req in
            guard let rc = req["repeatCell"] as? [String: Any],
                  rc["fields"] as? String == "userEnteredValue",
                  (rc["cell"] as? [String: Any])?.isEmpty == true,
                  let r = rc["range"] as? [String: Any] else { return false }
            return r["sheetId"] as? Int == 0 && r["startRowIndex"] as? Int == 1
                && r["startColumnIndex"] as? Int == 5 && r["endColumnIndex"] as? Int == 8
                && r["endRowIndex"] == nil
        }
        XCTAssertNotNil(clearIdx, "expected an unbounded clear of F:H from row 2")
        // It must run before the formulas are written, or it would wipe them.
        let writeIdx = reqs.firstIndex {
            ($0["updateCells"] as? [String: Any]).flatMap { ($0["start"] as? [String: Any]) }?["columnIndex"] as? Int == 5
        }
        XCTAssertNotNil(writeIdx)
        XCTAssertLessThan(clearIdx!, writeIdx!)
    }

    func testWeeklyRollupGroupsByWeekKeyFromLogSheetByTitle() throws {
        let updates = requestsWith("updateCells", in: try requests(weeklySheetId: 1234, createWeekly: true))
        let rollup = updates.first {
            ($0["start"] as? [String: Any])?["sheetId"] as? Int == 1234
                && ($0["start"] as? [String: Any])?["rowIndex"] as? Int == 3
        }
        let cells = (rollup?["rows"] as! [[String: Any]])[0]["values"] as! [[String: Any]]
        let weekCol = (cells[0]["userEnteredValue"] as! [String: Any])["formulaValue"] as? String
        let balanceCol = (cells[3]["userEnteredValue"] as! [String: Any])["formulaValue"] as? String
        XCTAssertEqual(weekCol, "=SORT(UNIQUE(FILTER('Sheet1'!G2:G,'Sheet1'!G2:G<>\"\")))")
        XCTAssertEqual(balanceCol, #"=ARRAYFORMULA(IF(A4:A="","",SUMIF(A4:A,"<="&A4:A,C4:C)))"#)
    }
}
