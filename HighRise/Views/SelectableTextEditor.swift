import SwiftUI
import AppKit

/// A plain-text editor backed by `NSTextView`, used for the Rich (Markdown) body
/// so the formatting toolbar can wrap the *current selection* — something
/// SwiftUI's `TextEditor` doesn't expose on the app's minimum macOS. Only the
/// Rich body uses this; every other format keeps the standard `TextEditor`, so
/// a bug here can't affect ordinary editing.
///
/// The SwiftUI toolbar holds a `RichTextController` and calls `apply(_:)`; the
/// editor registers its text view with that controller on creation.
@MainActor
final class RichTextController: ObservableObject {
    fileprivate weak var coordinator: SelectableTextEditor.Coordinator?

    /// Wrap the current selection in `style`'s Markdown (pure logic in
    /// `MarkdownFormatting.wrap`), then restore the computed selection.
    func apply(_ style: MarkdownFormatting.Style) {
        coordinator?.apply(style)
    }
}

struct SelectableTextEditor: NSViewRepresentable {
    @Binding var text: String
    let controller: RichTextController

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(self)
        controller.coordinator = coordinator   // controller holds this weakly
        return coordinator
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textContainerInset = NSSize(width: 5, height: 8)
        textView.string = text
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Only overwrite when the binding genuinely diverged (e.g. a template was
        // loaded), so typing doesn't reset the caret.
        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SelectableTextEditor
        weak var textView: NSTextView?

        init(_ parent: SelectableTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func apply(_ style: MarkdownFormatting.Style) {
            guard let textView else { return }
            let result = MarkdownFormatting.wrap(textView.string,
                                                 selection: textView.selectedRange(),
                                                 style: style)
            textView.string = result.text
            textView.setSelectedRange(result.selection)
            parent.text = result.text                 // programmatic edits don't fire the delegate
            textView.window?.makeFirstResponder(textView)
        }
    }
}
