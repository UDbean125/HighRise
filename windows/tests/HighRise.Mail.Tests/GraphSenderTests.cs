using System.Net;
using HighRise.Mail;
using Xunit;

namespace HighRise.Mail.Tests;

public class GraphSenderTests
{
    [Fact]
    public async Task SendModePostsToSendMailWithSaveFlag()
    {
        var handler = new CapturingHandler();
        var sender = new GraphSender(new HttpClient(handler), new StubTokenProvider("TKN"));

        await sender.SendAsync(new("a@b.co", "Name", "Subj", "Body", false), SendMode.Send);

        Assert.EndsWith("/me/sendMail", handler.Request!.RequestUri!.ToString());
        Assert.Equal("TKN", handler.Request!.Headers.Authorization!.Parameter);
        Assert.Contains("\"saveToSentItems\":true", handler.Body!);
        Assert.Contains("\"subject\":\"Subj\"", handler.Body!);
        Assert.Contains("\"contentType\":\"Text\"", handler.Body!);
    }

    [Fact]
    public async Task DraftModePostsToMessagesWithHtmlBody()
    {
        var handler = new CapturingHandler();
        var sender = new GraphSender(new HttpClient(handler), new StubTokenProvider("TKN"));

        await sender.SendAsync(new("a@b.co", "Name", "Subj", "<b>Hi</b>", true), SendMode.Draft);

        Assert.EndsWith("/me/messages", handler.Request!.RequestUri!.ToString());
        Assert.Contains("\"contentType\":\"HTML\"", handler.Body!);
        Assert.Contains("\"address\":\"a@b.co\"", handler.Body!);
    }

    [Fact]
    public async Task NonSuccessStatusThrowsMailSendException()
    {
        var handler = new CapturingHandler(HttpStatusCode.Forbidden);
        var sender = new GraphSender(new HttpClient(handler), new StubTokenProvider("TKN"));

        await Assert.ThrowsAsync<MailSendException>(() =>
            sender.SendAsync(new("a@b.co", "Name", "S", "B", false), SendMode.Send));
    }
}
