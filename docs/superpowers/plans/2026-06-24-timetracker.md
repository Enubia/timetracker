# TimeTracker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A macOS menu-bar app that tracks work sessions (start / pause / resume / end) and appends one row per session to a personal Google Sheet via a service account.

**Architecture:** A pure, fully unit-tested domain core (state machine + time math + auto-break rule) with zero I/O, wrapped by thin adapters for persistence (JSON/JSONL on disk), Google Sheets (service-account JWT → access token → values.append), and SwiftUI (`MenuBarExtra` UI). An `AppState` controller object ties the core to the adapters and is the single `ObservableObject` the UI observes. End-of-session never blocks on the network: completed sessions are written to a local append-only history (source of truth) and a pending-write queue that flushes to Google in the background.

**Tech Stack:** Swift 5.9+, SwiftUI (`MenuBarExtra`), AppKit interop where needed, `SMAppService` (launch at login), `UserNotifications`, `Security` framework (Keychain + RS256 JWT signing), `URLSession`. Project defined via **XcodeGen** (`project.yml`). Tests via XCTest. Built with `xcodebuild`.

## Global Constraints

- Platform: macOS 14.0+ deployment target.
- App is an **agent** app: `LSUIElement = true` (no Dock icon, no app-switcher entry).
- Bundle identifier: `com.marcoschuster.timetracker`. App display name: `TimeTracker`.
- Timezone for ALL date/time formatting: `Europe/Vienna` (use an explicit `TimeZone(identifier: "Europe/Vienna")!`, never `.current`).
- Sheet column order is fixed: `date | total hours | start | break | end`.
- Formats written to the sheet (all as plain text via Sheets `valueInputOption=RAW`): date `yyyy-MM-dd`; start/end `HH:mm` (24h); break & total as `H:mm` duration strings (e.g. `8:30`, `0:30`).
- `total = (end − start) − break` (net worked time).
- Auto-break: add exactly 30 minutes to break **only if** manual break total == 0 **and** gross elapsed (`end − start`) ≥ 6h00m. Threshold measured on gross elapsed.
- 10-hour "still running" nudge reflects Austrian maximum daily working time.
- Local code signing only ("Sign to Run Locally" / `CODE_SIGN_IDENTITY=-`); no paid Apple Developer account.
- No code comments unless explicitly required by a step (user global rule).
- Frequent commits: one commit per task minimum.
- Service-account JSON key is a secret: stored only in the macOS Keychain, never on disk in the repo, never logged, and matched by `.gitignore`.

---

## File Structure

```
timetracking/
  project.yml                         # XcodeGen project spec (committed)
  .gitignore
  README.md                           # Google setup checklist + build/run instructions
  Sources/
    App/
      TimeTrackerApp.swift            # @main MenuBarExtra; constructs AppState
      AppState.swift                  # @MainActor ObservableObject controller wiring core <-> adapters
    Core/                             # PURE. No Foundation I/O, no URLSession, no Date.now reads inside logic.
      SessionState.swift              # enum: idle/working/onBreak/ended
      WorkSession.swift               # the session value type + transition functions (pure)
      Duration.swift                  # seconds <-> "H:mm" string formatting
      SessionSummary.swift            # finalized row values (date,total,start,break,end as strings)
      AutoBreak.swift                 # pure auto-break + summary computation
    Persistence/
      LiveSessionStore.swift          # persist/restore in-progress WorkSession (Application Support JSON)
      HistoryLog.swift                # append-only JSONL of completed SessionSummary (source of truth)
      PendingQueue.swift              # queue of rows awaiting Google write (JSON file)
      AppPaths.swift                  # Application Support directory resolution
    Google/
      KeychainStore.swift             # store/read/delete service-account JSON in Keychain
      ServiceAccount.swift            # decode service-account JSON (client_email, private_key, token_uri)
      JWTSigner.swift                 # build + RS256-sign a Google OAuth JWT assertion
      GoogleAuth.swift                # exchange signed JWT for an access token (+ in-memory cache)
      SheetsClient.swift              # append row (RAW), read spreadsheet metadata (test connection)
      SheetSync.swift                 # orchestrates: drain PendingQueue -> SheetsClient, with retry/backoff
    Settings/
      Preferences.swift              # UserDefaults wrapper: sheetId, launchAtLogin mirror
      LaunchAtLogin.swift            # SMAppService.mainApp register/unregister
    UI/
      MenuBarLabel.swift             # menu-bar icon + live net worked time
      PopoverView.swift              # status, today's figures, context-aware buttons, footer
      SettingsView.swift             # paste JSON + sheet id + Test connection + launch toggle
      StaleSessionView.swift         # confirm end time for a stale running session
    Notifications/
      Notifier.swift                 # UserNotifications auth + 10h nudge
    Support/
      Info.plist                     # LSUIElement, bundle name, etc.
      TimeTracker.entitlements       # network client + keychain
  Tests/
    CoreTests/
      DurationTests.swift
      WorkSessionTests.swift
      AutoBreakTests.swift
```

**Dependency direction:** `Core` depends on nothing but Swift stdlib/Foundation value types. `Persistence`, `Google`, `Settings`, `Notifications` depend on `Core`. `App` + `UI` depend on everything. Tests cover only `Core`.

---

## Phase 0 — Project scaffold

### Task 0: XcodeGen project, gitignore, repo, runnable empty menu-bar app

**Files:**
- Create: `project.yml`
- Create: `.gitignore`
- Create: `Sources/App/TimeTrackerApp.swift`
- Create: `Sources/Support/Info.plist`
- Create: `Sources/Support/TimeTracker.entitlements`

**Interfaces:**
- Produces: a buildable `TimeTracker.app` target and a `TimeTrackerTests` test bundle target; `@main struct TimeTrackerApp`.

- [ ] **Step 1: Ensure XcodeGen is installed**

Run: `which xcodegen || brew install xcodegen`
Expected: a path to `xcodegen`, or a successful brew install.

- [ ] **Step 2: Write `.gitignore`**

```gitignore
.DS_Store
*.xcodeproj
*.xcworkspace
xcuserdata/
DerivedData/
build/
.build/
*.serviceaccount.json
*-key.json
secrets/
```

- [ ] **Step 3: Write `project.yml`**

```yaml
name: TimeTracker
options:
  bundleIdPrefix: com.marcoschuster
  deploymentTarget:
    macOS: "14.0"
  createIntermediateGroups: true
settings:
  base:
    CODE_SIGN_IDENTITY: "-"
    CODE_SIGN_STYLE: Manual
    DEVELOPMENT_TEAM: ""
    SWIFT_VERSION: "5.9"
    MARKETING_VERSION: "1.0"
    CURRENT_PROJECT_VERSION: "1"
targets:
  TimeTracker:
    type: application
    platform: macOS
    sources:
      - path: Sources
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.marcoschuster.timetracker
        PRODUCT_NAME: TimeTracker
        INFOPLIST_FILE: Sources/Support/Info.plist
        CODE_SIGN_ENTITLEMENTS: Sources/Support/TimeTracker.entitlements
        ENABLE_HARDENED_RUNTIME: YES
  TimeTrackerTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: Tests
    dependencies:
      - target: TimeTracker
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.marcoschuster.timetracker.tests
```

- [ ] **Step 4: Write `Sources/Support/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>TimeTracker</string>
    <key>CFBundleDisplayName</key>
    <string>TimeTracker</string>
    <key>CFBundleIdentifier</key>
    <string>com.marcoschuster.timetracker</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
</dict>
</plist>
```

- [ ] **Step 5: Write `Sources/Support/TimeTracker.entitlements`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
```

(Sandbox is disabled to keep Keychain + network simple for a personal, locally-signed app.)

- [ ] **Step 6: Write `Sources/App/TimeTrackerApp.swift`**

```swift
import SwiftUI

@main
struct TimeTrackerApp: App {
    var body: some Scene {
        MenuBarExtra("TimeTracker", systemImage: "clock") {
            Text("TimeTracker")
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 7: Generate the project and build**

Run:
```bash
cd /Volumes/projects/timetracking
xcodegen generate
xcodebuild -project TimeTracker.xcodeproj -scheme TimeTracker -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Initialize repo and create private GitHub repo**

Run:
```bash
cd /Volumes/projects/timetracking
git init
git add .
git commit -m "chore: scaffold TimeTracker menu-bar app (XcodeGen + empty MenuBarExtra)"
gh repo create timetracker --private --source=. --remote=origin --push
```
Expected: repo `timetracker` created private, initial commit pushed.

---

## Phase 1 — Pure domain core (TDD)

> All Core types are `Codable` value types. Time is passed in explicitly as `Date` parameters — Core never reads the clock itself, which is what makes it testable.

### Task 1: Duration formatting

**Files:**
- Create: `Sources/Core/Duration.swift`
- Test: `Tests/CoreTests/DurationTests.swift`

**Interfaces:**
- Produces: `enum Duration { static func hmString(seconds: Int) -> String }` — formats a non-negative second count as `H:mm` (hours not zero-padded, minutes zero-padded, rounded to nearest minute, negative clamped to 0).

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import TimeTracker

final class DurationTests: XCTestCase {
    func testFormatsWholeHours() {
        XCTAssertEqual(Duration.hmString(seconds: 8 * 3600), "8:00")
    }
    func testFormatsHoursAndMinutes() {
        XCTAssertEqual(Duration.hmString(seconds: 8 * 3600 + 30 * 60), "8:30")
    }
    func testFormatsHalfHour() {
        XCTAssertEqual(Duration.hmString(seconds: 30 * 60), "0:30")
    }
    func testRoundsToNearestMinute() {
        XCTAssertEqual(Duration.hmString(seconds: 7 * 3600 + 59 * 60 + 40), "8:00")
        XCTAssertEqual(Duration.hmString(seconds: 7 * 3600 + 59 * 60 + 20), "7:59")
    }
    func testRoundingCarriesIntoHour() {
        XCTAssertEqual(Duration.hmString(seconds: 59 * 60 + 50), "1:00")
    }
    func testNegativeClampsToZero() {
        XCTAssertEqual(Duration.hmString(seconds: -100), "0:00")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project TimeTracker.xcodeproj -scheme TimeTracker -destination 'platform=macOS' -only-testing:TimeTrackerTests/DurationTests CODE_SIGNING_ALLOWED=NO`
Expected: FAIL — `cannot find 'Duration' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

enum Duration {
    static func hmString(seconds: Int) -> String {
        let clamped = max(0, seconds)
        let totalMinutes = Int((Double(clamped) / 60.0).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return String(format: "%d:%02d", hours, minutes)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same command as Step 2.
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Duration.swift Tests/CoreTests/DurationTests.swift
git commit -m "feat(core): H:mm duration formatting"
```

### Task 2: Session state machine

**Files:**
- Create: `Sources/Core/SessionState.swift`
- Create: `Sources/Core/WorkSession.swift`
- Test: `Tests/CoreTests/WorkSessionTests.swift`

**Interfaces:**
- Produces:
  - `enum SessionState: String, Codable { case idle, working, onBreak, ended }`
  - `struct WorkSession: Codable, Equatable` with:
    - `var state: SessionState`
    - `var start: Date?`
    - `var end: Date?`
    - `var completedBreakSeconds: Int` (sum of finished breaks)
    - `var currentBreakStart: Date?`
    - `static func idle() -> WorkSession`
    - `mutating func start(at: Date) throws`
    - `mutating func beginBreak(at: Date) throws`
    - `mutating func endBreak(at: Date) throws`
    - `mutating func end(at: Date) throws`
    - `func breakSeconds(asOf now: Date) -> Int` (completed + in-progress break)
    - `func grossSeconds(asOf now: Date) -> Int` (start→now or start→end)
    - `func netSeconds(asOf now: Date) -> Int` (gross − break, clamped ≥ 0)
  - `enum SessionError: Error, Equatable { case invalidTransition }`
- Transition rules: `start` only from `idle`; `beginBreak` only from `working`; `endBreak` only from `onBreak`; `end` only from `working` or `onBreak`. Any other call throws `.invalidTransition`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import TimeTracker

final class WorkSessionTests: XCTestCase {
    private func d(_ hms: String) -> Date {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "Europe/Vienna")!
        return f.date(from: "2026-06-24T\(hms)+02:00")!
    }

    func testStartFromIdleEntersWorking() throws {
        var s = WorkSession.idle()
        try s.start(at: d("09:00:00"))
        XCTAssertEqual(s.state, .working)
        XCTAssertEqual(s.start, d("09:00:00"))
    }

    func testCannotStartTwice() throws {
        var s = WorkSession.idle()
        try s.start(at: d("09:00:00"))
        XCTAssertThrowsError(try s.start(at: d("09:05:00"))) {
            XCTAssertEqual($0 as? SessionError, .invalidTransition)
        }
    }

    func testBreakOnlyFromWorking() {
        var s = WorkSession.idle()
        XCTAssertThrowsError(try s.beginBreak(at: d("09:00:00")))
    }

    func testBreaksAccumulate() throws {
        var s = WorkSession.idle()
        try s.start(at: d("09:00:00"))
        try s.beginBreak(at: d("10:00:00"))
        try s.endBreak(at: d("10:15:00"))
        try s.beginBreak(at: d("12:00:00"))
        try s.endBreak(at: d("12:30:00"))
        XCTAssertEqual(s.completedBreakSeconds, 45 * 60)
        XCTAssertEqual(s.state, .working)
    }

    func testInProgressBreakCountedAsOfNow() throws {
        var s = WorkSession.idle()
        try s.start(at: d("09:00:00"))
        try s.beginBreak(at: d("10:00:00"))
        XCTAssertEqual(s.breakSeconds(asOf: d("10:10:00")), 10 * 60)
    }

    func testEndFromWorkingAndOnBreak() throws {
        var s = WorkSession.idle()
        try s.start(at: d("09:00:00"))
        try s.end(at: d("17:00:00"))
        XCTAssertEqual(s.state, .ended)

        var s2 = WorkSession.idle()
        try s2.start(at: d("09:00:00"))
        try s2.beginBreak(at: d("16:00:00"))
        try s2.end(at: d("17:00:00"))
        XCTAssertEqual(s2.state, .ended)
    }

    func testEndWhileOnBreakFinalizesOpenBreak() throws {
        var s = WorkSession.idle()
        try s.start(at: d("09:00:00"))
        try s.beginBreak(at: d("12:00:00"))
        try s.end(at: d("12:30:00"))
        XCTAssertEqual(s.breakSeconds(asOf: d("12:30:00")), 30 * 60)
    }

    func testNetSeconds() throws {
        var s = WorkSession.idle()
        try s.start(at: d("09:00:00"))
        try s.beginBreak(at: d("12:00:00"))
        try s.endBreak(at: d("13:00:00"))
        try s.end(at: d("18:00:00"))
        XCTAssertEqual(s.grossSeconds(asOf: d("18:00:00")), 9 * 3600)
        XCTAssertEqual(s.netSeconds(asOf: d("18:00:00")), 8 * 3600)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project TimeTracker.xcodeproj -scheme TimeTracker -destination 'platform=macOS' -only-testing:TimeTrackerTests/WorkSessionTests CODE_SIGNING_ALLOWED=NO`
Expected: FAIL — `cannot find 'WorkSession' in scope`.

- [ ] **Step 3: Write `SessionState.swift`**

```swift
import Foundation

enum SessionState: String, Codable {
    case idle
    case working
    case onBreak
    case ended
}

enum SessionError: Error, Equatable {
    case invalidTransition
}
```

- [ ] **Step 4: Write `WorkSession.swift`**

```swift
import Foundation

struct WorkSession: Codable, Equatable {
    var state: SessionState
    var start: Date?
    var end: Date?
    var completedBreakSeconds: Int
    var currentBreakStart: Date?

    static func idle() -> WorkSession {
        WorkSession(state: .idle, start: nil, end: nil,
                    completedBreakSeconds: 0, currentBreakStart: nil)
    }

    mutating func start(at now: Date) throws {
        guard state == .idle else { throw SessionError.invalidTransition }
        state = .working
        start = now
    }

    mutating func beginBreak(at now: Date) throws {
        guard state == .working else { throw SessionError.invalidTransition }
        state = .onBreak
        currentBreakStart = now
    }

    mutating func endBreak(at now: Date) throws {
        guard state == .onBreak, let began = currentBreakStart else {
            throw SessionError.invalidTransition
        }
        completedBreakSeconds += Int(now.timeIntervalSince(began))
        currentBreakStart = nil
        state = .working
    }

    mutating func end(at now: Date) throws {
        guard state == .working || state == .onBreak else {
            throw SessionError.invalidTransition
        }
        if state == .onBreak, let began = currentBreakStart {
            completedBreakSeconds += Int(now.timeIntervalSince(began))
            currentBreakStart = nil
        }
        end = now
        state = .ended
    }

    func breakSeconds(asOf now: Date) -> Int {
        var total = completedBreakSeconds
        if state == .onBreak, let began = currentBreakStart {
            total += Int(now.timeIntervalSince(began))
        }
        return max(0, total)
    }

    func grossSeconds(asOf now: Date) -> Int {
        guard let start else { return 0 }
        let stop = end ?? now
        return max(0, Int(stop.timeIntervalSince(start)))
    }

    func netSeconds(asOf now: Date) -> Int {
        max(0, grossSeconds(asOf: now) - breakSeconds(asOf: now))
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: same command as Step 2.
Expected: PASS (8 tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/SessionState.swift Sources/Core/WorkSession.swift Tests/CoreTests/WorkSessionTests.swift
git commit -m "feat(core): work session state machine with break accumulation"
```

### Task 3: Auto-break rule + finalized summary

**Files:**
- Create: `Sources/Core/SessionSummary.swift`
- Create: `Sources/Core/AutoBreak.swift`
- Test: `Tests/CoreTests/AutoBreakTests.swift`

**Interfaces:**
- Consumes: `WorkSession` (must be `.ended` with non-nil `start`/`end`), `Duration.hmString`.
- Produces:
  - `struct SessionSummary: Codable, Equatable { let date: String; let total: String; let start: String; let breakStr: String; let end: String }` where each field is the exact string written to the sheet, and `func row() -> [String]` returns `[date, total, start, breakStr, end]` in column order.
  - `enum AutoBreak { static let thresholdSeconds = 6 * 3600; static let autoBreakSeconds = 30 * 60; static func effectiveBreakSeconds(grossSeconds: Int, manualBreakSeconds: Int) -> Int; static func summarize(_ session: WorkSession, timeZone: TimeZone) -> SessionSummary }`
- Rule: `effectiveBreakSeconds` returns `autoBreakSeconds` when `manualBreakSeconds == 0 && grossSeconds >= thresholdSeconds`, otherwise returns `manualBreakSeconds`. `total = max(0, gross − effectiveBreak)`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import TimeTracker

final class AutoBreakTests: XCTestCase {
    private let tz = TimeZone(identifier: "Europe/Vienna")!
    private func d(_ hms: String) -> Date {
        let f = ISO8601DateFormatter()
        f.timeZone = tz
        return f.date(from: "2026-06-24T\(hms)+02:00")!
    }
    private func ended(start: String, end: String, breakSecs: Int) -> WorkSession {
        var s = WorkSession.idle()
        try! s.start(at: d(start))
        s.completedBreakSeconds = breakSecs
        try! s.end(at: d(end))
        return s
    }

    func testAutoBreakFiresWhenZeroBreakAndOverSixHours() {
        XCTAssertEqual(AutoBreak.effectiveBreakSeconds(grossSeconds: 7 * 3600, manualBreakSeconds: 0), 30 * 60)
    }
    func testAutoBreakAtExactlySixHours() {
        XCTAssertEqual(AutoBreak.effectiveBreakSeconds(grossSeconds: 6 * 3600, manualBreakSeconds: 0), 30 * 60)
    }
    func testNoAutoBreakJustUnderSixHours() {
        XCTAssertEqual(AutoBreak.effectiveBreakSeconds(grossSeconds: 6 * 3600 - 60, manualBreakSeconds: 0), 0)
    }
    func testNoAutoBreakWhenAnyManualBreak() {
        XCTAssertEqual(AutoBreak.effectiveBreakSeconds(grossSeconds: 10 * 3600, manualBreakSeconds: 5 * 60), 5 * 60)
    }

    func testSummaryNoBreakOverSixHoursGetsAutoBreak() {
        let s = ended(start: "09:00:00", end: "16:00:00", breakSecs: 0) // 7h gross
        let sum = AutoBreak.summarize(s, timeZone: tz)
        XCTAssertEqual(sum.date, "2026-06-24")
        XCTAssertEqual(sum.start, "09:00")
        XCTAssertEqual(sum.end, "16:00")
        XCTAssertEqual(sum.breakStr, "0:30")
        XCTAssertEqual(sum.total, "6:30")
        XCTAssertEqual(sum.row(), ["2026-06-24", "6:30", "09:00", "0:30", "16:00"])
    }

    func testSummaryWithManualBreak() {
        let s = ended(start: "09:00:00", end: "18:00:00", breakSecs: 60 * 60) // 9h gross, 1h break
        let sum = AutoBreak.summarize(s, timeZone: tz)
        XCTAssertEqual(sum.breakStr, "1:00")
        XCTAssertEqual(sum.total, "8:00")
    }

    func testSummaryShortDayNoAutoBreak() {
        let s = ended(start: "09:00:00", end: "14:00:00", breakSecs: 0) // 5h gross
        let sum = AutoBreak.summarize(s, timeZone: tz)
        XCTAssertEqual(sum.breakStr, "0:00")
        XCTAssertEqual(sum.total, "5:00")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project TimeTracker.xcodeproj -scheme TimeTracker -destination 'platform=macOS' -only-testing:TimeTrackerTests/AutoBreakTests CODE_SIGNING_ALLOWED=NO`
Expected: FAIL — `cannot find 'AutoBreak' in scope`.

- [ ] **Step 3: Write `SessionSummary.swift`**

```swift
import Foundation

struct SessionSummary: Codable, Equatable {
    let date: String
    let total: String
    let start: String
    let breakStr: String
    let end: String

    func row() -> [String] {
        [date, total, start, breakStr, end]
    }
}
```

- [ ] **Step 4: Write `AutoBreak.swift`**

```swift
import Foundation

enum AutoBreak {
    static let thresholdSeconds = 6 * 3600
    static let autoBreakSeconds = 30 * 60

    static func effectiveBreakSeconds(grossSeconds: Int, manualBreakSeconds: Int) -> Int {
        if manualBreakSeconds == 0 && grossSeconds >= thresholdSeconds {
            return autoBreakSeconds
        }
        return manualBreakSeconds
    }

    static func summarize(_ session: WorkSession, timeZone: TimeZone) -> SessionSummary {
        let start = session.start!
        let end = session.end!
        let gross = max(0, Int(end.timeIntervalSince(start)))
        let manualBreak = session.breakSeconds(asOf: end)
        let effBreak = effectiveBreakSeconds(grossSeconds: gross, manualBreakSeconds: manualBreak)
        let total = max(0, gross - effBreak)

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let dateFmt = DateFormatter()
        dateFmt.calendar = cal
        dateFmt.timeZone = timeZone
        dateFmt.locale = Locale(identifier: "en_US_POSIX")
        dateFmt.dateFormat = "yyyy-MM-dd"
        let clockFmt = DateFormatter()
        clockFmt.calendar = cal
        clockFmt.timeZone = timeZone
        clockFmt.locale = Locale(identifier: "en_US_POSIX")
        clockFmt.dateFormat = "HH:mm"

        return SessionSummary(
            date: dateFmt.string(from: start),
            total: Duration.hmString(seconds: total),
            start: clockFmt.string(from: start),
            breakStr: Duration.hmString(seconds: effBreak),
            end: clockFmt.string(from: end)
        )
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: same command as Step 2.
Expected: PASS (7 tests).

- [ ] **Step 6: Run the full Core test suite**

Run: `xcodebuild test -project TimeTracker.xcodeproj -scheme TimeTracker -destination 'platform=macOS' -only-testing:TimeTrackerTests CODE_SIGNING_ALLOWED=NO`
Expected: PASS (all Core tests).

- [ ] **Step 7: Commit**

```bash
git add Sources/Core/SessionSummary.swift Sources/Core/AutoBreak.swift Tests/CoreTests/AutoBreakTests.swift
git commit -m "feat(core): auto-break rule and finalized session summary"
```

---

## Phase 2 — Persistence adapters

> These touch the filesystem and are verified manually (Phase 7), not unit-tested. They are thin and deterministic.

### Task 4: App paths + live session store + history log + pending queue

**Files:**
- Create: `Sources/Persistence/AppPaths.swift`
- Create: `Sources/Persistence/LiveSessionStore.swift`
- Create: `Sources/Persistence/HistoryLog.swift`
- Create: `Sources/Persistence/PendingQueue.swift`

**Interfaces:**
- Consumes: `WorkSession`, `SessionSummary`.
- Produces:
  - `enum AppPaths { static var directory: URL }` → `~/Library/Application Support/TimeTracker` (created if missing).
  - `struct LiveSessionStore { func save(_ s: WorkSession); func load() -> WorkSession?; func clear() }`.
  - `struct HistoryLog { func append(_ s: SessionSummary) }` → appends one JSON object per line to `history.jsonl`.
  - `struct PendingQueue { func enqueue(_ s: SessionSummary); func all() -> [SessionSummary]; func replace(with: [SessionSummary]) }` → persisted to `pending.json` as a JSON array.

- [ ] **Step 1: Write `AppPaths.swift`**

```swift
import Foundation

enum AppPaths {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("TimeTracker", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
```

- [ ] **Step 2: Write `LiveSessionStore.swift`**

```swift
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
```

- [ ] **Step 3: Write `HistoryLog.swift`**

```swift
import Foundation

struct HistoryLog {
    private var url: URL { AppPaths.directory.appendingPathComponent("history.jsonl") }

    func append(_ summary: SessionSummary) {
        guard let data = try? JSONEncoder().encode(summary) else { return }
        var line = data
        line.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(line)
        } else {
            try? line.write(to: url, options: .atomic)
        }
    }
}
```

- [ ] **Step 4: Write `PendingQueue.swift`**

```swift
import Foundation

struct PendingQueue {
    private var url: URL { AppPaths.directory.appendingPathComponent("pending.json") }

    func all() -> [SessionSummary] {
        guard let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([SessionSummary].self, from: data) else { return [] }
        return items
    }

    func enqueue(_ summary: SessionSummary) {
        var items = all()
        items.append(summary)
        replace(with: items)
    }

    func replace(with items: [SessionSummary]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
```

- [ ] **Step 5: Build to verify it compiles**

Run: `xcodegen generate && xcodebuild -project TimeTracker.xcodeproj -scheme TimeTracker -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Sources/Persistence
git commit -m "feat(persistence): live session store, history log, pending queue"
```

---

## Phase 3 — Google Sheets adapters

### Task 5: Keychain store + service account model

**Files:**
- Create: `Sources/Google/KeychainStore.swift`
- Create: `Sources/Google/ServiceAccount.swift`

**Interfaces:**
- Produces:
  - `enum KeychainStore { static func save(json: Data) -> Bool; static func load() -> Data?; static func delete() }` — generic password item, service `com.marcoschuster.timetracker`, account `service-account-json`.
  - `struct ServiceAccount: Decodable { let clientEmail: String; let privateKey: String; let tokenUri: String }` decoding keys `client_email`, `private_key`, `token_uri`; `static func from(_ data: Data) throws -> ServiceAccount`.

- [ ] **Step 1: Write `KeychainStore.swift`**

```swift
import Foundation
import Security

enum KeychainStore {
    private static let service = "com.marcoschuster.timetracker"
    private static let account = "service-account-json"

    static func save(json: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = json
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }

    static func load() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
```

- [ ] **Step 2: Write `ServiceAccount.swift`**

```swift
import Foundation

struct ServiceAccount: Decodable {
    let clientEmail: String
    let privateKey: String
    let tokenUri: String

    enum CodingKeys: String, CodingKey {
        case clientEmail = "client_email"
        case privateKey = "private_key"
        case tokenUri = "token_uri"
    }

    static func from(_ data: Data) throws -> ServiceAccount {
        try JSONDecoder().decode(ServiceAccount.self, from: data)
    }
}
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodegen generate && xcodebuild -project TimeTracker.xcodeproj -scheme TimeTracker -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Sources/Google/KeychainStore.swift Sources/Google/ServiceAccount.swift
git commit -m "feat(google): keychain store and service-account model"
```

### Task 6: JWT signer (RS256)

**Files:**
- Create: `Sources/Google/JWTSigner.swift`

**Interfaces:**
- Consumes: `ServiceAccount`.
- Produces: `enum JWTSigner { static func assertion(for account: ServiceAccount, scope: String, now: Date, lifetimeSeconds: Int) throws -> String; enum JWTError: Error { case badPrivateKey, signFailed } }`. Builds header `{alg:RS256,typ:JWT}`, claims `{iss,scope,aud:tokenUri,iat,exp}`, base64url-encodes both, signs `header.claims` with the RSA private key using `SecKeyCreateSignature(.rsaSignatureMessagePKCS1v15SHA256)`, returns `header.claims.signature`.

- [ ] **Step 1: Write `JWTSigner.swift`**

```swift
import Foundation
import Security

enum JWTSigner {
    enum JWTError: Error { case badPrivateKey, signFailed }

    static func assertion(for account: ServiceAccount, scope: String, now: Date, lifetimeSeconds: Int = 3600) throws -> String {
        let header = #"{"alg":"RS256","typ":"JWT"}"#
        let iat = Int(now.timeIntervalSince1970)
        let exp = iat + lifetimeSeconds
        let claims = "{\"iss\":\"\(account.clientEmail)\",\"scope\":\"\(scope)\",\"aud\":\"\(account.tokenUri)\",\"iat\":\(iat),\"exp\":\(exp)}"

        let signingInput = base64url(Data(header.utf8)) + "." + base64url(Data(claims.utf8))
        let key = try privateKey(from: account.privateKey)

        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            key,
            .rsaSignatureMessagePKCS1v15SHA256,
            Data(signingInput.utf8) as CFData,
            &error
        ) as Data? else {
            throw JWTError.signFailed
        }
        return signingInput + "." + base64url(signature)
    }

    private static func privateKey(from pem: String) throws -> SecKey {
        let cleaned = pem
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "\\n", with: "\n")
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        guard let der = Data(base64Encoded: cleaned) else { throw JWTError.badPrivateKey }
        let pkcs1 = try stripPKCS8Header(der)
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(pkcs1 as CFData, attrs as CFDictionary, &error) else {
            throw JWTError.badPrivateKey
        }
        return key
    }

    private static func stripPKCS8Header(_ der: Data) throws -> Data {
        let bytes = [UInt8](der)
        guard bytes.first == 0x30 else { throw JWTError.badPrivateKey }
        let marker: [UInt8] = [0x04, 0x82]
        var i = 0
        while i < bytes.count - 4 {
            if bytes[i] == marker[0] && bytes[i + 1] == marker[1] {
                let len = Int(bytes[i + 2]) << 8 | Int(bytes[i + 3])
                let start = i + 4
                let end = start + len
                if end <= bytes.count {
                    return Data(bytes[start..<end])
                }
            }
            i += 1
        }
        throw JWTError.badPrivateKey
    }

    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
```

> Note: `SecKeyCreateWithData` for RSA expects a PKCS#1 `RSAPrivateKey`; Google keys are PKCS#8, so `stripPKCS8Header` extracts the inner key octet-string. If parsing proves brittle in manual testing, the fallback is to add a small JWT library via SwiftPM — but try the dependency-free path first.

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodegen generate && xcodebuild -project TimeTracker.xcodeproj -scheme TimeTracker -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Sources/Google/JWTSigner.swift
git commit -m "feat(google): RS256 JWT assertion signer"
```

### Task 7: Google auth (token exchange)

**Files:**
- Create: `Sources/Google/GoogleAuth.swift`

**Interfaces:**
- Consumes: `ServiceAccount`, `JWTSigner`.
- Produces: `actor GoogleAuth { init(account: ServiceAccount); func accessToken() async throws -> String; enum AuthError: Error { case tokenRequestFailed(Int), badResponse } }`. Caches the token in-memory until ~60s before expiry; on miss, signs a JWT (scope `https://www.googleapis.com/auth/spreadsheets`) and POSTs `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=...` (form-encoded) to `account.tokenUri`.

- [ ] **Step 1: Write `GoogleAuth.swift`**

```swift
import Foundation

actor GoogleAuth {
    enum AuthError: Error { case tokenRequestFailed(Int), badResponse }

    private let account: ServiceAccount
    private let scope = "https://www.googleapis.com/auth/spreadsheets"
    private var cachedToken: String?
    private var expiresAt: Date = .distantPast

    init(account: ServiceAccount) {
        self.account = account
    }

    func accessToken(now: Date = Date()) async throws -> String {
        if let token = cachedToken, now < expiresAt.addingTimeInterval(-60) {
            return token
        }
        let assertion = try JWTSigner.assertion(for: account, scope: scope, now: now)
        var request = URLRequest(url: URL(string: account.tokenUri)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=\(assertion)"
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError.badResponse }
        guard http.statusCode == 200 else { throw AuthError.tokenRequestFailed(http.statusCode) }

        struct TokenResponse: Decodable {
            let access_token: String
            let expires_in: Int
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        cachedToken = decoded.access_token
        expiresAt = now.addingTimeInterval(TimeInterval(decoded.expires_in))
        return decoded.access_token
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodegen generate && xcodebuild -project TimeTracker.xcodeproj -scheme TimeTracker -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Sources/Google/GoogleAuth.swift
git commit -m "feat(google): service-account access token exchange with caching"
```

### Task 8: Sheets client (append row + test connection) + header ensure

**Files:**
- Create: `Sources/Google/SheetsClient.swift`

**Interfaces:**
- Consumes: `GoogleAuth`.
- Produces: `struct SheetsClient { init(auth: GoogleAuth, spreadsheetId: String); func spreadsheetTitle() async throws -> String; func ensureHeader() async throws; func append(row: [String]) async throws; enum SheetsError: Error { case http(Int) } }`.
  - `spreadsheetTitle`: `GET /v4/spreadsheets/{id}?fields=properties.title` (test connection).
  - `ensureHeader`: `GET /v4/spreadsheets/{id}/values/A1:E1`; if empty, `PUT` the header `["date","total hours","start","break","end"]` to `A1:E1` with `valueInputOption=RAW`.
  - `append`: `POST /v4/spreadsheets/{id}/values/A:E:append?valueInputOption=RAW&insertDataOption=INSERT_ROWS` with body `{"values":[row]}`.

- [ ] **Step 1: Write `SheetsClient.swift`**

```swift
import Foundation

struct SheetsClient {
    enum SheetsError: Error { case http(Int) }

    private let auth: GoogleAuth
    private let spreadsheetId: String
    private let base = "https://sheets.googleapis.com/v4/spreadsheets"
    static let header = ["date", "total hours", "start", "break", "end"]

    init(auth: GoogleAuth, spreadsheetId: String) {
        self.auth = auth
        self.spreadsheetId = spreadsheetId
    }

    func spreadsheetTitle() async throws -> String {
        let url = URL(string: "\(base)/\(spreadsheetId)?fields=properties.title")!
        let data = try await send(URLRequest(url: url))
        struct Resp: Decodable { struct P: Decodable { let title: String }; let properties: P }
        return try JSONDecoder().decode(Resp.self, from: data).properties.title
    }

    func ensureHeader() async throws {
        let getURL = URL(string: "\(base)/\(spreadsheetId)/values/A1:E1")!
        let data = try await send(URLRequest(url: getURL))
        struct ValuesResp: Decodable { let values: [[String]]? }
        let existing = try JSONDecoder().decode(ValuesResp.self, from: data).values ?? []
        guard existing.isEmpty || existing.first?.isEmpty == true else { return }

        var put = URLRequest(url: URL(string: "\(base)/\(spreadsheetId)/values/A1:E1?valueInputOption=RAW")!)
        put.httpMethod = "PUT"
        put.setValue("application/json", forHTTPHeaderField: "Content-Type")
        put.httpBody = try JSONSerialization.data(withJSONObject: ["values": [Self.header]])
        _ = try await send(put)
    }

    func append(row: [String]) async throws {
        var req = URLRequest(url: URL(string: "\(base)/\(spreadsheetId)/values/A:E:append?valueInputOption=RAW&insertDataOption=INSERT_ROWS")!)
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
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodegen generate && xcodebuild -project TimeTracker.xcodeproj -scheme TimeTracker -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Sources/Google/SheetsClient.swift
git commit -m "feat(google): sheets client (append RAW, ensure header, test connection)"
```

### Task 9: Sync orchestrator

**Files:**
- Create: `Sources/Google/SheetSync.swift`

**Interfaces:**
- Consumes: `PendingQueue`, `SheetsClient`, `KeychainStore`, `ServiceAccount`, `GoogleAuth`, `Preferences` (for `sheetId`).
- Produces:
  - `enum SyncStatus: Equatable { case idle, syncing, synced(Date), pending(Int), failed(String) }`
  - `actor SheetSync { init(queue: PendingQueue); func configure(serviceAccountJSON: Data, sheetId: String) throws; func testConnection() async throws -> String; func flush() async -> SyncStatus }`.
  - `flush`: builds a `SheetsClient` from current config; if no config, returns `.failed("not configured")`; calls `ensureHeader()` once, then appends each queued row **in order**, removing successes from the queue via `replace(with:)`; stops on first failure (keeps remainder queued) and returns `.pending(remaining)` or `.failed`. On full drain returns `.synced(now)`.

- [ ] **Step 1: Write `SheetSync.swift`**

```swift
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
            return items.isEmpty ? .synced(now) : .pending(items.count)
        }
    }

    enum SyncError: Error { case notConfigured }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodegen generate && xcodebuild -project TimeTracker.xcodeproj -scheme TimeTracker -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Sources/Google/SheetSync.swift
git commit -m "feat(google): pending-queue sync orchestrator with ordered drain"
```

---

## Phase 4 — Settings glue

### Task 10: Preferences + launch at login

**Files:**
- Create: `Sources/Settings/Preferences.swift`
- Create: `Sources/Settings/LaunchAtLogin.swift`

**Interfaces:**
- Produces:
  - `enum Preferences { static var sheetId: String { get set }; static var lastSyncEpoch: Double { get set } }` backed by `UserDefaults.standard`.
  - `enum LaunchAtLogin { static var isEnabled: Bool { get }; static func set(_ enabled: Bool) }` using `SMAppService.mainApp.register()/unregister()`.

- [ ] **Step 1: Write `Preferences.swift`**

```swift
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
```

- [ ] **Step 2: Write `LaunchAtLogin.swift`**

```swift
import Foundation
import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            NSLog("LaunchAtLogin error: \(error.localizedDescription)")
        }
    }
}
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodegen generate && xcodebuild -project TimeTracker.xcodeproj -scheme TimeTracker -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Sources/Settings
git commit -m "feat(settings): preferences and launch-at-login via SMAppService"
```

---

## Phase 5 — Controller + UI

### Task 11: Notifier (10h nudge)

**Files:**
- Create: `Sources/Notifications/Notifier.swift`

**Interfaces:**
- Produces: `enum Notifier { static func requestAuthorization(); static func nudgeTenHours() }`. `nudgeTenHours` posts a `UNNotificationRequest` with title "Still tracking — 10h reached" and body referencing the Austrian daily maximum, identifier `ten-hour-nudge` (so it isn't duplicated).

- [ ] **Step 1: Write `Notifier.swift`**

```swift
import Foundation
import UserNotifications

enum Notifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func nudgeTenHours() {
        let content = UNMutableNotificationContent()
        content.title = "Still tracking — 10h reached"
        content.body = "You've been working 10 hours. Austrian law caps the working day at 10h — time to end the session?"
        content.sound = .default
        let request = UNNotificationRequest(identifier: "ten-hour-nudge", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodegen generate && xcodebuild -project TimeTracker.xcodeproj -scheme TimeTracker -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Sources/Notifications/Notifier.swift
git commit -m "feat(notifications): 10h working-time nudge"
```

### Task 12: AppState controller

**Files:**
- Create: `Sources/App/AppState.swift`

**Interfaces:**
- Consumes: `WorkSession`, `AutoBreak`, `LiveSessionStore`, `HistoryLog`, `PendingQueue`, `SheetSync`, `KeychainStore`, `Preferences`, `LaunchAtLogin`, `Notifier`, `Duration`.
- Produces a `@MainActor final class AppState: ObservableObject` with:
  - `@Published private(set) var session: WorkSession`
  - `@Published private(set) var syncStatus: SyncStatus`
  - `@Published var nowTick: Date` (drives live label; updated by a 1s timer)
  - `let timeZone = TimeZone(identifier: "Europe/Vienna")!`
  - computed `var menuBarText: String?` (nil when idle; else `Duration.hmString(seconds: session.netSeconds(asOf: nowTick))`)
  - `var stateGlyph: String`
  - actions: `func startDay()`, `func pause()`, `func resume()`, `func endDay()`, `func adjustStart(to: Date)`
  - `func configureGoogle(json: Data, sheetId: String) async -> Result<String, Error>` (saves to Keychain + Preferences, configures sync, returns spreadsheet title on success)
  - `func retrySync()`
  - `var hasStaleSession: Bool` and `func endStaleSession(at: Date)`
  - lifecycle: `func onLaunch()` (restore live session, load Google config from Keychain, start timer, schedule checks), `func onWake()` (flush + stale check).

- [ ] **Step 1: Write `AppState.swift`**

```swift
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
            try? sync.configure(serviceAccountJSON: json, sheetId: Preferences.sheetId) // configure is async; see note
        }
        Notifier.requestAuthorization()
        startTimer()
        Task { await flush() }
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
```

> Implementation note for the `onLaunch` Keychain reconfigure: `sync.configure` is `async`. Wrap the restore in a `Task { try? await sync.configure(...) ; await flush() }` rather than calling it synchronously. Adjust the two lines accordingly when implementing — the intent is: on launch, if a key + sheetId exist, reconfigure sync, then flush.

- [ ] **Step 2: Fix the `onLaunch` async configure**

Replace the synchronous `try? sync.configure(...)` block with:

```swift
        if let json = KeychainStore.load(), !Preferences.sheetId.isEmpty {
            let sheetId = Preferences.sheetId
            Task { try? await sync.configure(serviceAccountJSON: json, sheetId: sheetId); await flush() }
        }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodegen generate && xcodebuild -project TimeTracker.xcodeproj -scheme TimeTracker -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Sources/App/AppState.swift
git commit -m "feat(app): AppState controller wiring core, persistence, sync, nudges"
```

### Task 13: Popover, menu-bar label, stale-session view, settings view, app wiring

**Files:**
- Create: `Sources/UI/MenuBarLabel.swift`
- Create: `Sources/UI/PopoverView.swift`
- Create: `Sources/UI/StaleSessionView.swift`
- Create: `Sources/UI/SettingsView.swift`
- Modify: `Sources/App/TimeTrackerApp.swift`

**Interfaces:**
- Consumes: `AppState`.
- Produces SwiftUI views; `TimeTrackerApp` owns a `@StateObject AppState`, renders `MenuBarExtra { PopoverView() }` with a `MenuBarLabel`, calls `appState.onLaunch()` on appear, and registers an `NSWorkspace.didWakeNotification` observer calling `onWake()`.

- [ ] **Step 1: Write `MenuBarLabel.swift`**

```swift
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
```

- [ ] **Step 2: Write `StaleSessionView.swift`**

```swift
import SwiftUI

struct StaleSessionView: View {
    @ObservedObject var app: AppState
    @State private var endTime: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Unfinished session").font(.headline)
            if let start = app.todayStartString {
                Text("Started \(start) on a previous day and is still running.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            DatePicker("End time", selection: $endTime, displayedComponents: [.date, .hourAndMinute])
            HStack {
                Button("End now") { app.endStaleSession(at: Date()) }
                Button("End at selected time") { app.endStaleSession(at: endTime) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 320)
    }
}
```

- [ ] **Step 3: Write `SettingsView.swift`**

```swift
import SwiftUI

struct SettingsView: View {
    @ObservedObject var app: AppState
    @State private var jsonText: String = ""
    @State private var sheetId: String = Preferences.sheetId
    @State private var launchAtLogin: Bool = LaunchAtLogin.isEnabled
    @State private var testResult: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings").font(.title2).bold()

            Text("Service account JSON").font(.headline)
            TextEditor(text: $jsonText)
                .font(.system(.caption, design: .monospaced))
                .frame(height: 120)
                .border(.secondary)

            Text("Google Sheet ID").font(.headline)
            TextField("spreadsheet id from the URL", text: $sheetId)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Save & Test connection") { saveAndTest() }
                Text(testResult).font(.callout).foregroundStyle(.secondary)
            }

            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in LaunchAtLogin.set(newValue) }

            Spacer()
        }
        .padding()
        .frame(width: 420, height: 360)
    }

    private func saveAndTest() {
        guard let data = jsonText.data(using: .utf8), !sheetId.isEmpty else {
            testResult = "Paste JSON and a Sheet ID first."
            return
        }
        testResult = "Testing…"
        Task {
            let result = await app.configureGoogle(json: data, sheetId: sheetId)
            switch result {
            case .success(let title): testResult = "Connected to: \(title)"
            case .failure(let error): testResult = "Failed: \(error.localizedDescription)"
            }
        }
    }
}
```

- [ ] **Step 4: Write `PopoverView.swift`**

```swift
import SwiftUI

struct PopoverView: View {
    @ObservedObject var app: AppState
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if app.hasStaleSession {
                StaleSessionView(app: app)
                Divider()
            }

            statusLine
            if app.session.start != nil {
                figures
            }
            Divider()
            buttons
            Divider()
            footer
        }
        .padding()
        .frame(width: 300)
        .sheet(isPresented: $showSettings) { SettingsView(app: app) }
    }

    private var statusLine: some View {
        Group {
            switch app.session.state {
            case .idle, .ended:
                Text("Not working").font(.headline)
            case .working:
                Text("Working — \(app.todayNetString)").font(.headline)
            case .onBreak:
                Text("On break — \(app.todayBreakString)").font(.headline)
            }
        }
    }

    private var figures: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let start = app.todayStartString { Text("Start: \(start)") }
            Text("Break: \(app.todayBreakString)")
            Text("Worked: \(app.todayNetString)")
        }
        .font(.callout).foregroundStyle(.secondary)
    }

    @ViewBuilder private var buttons: some View {
        switch app.session.state {
        case .idle, .ended:
            Button("Start") { app.startDay() }.keyboardShortcut(.defaultAction)
        case .working:
            HStack {
                Button("Pause") { app.pause() }
                Button("End") { app.endDay() }
            }
        case .onBreak:
            HStack {
                Button("Resume") { app.resume() }
                Button("End") { app.endDay() }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            syncFooter
            HStack {
                Button("Open Sheet") { openSheet() }
                    .disabled(Preferences.sheetId.isEmpty)
                Spacer()
                Button("Settings") { showSettings = true }
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
    }

    private var syncFooter: some View {
        HStack(spacing: 6) {
            switch app.syncStatus {
            case .idle: Text("—").foregroundStyle(.secondary)
            case .syncing: Text("Syncing…").foregroundStyle(.secondary)
            case .synced: Text("Synced ✓").foregroundStyle(.green)
            case .pending(let n):
                Text("⚠️ \(n) pending").foregroundStyle(.orange)
                Button("Retry") { app.retrySync() }
            case .failed(let msg):
                Text("⚠️ \(msg)").foregroundStyle(.red)
                Button("Retry") { app.retrySync() }
            }
        }
        .font(.callout)
    }

    private func openSheet() {
        guard !Preferences.sheetId.isEmpty,
              let url = URL(string: "https://docs.google.com/spreadsheets/d/\(Preferences.sheetId)/edit") else { return }
        NSWorkspace.shared.open(url)
    }
}
```

- [ ] **Step 5: Rewrite `TimeTrackerApp.swift`**

```swift
import SwiftUI
import AppKit

@main
struct TimeTrackerApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(app: app)
                .onAppear {
                    app.onLaunch()
                    NSWorkspace.shared.notificationCenter.addObserver(
                        forName: NSWorkspace.didWakeNotification,
                        object: nil, queue: .main
                    ) { _ in app.onWake() }
                }
        } label: {
            MenuBarLabel(app: app)
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 6: Build to verify it compiles**

Run: `xcodegen generate && xcodebuild -project TimeTracker.xcodeproj -scheme TimeTracker -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add Sources/UI Sources/App/TimeTrackerApp.swift
git commit -m "feat(ui): menu-bar label, popover, settings, stale-session prompt, app wiring"
```

---

## Phase 6 — README + end-to-end manual verification

### Task 14: README with Google setup checklist and build/run instructions

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write `README.md`**

````markdown
# TimeTracker

A macOS menu-bar app that tracks work sessions and appends one row per session to a personal Google Sheet.

## Google setup (one-time)

1. console.cloud.google.com → create a project (`timetracking`).
2. APIs & Services → Library → enable **Google Sheets API**.
3. APIs & Services → Credentials → Create credentials → **Service account**.
4. Service account → **Keys** → Add key → **JSON**; download it.
5. Copy `client_email` from the JSON.
6. In your Google Sheet → **Share** → paste `client_email` → **Editor**.
7. Copy the Sheet ID from the URL: `docs.google.com/spreadsheets/d/<SHEET_ID>/edit`.

In the app: open **Settings**, paste the JSON, paste the Sheet ID, click **Save & Test connection** (key is stored in the macOS Keychain).

## Sheet format

Columns: `date | total hours | start | break | end`. Date `yyyy-MM-dd`; start/end `HH:mm`; break & total `H:mm`. All times in `Europe/Vienna`. One row appended per session. `total = (end − start) − break`. If you take no manual break and the day is ≥ 6h gross, a 30-minute break is added automatically.

## Build & run

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project TimeTracker.xcodeproj -scheme TimeTracker -destination 'platform=macOS' build
```

To produce a standalone app you can drop in `/Applications`:

```bash
xcodebuild -project TimeTracker.xcodeproj -scheme TimeTracker -configuration Release \
  -derivedDataPath build CODE_SIGN_IDENTITY=- build
cp -R build/Build/Products/Release/TimeTracker.app /Applications/
```

## Tests

```bash
xcodebuild test -project TimeTracker.xcodeproj -scheme TimeTracker -destination 'platform=macOS'
```

Local data lives in `~/Library/Application Support/TimeTracker/` (`live-session.json`, `history.jsonl`, `pending.json`). `history.jsonl` is the source of truth; the Google Sheet is a sync target.
````

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: README with Google setup, sheet format, build/run/test"
```

### Task 15: End-to-end manual verification

- [ ] **Step 1: Run the unit suite**

Run: `xcodebuild test -project TimeTracker.xcodeproj -scheme TimeTracker -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
Expected: all Core tests pass.

- [ ] **Step 2: Build & launch the app**

Run a Release build, copy to `/Applications`, launch. Confirm a clock icon appears in the menu bar and no Dock icon appears.

- [ ] **Step 3: Configure Google**

Open Settings, paste the service-account JSON + Sheet ID, click **Save & Test connection**. Expected: "Connected to: <sheet title>". Verify the header row appears in the sheet after the first sync.

- [ ] **Step 4: Happy path**

Start → confirm the menu-bar shows a ticking time. Pause → Resume → confirm break accrues. End → confirm a row appears in the sheet within a few seconds with correct date/start/break/end/total, and the footer shows "Synced ✓".

- [ ] **Step 5: Auto-break**

Temporarily verify the rule with a short day by editing start via the popover (adjust start to >6h ago), end with no manual break, and confirm `break = 0:30` and total reduced accordingly. (Or trust the unit tests — `AutoBreakTests` already covers the math.)

- [ ] **Step 6: Offline queue**

Turn off Wi-Fi, End a session → confirm it completes instantly and footer shows "⚠️ 1 pending". Turn Wi-Fi back on, click Retry (or relaunch) → confirm it flushes to the sheet in order.

- [ ] **Step 7: Stale session**

With a session running, set the Mac clock forward a day (or restart the app after midnight) → confirm the stale-session prompt appears and ending it writes the correct date/end.

- [ ] **Step 8: Launch at login**

Toggle "Launch at login" on in Settings → confirm via System Settings → General → Login Items that TimeTracker is listed.

- [ ] **Step 9: Final commit / push**

```bash
git add -A
git commit -m "chore: end-to-end verification pass" --allow-empty
git push
```

---

## Self-Review

**Spec coverage:**
- Menu-bar app, start/pause/end → Tasks 12–13. ✓
- Pause implies resume; multiple breaks sum → Task 2. ✓
- Google Sheet sync (service account) → Tasks 5–9. ✓
- Columns date/total/start/break/end → Task 3 (`SessionSummary`), Task 8 (header/append). ✓
- Auto 30-min break after 6h if no manual break → Task 3. ✓
- Net total, Europe/Vienna, HH:mm durations → Tasks 1, 3 + Global Constraints. ✓
- Crash recovery / persist live session → Tasks 4, 12. ✓
- Sleep counts as working → Task 2 (wall-clock gross) + no sleep detection anywhere. ✓
- Append one row per session, same-date allowed → Task 8 (`A:E:append` + INSERT_ROWS), Task 12 (enqueue per End). ✓
- Optimistic local queue + background retry + JSONL source of truth → Tasks 4, 9, 12. ✓
- Stale-session prompt (launch/wake/midnight), confirm end time → Tasks 12 (`hasStaleSession`), 13 (`StaleSessionView`). ✓
- 10h nudge → Tasks 11, 12. ✓
- Menu-bar icon + live net time; context-aware popover; sync footer; Open Sheet; Settings; Quit → Task 13. ✓
- Adjustable current session start, choose end time; no in-app history editor → Task 12 (`adjustStart`, `endStaleSession`), Task 13. ✓
- Agent app (no Dock), launch at login default-on, local signing, bundle id → Task 0, Task 10. ✓
- Private repo via gh → Task 0. ✓
- First-run Settings (paste JSON → Keychain, Sheet ID → prefs, test via metadata read) → Tasks 5, 8, 13. ✓
- TDD on pure core, manual I/O verification → Phases 1 (TDD) and 6. ✓

**Note on "launch at login default on":** the spec says default-on, but `SMAppService` requires an explicit registration call (the OS won't auto-enable it). The honest implementation is: on first launch, if the user has never set the toggle, call `LaunchAtLogin.set(true)` once. Add this to `AppState.onLaunch()` guarded by a `UserDefaults` "didSetInitialLaunchAtLogin" flag during Task 12 implementation. (Flagging here rather than silently dropping it.)

**Placeholder scan:** No TBD/TODO/"handle errors appropriately" left; every code step has concrete code.

**Type consistency:** `SessionSummary.row()` order matches `SheetsClient.header`; `SyncStatus` cases used identically in `SheetSync` and `PopoverView`; `WorkSession` field names consistent across Core, Persistence, AppState.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-24-timetracker.md`.
