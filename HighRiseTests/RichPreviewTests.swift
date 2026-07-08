import Testing
@testable import HighRise

/// The rendered preview must show the same words the recipient will see, so the
/// text content the native Markdown parse produces (markers removed, bullets
/// shown) is pinned. Attribute rendering itself is SwiftUI's job.
struct RichPreviewTests {

    private func text(_ markdown: String) -> String {
        String(RichPreview.attributed(from: markdown).characters)
    }

    @Test("Inline markers are removed from the displayed text")
    func inlineMarkersStripped() {
        #expect(text("**hi**") == "hi")
        #expect(text("*hi*") == "hi")
        #expect(text("a **b** c") == "a b c")
    }

    @Test("Link syntax shows just the label")
    func linkLabel() {
        #expect(text("[Docs](https://x.example)") == "Docs")
    }

    @Test("Plain text passes through unchanged")
    func plainText() {
        #expect(text("Just text") == "Just text")
    }

    @Test("\"- \" lines are turned into real bullets")
    func bullets() {
        #expect(RichPreview.bulletized("- one\n- two") == "• one\n• two")
        // Non-list lines are untouched.
        #expect(RichPreview.bulletized("intro\n- item") == "intro\n• item")
        // A lone dash without a space is not a bullet.
        #expect(RichPreview.bulletized("-nope") == "-nope")
        #expect(text("- one\n- two") == "• one\n• two")
    }

    @Test("Line breaks are preserved")
    func lineBreaks() {
        #expect(text("a\nb") == "a\nb")
    }
}
