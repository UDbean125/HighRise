import SwiftUI

/// iOS companion to the macOS HighRise app.
///
/// Mac HighRise drives Apple Mail/Outlook unattended via AppleScript — iOS has
/// no equivalent automation API, so this app can't batch-send. It reuses the
/// same import/merge core (see the `HighRise/Models` and `HighRise/Services`
/// files listed under this target in `project.yml`) but hands each recipient
/// to `MFMailComposeViewController` one at a time for the user to review and
/// send themselves (`HighRiseMobile/Mail/MailComposeView.swift`).
@main
struct HighRiseMobileApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
