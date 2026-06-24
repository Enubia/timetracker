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
