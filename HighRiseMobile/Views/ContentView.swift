import SwiftUI

struct ContentView: View {
    @StateObject private var coordinator = MobileCoordinator()

    var body: some View {
        NavigationStack {
            ImportView()
                .environmentObject(coordinator)
        }
    }
}
