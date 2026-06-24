using HighRise.Mail;
using Xunit;

namespace HighRise.Mail.Tests;

public class MimeMessageBuilderTests
{
    private static ComposedMessage Msg(
        string to = "a@b.co", string subject = "Hi", string body = "Body", bool html = false) =>
        new(to, "Name", subject, body, html);

    [Fact]
    public void AsciiSubjectIsLeftAsIs()
    {
        var mime = MimeMessageBuilder.BuildMime(Msg(subject: "Quick question"));
        Assert.Contains("Subject: Quick question\r\n", mime);
    }

    [Fact]
    public void NonAsciiSubjectIsRfc2047Encoded()
    {
        var mime = MimeMessageBuilder.BuildMime(Msg(subject: "Café ☕"));
        Assert.Contains("Subject: =?utf-8?B?", mime);
    }

    [Fact]
    public void StripsCrlfSoNoHeaderCanBeInjected()
    {
        var mime = MimeMessageBuilder.BuildMime(
            Msg(to: "a@b.co\r\nBcc: evil@x.com", subject: "Hi\r\nX-Evil: 1"));

        // The malicious text survives only as inert characters on the existing
        // header line — never as a new injected header line.
        Assert.DoesNotContain("\nBcc:", mime);
        Assert.DoesNotContain("\nX-Evil:", mime);
        Assert.Contains("To: a@b.coBcc: evil@x.com\r\n", mime);
    }

    [Fact]
    public void HtmlBodyUsesHtmlContentType()
    {
        var mime = MimeMessageBuilder.BuildMime(Msg(html: true));
        Assert.Contains("Content-Type: text/html", mime);
    }

    [Fact]
    public void PlainBodyUsesPlainContentType()
    {
        var mime = MimeMessageBuilder.BuildMime(Msg(html: false));
        Assert.Contains("Content-Type: text/plain", mime);
    }

    [Fact]
    public void RawIsBase64UrlWithNoUnsafeCharacters()
    {
        var raw = MimeMessageBuilder.BuildRawBase64Url(Msg(body: "Plenty of content >>> ???"));
        Assert.DoesNotContain("+", raw);
        Assert.DoesNotContain("/", raw);
        Assert.DoesNotContain("=", raw);
        Assert.DoesNotContain("\r", raw);
        Assert.DoesNotContain("\n", raw);
    }
}
