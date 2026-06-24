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
