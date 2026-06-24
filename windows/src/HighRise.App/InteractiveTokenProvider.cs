using Google.Apis.Auth.OAuth2;
using Google.Apis.Util.Store;
using HighRise.Mail;
using Microsoft.Identity.Client;

namespace HighRise.App;

/// <summary>
/// Acquires OAuth access tokens via interactive sign-in: Google's loopback flow
/// for Gmail, MSAL for Microsoft Graph. Credentials/tokens are cached for the
/// session so the user signs in once per provider. Reads client IDs from
/// <see cref="OAuthConfig"/>; if a provider isn't configured it fails with a
/// clear message instead of silently doing nothing.
/// </summary>
public sealed class InteractiveTokenProvider : IAccessTokenProvider
{
    private static readonly string[] GoogleScopes = { "https://www.googleapis.com/auth/gmail.compose" };
    private static readonly string[] GraphScopes = { "Mail.Send", "Mail.ReadWrite" };

    private readonly OAuthConfig _config;
    private UserCredential? _googleCredential;
    private IPublicClientApplication? _msal;

    public InteractiveTokenProvider(OAuthConfig config) => _config = config;

    public Task<string> GetAccessTokenAsync(EmailProvider provider, CancellationToken cancellationToken = default) =>
        provider switch
        {
            EmailProvider.Gmail => GetGoogleTokenAsync(cancellationToken),
            EmailProvider.Outlook => GetMicrosoftTokenAsync(cancellationToken),
            _ => throw new MailSendException($"Unsupported provider: {provider}")
        };

    private async Task<string> GetGoogleTokenAsync(CancellationToken cancellationToken)
    {
        var google = _config.Google;
        if (google is null || string.IsNullOrWhiteSpace(google.ClientId))
            throw new MailSendException("Gmail isn't configured. Add google.clientId / google.clientSecret to oauth.json.");

        _googleCredential ??= await GoogleWebAuthorizationBroker.AuthorizeAsync(
            new ClientSecrets { ClientId = google.ClientId, ClientSecret = google.ClientSecret },
            GoogleScopes,
            "user",
            cancellationToken,
            new FileDataStore("HighRise.Google"));

        return await _googleCredential.GetAccessTokenForRequestAsync(cancellationToken: cancellationToken);
    }

    private async Task<string> GetMicrosoftTokenAsync(CancellationToken cancellationToken)
    {
        var microsoft = _config.Microsoft;
        if (microsoft is null || string.IsNullOrWhiteSpace(microsoft.ClientId))
            throw new MailSendException("Outlook isn't configured. Add microsoft.clientId to oauth.json.");

        _msal ??= PublicClientApplicationBuilder.Create(microsoft.ClientId)
            .WithAuthority(AzureCloudInstance.AzurePublic, "common")
            .WithRedirectUri("http://localhost")
            .Build();

        AuthenticationResult result;
        try
        {
            var accounts = await _msal.GetAccountsAsync();
            result = await _msal.AcquireTokenSilent(GraphScopes, accounts.FirstOrDefault())
                .ExecuteAsync(cancellationToken);
        }
        catch (MsalUiRequiredException)
        {
            result = await _msal.AcquireTokenInteractive(GraphScopes)
                .ExecuteAsync(cancellationToken);
        }

        return result.AccessToken;
    }
}
