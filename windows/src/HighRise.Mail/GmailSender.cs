using System.Net.Http.Headers;
using System.Net.Http.Json;

namespace HighRise.Mail;

/// <summary>
/// Sends/drafts a message through the Gmail API. Draft -> POST .../drafts with
/// {"message":{"raw":…}}; Send -> POST .../messages/send with {"raw":…}. The raw
/// payload is a base64url MIME message (see <see cref="MimeMessageBuilder"/>).
/// </summary>
public sealed class GmailSender : IEmailSender
{
    private const string DraftsUrl = "https://gmail.googleapis.com/gmail/v1/users/me/drafts";
    private const string SendUrl = "https://gmail.googleapis.com/gmail/v1/users/me/messages/send";

    private readonly HttpClient _http;
    private readonly IAccessTokenProvider _tokens;

    public GmailSender(HttpClient http, IAccessTokenProvider tokens)
    {
        _http = http;
        _tokens = tokens;
    }

    public EmailProvider Provider => EmailProvider.Gmail;

    public async Task SendAsync(ComposedMessage message, SendMode mode, CancellationToken cancellationToken = default)
    {
        var raw = MimeMessageBuilder.BuildRawBase64Url(message);
        var token = await _tokens.GetAccessTokenAsync(Provider, cancellationToken);

        using var request = new HttpRequestMessage(HttpMethod.Post, mode == SendMode.Send ? SendUrl : DraftsUrl)
        {
            Content = mode == SendMode.Send
                ? JsonContent.Create(new { raw })
                : JsonContent.Create(new { message = new { raw } })
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);

        using var response = await _http.SendAsync(request, cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            var body = await response.Content.ReadAsStringAsync(cancellationToken);
            throw new MailSendException($"Gmail API returned {(int)response.StatusCode}: {body}");
        }
    }
}
