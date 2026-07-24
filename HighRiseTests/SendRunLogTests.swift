import Testing
import Foundation
@testable import HighRise

/// The run journal is the double-send safety net: the only record of who was
/// already emailed that survives the app quitting (window close = quit)
/// mid-run. These pin the store's round-trip, the incomplete-run detection,
/// and the coordinator surfacing/acknowledging the notice.
struct SendRunLogTests {

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SendRunLogTests-\(UUID().uuidString)")
    }

    private var sampleLog: SendRunLog {
        var log = SendRunLog(startedAt: Date(timeIntervalSince1970: 1_700_000_000),
                             mode: "send", total: 3)
        log.records = [
            .init(email: "ada@example.com", name: "Ada", status: "sent",
                  reason: nil, at: Date(timeIntervalSince1970: 1_700_000_001)),
            .init(email: "grace@example.com", name: "Grace, PhD", status: "failed",
                  reason: "Mail said \"no\"", at: Date(timeIntervalSince1970: 1_700_000_002)),
        ]
        return log
    }

    @Test("A journal round-trips losslessly")
    func roundTrip() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SendRunLogStore(directory: directory)
        store.save(sampleLog)
        #expect(SendRunLogStore(directory: directory).load() == sampleLog)
    }

    @Test("Only an unfinished journal counts as incomplete")
    func incompleteDetection() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SendRunLogStore(directory: directory)

        store.save(sampleLog) // finished == false: the app died mid-run
        #expect(store.loadIncomplete() != nil)

        var done = sampleLog
        done.finished = true
        store.save(done)
        #expect(store.loadIncomplete() == nil)
    }

    @Test("deliveredCount counts sent and drafted, not skipped or failed")
    func deliveredCount() {
        var log = sampleLog
        log.records.append(.init(email: "x@y.com", name: "X", status: "drafted",
                                 reason: nil, at: Date(timeIntervalSince1970: 0)))
        log.records.append(.init(email: "z@y.com", name: "Z", status: "skipped",
                                 reason: "held", at: Date(timeIntervalSince1970: 0)))
        #expect(log.deliveredCount == 2) // 1 sent + 1 drafted
    }

    @Test("CSV escapes commas, quotes, and newlines in fields")
    func csvEscaping() {
        let csv = sampleLog.csv()
        let lines = csv.split(separator: "\n")
        #expect(lines[0] == "Email,Name,Status,Reason")
        #expect(lines[1] == "ada@example.com,Ada,sent,")
        #expect(lines[2] == "grace@example.com,\"Grace, PhD\",failed,\"Mail said \"\"no\"\"\"")
    }

    @Test("A nil directory makes the store inert")
    func nilDirectoryIsInert() {
        let store = SendRunLogStore(directory: nil)
        store.save(sampleLog)
        #expect(store.load() == nil)
        #expect(store.loadIncomplete() == nil)
    }
}

/// Coordinator-level surfacing of a died-mid-run journal.
@MainActor
struct HighRiseCoordinatorRunLogTests {

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("CoordinatorRunLogTests-\(UUID().uuidString)")
    }

    private func makeCoordinator(runLogDirectory: URL) -> HighRiseCoordinator {
        HighRiseCoordinator(sessionStore: SessionStore(directory: nil),
                            library: TemplateLibraryStore(directory: nil),
                            runLog: SendRunLogStore(directory: runLogDirectory))
    }

    @Test("An unfinished journal from a previous launch surfaces as a notice")
    func incompleteRunSurfaces() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var died = SendRunLog(startedAt: Date(), mode: "send", total: 10)
        died.records = [.init(email: "ada@example.com", name: "Ada",
                              status: "sent", reason: nil, at: Date())]
        SendRunLogStore(directory: directory).save(died)

        let coordinator = makeCoordinator(runLogDirectory: directory)
        #expect(coordinator.incompleteLastRun?.deliveredCount == 1)
        #expect(coordinator.incompleteRunReportCSV()?.contains("ada@example.com") == true)
    }

    @Test("Dismissing the notice marks the journal finished for good")
    func dismissalSticks() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        SendRunLogStore(directory: directory)
            .save(SendRunLog(startedAt: Date(), mode: "draft", total: 5))

        let first = makeCoordinator(runLogDirectory: directory)
        #expect(first.incompleteLastRun != nil)
        first.dismissIncompleteRunNotice()
        #expect(first.incompleteLastRun == nil)

        let second = makeCoordinator(runLogDirectory: directory)
        #expect(second.incompleteLastRun == nil,
                "an acknowledged notice must not reappear on the next launch")
    }

    @Test("A finished last run produces no notice")
    func finishedRunIsQuiet() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var done = SendRunLog(startedAt: Date(), mode: "send", total: 2)
        done.finished = true
        SendRunLogStore(directory: directory).save(done)

        #expect(makeCoordinator(runLogDirectory: directory).incompleteLastRun == nil)
    }
}
