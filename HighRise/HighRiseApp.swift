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
// instead of leaving a windowless app stuck in the Dock.
final class HighRiseAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
