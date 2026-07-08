import Testing
@testable import HighRise

/// This converter's output becomes outgoing email, so its grammar, escaping, and
/// — critically — its hands-off treatment of `{{merge fields}}` are pinned.
struct MarkdownToHTMLTests {

    @Test("Plain text becomes a paragraph")
    func paragraph() {
        #expect(MarkdownToHTML.html(from: "Hello world") == "<p>Hello world</p>")
        #expect(MarkdownToHTML.html(from: "") == "")
    }

    @Test("Blank lines split paragraphs; single newlines are line breaks")
    func paragraphsAndBreaks() {
        #expect(MarkdownToHTML.html(from: "A\n\nB") == "<p>A</p><p>B</p>")
        #expect(MarkdownToHTML.html(from: "A\nB") == "<p>A<br>B</p>")
    }

    @Test("Bold and italic")
    func emphasis() {
        #expect(MarkdownToHTML.html(from: "**hi**") == "<p><strong>hi</strong></p>")
        #expect(MarkdownToHTML.html(from: "*hi*") == "<p><em>hi</em></p>")
        #expect(MarkdownToHTML.html(from: "a **b** c *d*") == "<p>a <strong>b</strong> c <em>d</em></p>")
    }

    @Test("Links render as anchors")
    func links() {
        #expect(MarkdownToHTML.html(from: "[Acme](https://acme.example)")
                == #"<p><a href="https://acme.example">Acme</a></p>"#)
    }

    @Test("A block of \"- \" lines becomes a bullet list")
    func bulletList() {
        #expect(MarkdownToHTML.html(from: "- one\n- two") == "<ul><li>one</li><li>two</li></ul>")
        // A mixed block is not a list.
        #expect(MarkdownToHTML.html(from: "intro\n- one") == "<p>intro<br>- one</p>")
    }

    @Test("Literal HTML characters are escaped")
    func escaping() {
        #expect(MarkdownToHTML.html(from: "a < b & c > d") == "<p>a &lt; b &amp; c &gt; d</p>")
        // A quote inside a URL is escaped so it can't break the href attribute.
        #expect(MarkdownToHTML.html(from: "[x](a\"b)") == #"<p><a href="a&quot;b">x</a></p>"#)
    }

    @Test("Merge fields pass through untouched, even inside formatting")
    func mergeFieldsPreserved() {
        #expect(MarkdownToHTML.html(from: "Hi {{First Name}}") == "<p>Hi {{First Name}}</p>")
        #expect(MarkdownToHTML.html(from: "Hi **{{First Name}}**")
                == "<p>Hi <strong>{{First Name}}</strong></p>")
        // A fallback with special chars inside a field still isn't escaped here —
        // the merge engine handles the substituted value's escaping.
        #expect(MarkdownToHTML.html(from: "{{Company|A & B}}") == "<p>{{Company|A & B}}</p>")
    }

    @Test("A realistic multi-block template")
    func realistic() {
        let md = "Hi {{First Name}},\n\nThanks for your interest in **{{Product}}**. Highlights:\n\n- Fast setup\n- [Docs](https://x.example)"
        let html = MarkdownToHTML.html(from: md)
        #expect(html == "<p>Hi {{First Name}},</p>"
                + "<p>Thanks for your interest in <strong>{{Product}}</strong>. Highlights:</p>"
                + #"<ul><li>Fast setup</li><li><a href="https://x.example">Docs</a></li></ul>"#)
    }
}
