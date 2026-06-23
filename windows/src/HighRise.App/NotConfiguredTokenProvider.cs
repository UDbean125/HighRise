using HighRise.Mail;

namespace HighRise.App;

/// <summary>
/// Placeholder token provider used until interactive OAuth is wired up (MSAL for
/// Microsoft Graph, Google OAuth for Gmail). It keeps the send path compiling and
/// fails with a clear message rather than silently doing nothing.
/// </summary>
public sealed class NotConfiguredTokenProvider : IAccessTokenProvider
{
    public Task<string> GetAccessTokenAsync(EmailProvider provider, CancellationToken cancellationToken = default) =>
        throw new MailSendException(
            $"Sign-in for {provider} isn't configured yet. Add the OAuth client ID to enable sending.");
}
