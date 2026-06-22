import os

/// Per-subsystem loggers for HighRise. Apple unified logging only — never
/// `print()` — so diagnostics are structured, privacy-aware, and visible in
/// Console.app without leaking recipient data into stdout.
enum Log {
    private static let subsystem = "com.bryansnotes.highrise"

    static let csv = Logger(subsystem: subsystem, category: "CSVImport")
    static let merge = Logger(subsystem: subsystem, category: "Merge")
    static let send = Logger(subsystem: subsystem, category: "Send")
    static let coordinator = Logger(subsystem: subsystem, category: "Coordinator")
}
