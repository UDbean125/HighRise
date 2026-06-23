using System.Net;
using HighRise.Mail;
using Xunit;

namespace HighRise.Mail.Tests;

public class GmailSenderTests
{
    private static ComposedMessage Msg() => new("a@b.co", "Name", "Subject", "Body", false);

    [Fact]
    public async Task SendModePostsToMessagesSendWithBearerToken()
    {
        var handler = new CapturingHandler();
        var sender = new GmailSender(new HttpClient(handler), new StubTokenProvider("TKN"));

        await sender.SendAsync(Msg(), SendMode.Send);

        Assert.Equal(HttpMethod.Post, handler.Request!.Method);
        Assert.EndsWith("/users/me/messages/send", handler.Request!.RequestUri!.ToString());
        Assert.Equal("Bearer", handler.Request!.Headers.Authorization!.Scheme);
        Assert.Equal("TKN", handler.Request!.Headers.Authorization!.Parameter);
        Assert.Contains("\"raw\"", handler.Body!);
    }

    [Fact]
    public async Task DraftModePostsToDraftsWithMessageWrapper()
    {
        var handler = new CapturingHandler();
        var sender = new GmailSender(new HttpClient(handler), new StubTokenProvider("TKN"));

        await sender.SendAsync(Msg(), SendMode.Draft);

        Assert.EndsWith("/users/me/drafts", handler.Request!.RequestUri!.ToString());
        Assert.Contains("\"message\"", handler.Body!);
        Assert.Contains("\"raw\"", handler.Body!);
    }

    [Fact]
    public async Task NonSuccessStatusThrowsMailSendException()
    {
        var handler = new CapturingHandler(HttpStatusCode.Unauthorized);
        var sender = new GmailSender(new HttpClient(handler), new StubTokenProvider("TKN"));

        await Assert.ThrowsAsync<MailSendException>(() => sender.SendAsync(Msg(), SendMode.Send));
    }
}
