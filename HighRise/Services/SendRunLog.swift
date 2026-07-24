import Foundation

/// A durable journal of one merge-and-deliver run, written record-by-record
/// as the run progresses.
///
/// The in-memory `outcomes` array is otherwise the app's only ledger of who
/// was already emailed — and the app quits when its window closes — so a quit
/// or crash 300 recipients into a 1,000-recipient run would destroy the only
/// record and make an innocent "import the list again and press Send" a
/// silent double-send to 300 people. The journal survives; an unfinished one
/// is surfaced on the next launch.
struct SendRunLog: Codable, Equatable {

    struct Record: Codable, Equatable {
        let email: String
        let name: String
        /// "sent" / "drafted" / "skipped" / "failed"
        let status: String
        let reason: String?
        let at: Date
    }

    var startedAt: Date
    /// "send" or "draft" — what a success in `records` actually did.
    var mode: String
    /// How many recipients the run set out to reach.
    var total: Int
    var records: [Record] = []
    /// True once the run loop ended (completed, stopped early, or the user
    /// cancelled/acknowledged). False on disk = the app died mid-run.
    var finished = false

    var deliveredCount: Int {
        records.filter { $0.status == "sent" || $0.status == "drafted" }.count
    }

    /// The journal as CSV, for the "who already got it" export.
    func csv() -> String {
        var lines = ["Email,Name,Status,Reason"]
        for record in records {
            let fields = [record.email, record.name, record.status, record.reason ?? ""]
            lines.append(fields.map { field in
                field.contains(where: { ",\"\n".contains($0) })
                    ? "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                    : field
            }.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

/// JSON persistence for the run journal, same injectable/atomic/fail-silent
/// pattern as `TemplateLibraryStore` and `SessionStore` (`directory: nil` →
/// inert, for tests).
final class SendRunLogStore {

    private let url: URL?

    init(directory: URL? = TemplateLibraryStore.defaultDirectory) {
        url = directory?.appendingPathComponent("last-run.json")
    }

    func save(_ log: SendRunLog) {
        guard let url else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(log) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func load() -> SendRunLog? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SendRunLog.self, from: data)
    }

    /// The journal of a run that never finished — i.e. the app quit or
    /// crashed mid-run. Nil when the last run ended normally.
    func loadIncomplete() -> SendRunLog? {
        guard let log = load(), !log.finished else { return nil }
        return log
    }
}
