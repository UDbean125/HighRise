import Testing
@testable import HighRise

/// The toolbar splices Markdown into whatever's already typed, so the separator
/// rules (space vs newline, no doubling) are pinned — a wrong separator would
/// glue a bullet onto the previous line or double-space inline marks.
struct MarkdownFormattingTests {

    @Test("Into empty text, the snippet is inserted as-is")
    func empty() {
        #expect(MarkdownFormatting.inserting(.bold, into: "") == "**bold text**")
        #expect(MarkdownFormatting.inserting(.bullet, into: "") == "- list item")
    }

    @Test("Inline styles get one leading space after non-space text")
    func inlineSpacing() {
        #expect(MarkdownFormatting.inserting(.bold, into: "Hi") == "Hi **bold text**")
        #expect(MarkdownFormatting.inserting(.italic, into: "Hi") == "Hi *italic text*")
        #expect(MarkdownFormatting.inserting(.link, into: "See") == "See [link text](https://)")
    }

    @Test("No double space when text already ends in whitespace")
    func noDoubleSpace() {
        #expect(MarkdownFormatting.inserting(.bold, into: "Hi ") == "Hi **bold text**")
        #expect(MarkdownFormatting.inserting(.bold, into: "Hi\n") == "Hi\n**bold text**")
    }

    @Test("A bullet begins on its own line, without doubling an existing newline")
    func bulletOnNewLine() {
        #expect(MarkdownFormatting.inserting(.bullet, into: "Intro") == "Intro\n- list item")
        #expect(MarkdownFormatting.inserting(.bullet, into: "Intro\n") == "Intro\n- list item")
    }

    @Test("Each style exposes its snippet, label, and icon")
    func styleMetadata() {
        #expect(MarkdownFormatting.Style.allCases.count == 4)
        #expect(MarkdownFormatting.Style.bold.snippet == "**bold text**")
        #expect(MarkdownFormatting.Style.bullet.label == "Bullet list")
        #expect(MarkdownFormatting.Style.link.systemImage == "link")
    }

    // MARK: - Selection wrapping (WYSIWYG)

    @Test("Wrapping a selection surrounds it and re-selects the inner text")
    func wrapSelection() {
        let bold = MarkdownFormatting.wrap("Hello", selection: NSRange(location: 0, length: 5), style: .bold)
        #expect(bold.text == "**Hello**")
        #expect(bold.selection == NSRange(location: 2, length: 5))

        let italic = MarkdownFormatting.wrap("Hi there", selection: NSRange(location: 3, length: 5), style: .italic)
        #expect(italic.text == "Hi *there*")
        #expect(italic.selection == NSRange(location: 4, length: 5))
    }

    @Test("Wrapping an empty selection inserts a placeholder and selects it")
    func wrapEmptySelection() {
        let bold = MarkdownFormatting.wrap("", selection: NSRange(location: 0, length: 0), style: .bold)
        #expect(bold.text == "**bold text**")
        #expect(bold.selection == NSRange(location: 2, length: 9))   // "bold text"
    }

    @Test("Link wrapping keeps the label and selects the URL to replace")
    func wrapLink() {
        let withSel = MarkdownFormatting.wrap("See", selection: NSRange(location: 0, length: 3), style: .link)
        #expect(withSel.text == "[See](https://)")
        #expect(withSel.selection == NSRange(location: 6, length: 8))   // "https://"

        let empty = MarkdownFormatting.wrap("", selection: NSRange(location: 0, length: 0), style: .link)
        #expect(empty.text == "[link text](https://)")
        #expect(empty.selection == NSRange(location: 12, length: 8))
    }

    @Test("Bullet prefixes every line the selection covers")
    func wrapBulletLines() {
        let both = MarkdownFormatting.wrap("one\ntwo", selection: NSRange(location: 0, length: 7), style: .bullet)
        #expect(both.text == "- one\n- two")

        // A caret on a single line bullets just that line.
        let single = MarkdownFormatting.wrap("intro", selection: NSRange(location: 3, length: 0), style: .bullet)
        #expect(single.text == "- intro")

        // A trailing newline isn't turned into a stray bullet.
        let trailing = MarkdownFormatting.wrap("one\n", selection: NSRange(location: 0, length: 2), style: .bullet)
        #expect(trailing.text == "- one\n")
    }

    @Test("An out-of-range selection is clamped, not crashed")
    func wrapClampsRange() {
        let r = MarkdownFormatting.wrap("Hi", selection: NSRange(location: 99, length: 99), style: .bold)
        #expect(r.text == "Hi**bold text**")
    }
}
