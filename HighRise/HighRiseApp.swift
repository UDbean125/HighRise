import SwiftUI

@main
struct HighRiseApp: App {
    @StateObject private var coordinator = HighRiseCoordinator()

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
        }
    }
}
