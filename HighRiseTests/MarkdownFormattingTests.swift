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
}
