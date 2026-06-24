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

Columns: `date | total hours | start | break | end | overhours`. Date `yyyy-MM-dd`; start/end `HH:mm`; break & total `H:mm`. All times in `Europe/Vienna`. One row appended per session. `total = (end − start) − break`. If you take no manual break and the day is ≥ 6h gross, a 30-minute break is added automatically.

The app appends only `A:E`; everything below is installed once (gated on the `overhours` header) and is pure Google Sheets formulas — it self-fills and back-fills history with no per-session code:

- **`overhours` (col F)** — `total − target`, where `target` is the standard workday. Displayed signed (`+0:42` / `-0:48` / `0:00`), filled **green** when over and **red** when under.
- **`Weekly` tab** — editable **target cell** (defaults to `6:48`) referenced by every formula, plus a self-updating per-week rollup (Mon–Sun): `week-start | hours worked | Σ overhours | running balance`. Change the target cell and the whole sheet recomputes.

(Columns `G`/`H` on the log sheet are hidden helpers — the week key and numeric worked hours used by the rollup.)

## Build & run

```bash
brew install xcodegen
make build
```

To produce a standalone app and drop it in `/Applications`:

```bash
make install
```

`make` targets: `build`, `test`, `release` (Release build under `build/`), `install` (release + copy to `/Applications`), `generate` (regenerate the Xcode project from `project.yml`), `clean`. The Xcode project is regenerated automatically whenever `project.yml` changes.

## Tests

```bash
make test
```

Local data lives in `~/Library/Application Support/TimeTracker/` (`live-session.json`, `history.jsonl`, `pending.json`). `history.jsonl` is the source of truth; the Google Sheet is a sync target.
