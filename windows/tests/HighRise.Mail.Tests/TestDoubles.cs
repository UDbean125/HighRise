using System.Net;
using HighRise.Mail;

namespace HighRise.Mail.Tests;

/// <summary>Captures the outgoing request and returns a canned status.</summary>
internal sealed class CapturingHandler : HttpMessageHandler
{
    private readonly HttpStatusCode _status;

    public CapturingHandler(HttpStatusCode status = HttpStatusCode.OK) => _status = status;

    public HttpRequestMessage? Request { get; private set; }
    public string? Body { get; private set; }

    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request, CancellationToken cancellationToken)
    {
        Request = request;
        if (request.Content is not null)
            Body = await request.Content.ReadAsStringAsync(cancellationToken);
        return new HttpResponseMessage(_status) { Content = new StringContent("{}") };
    }
}

/// <summary>Returns a fixed access token without any interactive sign-in.</summary>
internal sealed class StubTokenProvider : IAccessTokenProvider
{
    private readonly string _token;

    public StubTokenProvider(string token) => _token = token;

    public Task<string> GetAccessTokenAsync(EmailProvider provider, CancellationToken cancellationToken = default) =>
        Task.FromResult(_token);
}
