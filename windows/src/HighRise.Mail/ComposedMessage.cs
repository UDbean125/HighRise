using HighRise.Core.Models;

namespace HighRise.Mail;

/// <summary>
/// One personalized message ready to hand to a provider. The Windows analog of
/// the Swift <c>ComposedMessage</c>.
/// </summary>
public sealed record ComposedMessage(
    string RecipientEmail,
    string RecipientName,
    string Subject,
    string Body,
    bool IsHtml)
{
    /// <summary>Builds a message from a merged preview produced by HighRise.Core.</summary>
    public static ComposedMessage FromPreview(MergePreview preview, bool isHtml) =>
        new(
            preview.Contact.Email,
            preview.Contact.DisplayName,
            preview.ResolvedSubject,
            preview.ResolvedBody,
            isHtml);
}
