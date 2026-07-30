import SwiftUI

struct ContentView: View {
    @StateObject private var coordinator = MobileCoordinator()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            HomeView()
        }
        // iOS kills backgrounded apps without warning, so the working session
        // is written the moment we leave the foreground — .inactive fires
        // before .background and is the last reliable point to save.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { coordinator.saveSession() }
        }
        // The coordinator MUST be injected on the NavigationStack, not on
        // HomeView inside it. Views pushed by a NavigationLink are hosted by
        // the stack, not by the source view, so an injection on HomeView never
        // reaches Import/Template/Review/Send — they trap at launch of that
        // screen with "No ObservableObject of type MobileCoordinator found."
        // (A real crash that shipped in Build 58; keep this modifier here.)
        .environmentObject(coordinator)
    }
}
