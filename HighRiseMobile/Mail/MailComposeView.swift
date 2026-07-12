import SwiftUI
import MessageUI

/// Wraps `MFMailComposeViewController` — the only mail-sending mechanism
/// available on iOS (there is no AppleScript/Apple Events equivalent, and no
/// SMTP client in this app per the Mac app's "no SMTP, no servers" design).
/// Presents one recipient's already-merged message pre-filled; the user
/// reviews and taps Send themselves, which is why sending on iOS is a
/// one-sheet-per-recipient queue (`SendQueue`) rather than the unattended
/// batch send the macOS app does via AppleScript.
struct MailComposeView: UIViewControllerRepresentable {
    let preview: MergePreview
    let isHTML: Bool
    let onFinish: (MFMailComposeResult, Error?) -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([preview.contact.email])
        controller.setSubject(preview.resolvedSubject)
        controller.setMessageBody(preview.resolvedBody, isHTML: isHTML)
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (MFMailComposeResult, Error?) -> Void

        init(onFinish: @escaping (MFMailComposeResult, Error?) -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                    didFinishWith result: MFMailComposeResult, error: Error?) {
            controller.dismiss(animated: true) { [onFinish] in onFinish(result, error) }
        }
    }
}
