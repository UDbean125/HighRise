import Foundation

/// Extracts a single named entry from a ZIP container (`.xlsx` and `.docx` are
/// both ZIPs of XML).
///
/// Foundation ships no public ZIP reader and the project forbids third-party
/// dependencies, so we shell out to macOS's built-in `/usr/bin/unzip`. This is
/// reliable and dependency-free, but it means the app must run **unsandboxed**
/// (spawning a subprocess isn't permitted under App Sandbox) — documented in
/// the README alongside the AppleScript automation requirement.
enum ZipEntryReader {

    enum ZipError: LocalizedError {
        case unzipUnavailable
        case entryNotFound(String)
        case readFailed(String)

        var errorDescription: String? {
            switch self {
            case .unzipUnavailable:    return "The system unzip tool is unavailable."
            case .entryNotFound(let e): return "The file doesn't contain \(e) — it may not be a valid Office document."
            case .readFailed(let m):   return m
            }
        }
    }

    /// Returns the raw bytes of `entry` (e.g. `xl/sharedStrings.xml`) inside the
    /// archive at `url`.
    static func entry(_ entry: String, in url: URL) throws -> Data {
        let unzip = URL(fileURLWithPath: "/usr/bin/unzip")
        guard FileManager.default.isExecutableFile(atPath: unzip.path) else {
            throw ZipError.unzipUnavailable
        }

        let process = Process()
        process.executableURL = unzip
        process.arguments = ["-p", url.path, entry] // -p writes the entry to stdout

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        // Drain stdout *before* waiting so a large entry can't deadlock on a
        // full pipe buffer; readDataToEndOfFile returns at EOF (process exit).
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if err.lowercased().contains("caution") || data.isEmpty {
                throw ZipError.entryNotFound(entry)
            }
            throw ZipError.readFailed(err.isEmpty ? "unzip exited with status \(process.terminationStatus)." : err)
        }
        return data
    }
}
