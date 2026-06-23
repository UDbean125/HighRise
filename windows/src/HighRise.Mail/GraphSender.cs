using System.Net.Http.Headers;
using System.Net.Http.Json;

namespace HighRise.Mail;

/// <summary>
/// Sends/drafts a message through Microsoft Graph. Draft -> POST /me/messages
/// with the message object; Send -> POST /me/sendMail with {message, saveToSentItems}.
/// Graph takes a structured JSON message (no raw MIME), so it does its own
/// encoding — there's no header-injection surface here.
/// </summary>
public sealed class GraphSender : IEmailSender
{
    private const string MessagesUrl = "https://graph.microsoft.com/v1.0/me/messages";
    private const string SendMailUrl = "https://graph.microsoft.com/v1.0/me/sendMail";

    private readonly HttpClient _http;
    private readonly IAccessTokenProvider _tokens;

    public GraphSender(HttpClient http, IAccessTokenProvider tokens)
    {
        _http = http;
        _tokens = tokens;
    }

    public EmailProvider Provider => EmailProvider.Outlook;

    public async Task SendAsync(ComposedMessage message, SendMode mode, CancellationToken cancellationToken = default)
    {
        var token = await _tokens.GetAccessTokenAsync(Provider, cancellationToken);

        var graphMessage = new
        {
            subject = message.Subject,
            body = new
            {
                contentType = message.IsHtml ? "HTML" : "Text",
                content = message.Body
            },
            toRecipients = new[]
            {
                new { emailAddress = new { address = message.RecipientEmail } }
            }
        };

        using var request = new HttpRequestMessage(HttpMethod.Post, mode == SendMode.Send ? SendMailUrl : MessagesUrl)
        {
            Content = mode == SendMode.Send
                ? JsonContent.Create(new { message = graphMessage, saveToSentItems = true })
                : JsonContent.Create(graphMessage)
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);

        using var response = await _http.SendAsync(request, cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            var body = await response.Content.ReadAsStringAsync(cancellationToken);
            throw new MailSendException($"Microsoft Graph returned {(int)response.StatusCode}: {body}");
        }
    }
}
