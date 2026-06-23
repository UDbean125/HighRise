namespace HighRise.Mail;

/// <summary>The email back-end a message is sent through.</summary>
public enum EmailProvider
{
    Gmail,
    Outlook
}

/// <summary>What to do with each composed message.</summary>
public enum SendMode
{
    /// <summary>Create the message in the user's Drafts for review.</summary>
    Draft,
    /// <summary>Send the message immediately from the user's account.</summary>
    Send
}

/// <summary>
/// Supplies a valid OAuth access token for a provider. The interactive sign-in
/// (MSAL for Microsoft, Google OAuth for Gmail) lives in the platform UI layer;
/// the senders only need a bearer token, which keeps this library free of any
/// interactive/desktop dependency and fully unit-testable.
/// </summary>
public interface IAccessTokenProvider
{
    Task<string> GetAccessTokenAsync(EmailProvider provider, CancellationToken cancellationToken = default);
}

/// <summary>Sends or drafts one composed message through a provider.</summary>
public interface IEmailSender
{
    EmailProvider Provider { get; }

    Task SendAsync(ComposedMessage message, SendMode mode, CancellationToken cancellationToken = default);
}

/// <summary>Raised when a provider API rejects a send/draft request.</summary>
public sealed class MailSendException : Exception
{
    public MailSendException(string message) : base(message) { }
}
