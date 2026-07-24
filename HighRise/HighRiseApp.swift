import SwiftUI

@main
struct HighRiseApp: App {
    @StateObject private var coordinator = HighRiseCoordinator()
    @NSApplicationDelegateAdaptor(HighRiseAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coordinator)
                .frame(minWidth: 820, minHeight: 600)
                .onAppear { appDelegate.coordinator = coordinator }
        }
        .windowResizability(.contentSize)
        .commands {
            // Replace the default New-document item; HighRise is single-window.
            CommandGroup(replacing: .newItem) { }
            // A working Help menu: replay the first-run welcome tour any time.
            CommandGroup(replacing: .help) {
                Button("HighRise Welcome Tour") {
                    coordinator.isShowingWelcome = true
                }
            }
        }
    }
}

// HighRise has no menu item to reopen the main window once closed, so quit
// instead of leaving a windowless app stuck in the Dock. But quitting also
// kills promised work — an armed scheduled send or an in-flight run — so
// those get an explicit confirmation instead of vanishing silently.
@MainActor
final class HighRiseAppDelegate: NSObject, NSApplicationDelegate {

    /// Wired by `HighRiseApp` via `onAppear` so the quit guard can see the
    /// live send/schedule state.
    weak var coordinator: HighRiseCoordinator?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Runs for every quit path (window close above, Cmd-Q, logout). If a
    /// choice to "Keep Running" leaves the app windowless, clicking its Dock
    /// icon reopens the window — a state the user chose via this dialog, not
    /// the silent dead-end App Review flagged.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let coordinator else { return .terminateNow }

        if coordinator.isSending {
            let done = coordinator.outcomes.count
            return confirmQuit(
                message: "HighRise is still sending.",
                informative: "\(done) message\(done == 1 ? "" : "s") delivered so far — recipients not yet reached won't get the email if you quit. Progress is saved, so a later run can pick up who's left.",
                quitTitle: "Stop and Quit")
        }

        if let fireDate = coordinator.scheduledFireDate {
            let when = fireDate.formatted(date: .abbreviated, time: .shortened)
            let count = coordinator.scheduledCount
            return confirmQuit(
                message: "A send is scheduled for \(when).",
                informative: "\(count) recipient\(count == 1 ? " is" : "s are") queued. HighRise can only send while it's open — if you quit, the schedule pauses and resumes the next time you open HighRise (or shows a notice if the time has passed).",
                quitTitle: "Quit Anyway")
        }

        return .terminateNow
    }

    private func confirmQuit(message: String, informative: String,
                             quitTitle: String) -> NSApplication.TerminateReply {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = informative
        alert.alertStyle = .warning
        alert.addButton(withTitle: quitTitle)
        alert.addButton(withTitle: "Keep Running")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }
}
