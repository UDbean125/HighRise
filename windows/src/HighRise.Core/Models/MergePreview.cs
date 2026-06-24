namespace HighRise.Core.Models;

/// <summary>
/// The result of merging the template against one contact: the rendered message
/// plus enough information to warn about problems before sending. Port of the
/// Swift <c>MergePreview</c>.
/// </summary>
public sealed class MergePreview
{
    public Guid Id { get; }
    public Contact Contact { get; }
    public string ResolvedSubject { get; }
    public string ResolvedBody { get; }

    /// <summary>Placeholder names that had no matching, non-empty field for this contact.</summary>
    public IReadOnlyList<string> UnresolvedFields { get; }

    /// <summary>Whether <see cref="Contact"/>.Email is a syntactically valid address.</summary>
    public bool HasValidEmail { get; }

    public MergePreview(Guid id, Contact contact, string resolvedSubject, string resolvedBody,
                        IReadOnlyList<string> unresolvedFields, bool hasValidEmail)
    {
        Id = id;
        Contact = contact;
        ResolvedSubject = resolvedSubject;
        ResolvedBody = resolvedBody;
        UnresolvedFields = unresolvedFields;
        HasValidEmail = hasValidEmail;
    }

    /// <summary>Safe to send only with a valid recipient and no leftover placeholders.</summary>
    public bool IsSendable => HasValidEmail && UnresolvedFields.Count == 0;

    public string? BlockingReason
    {
        get
        {
            if (!HasValidEmail)
                return string.IsNullOrEmpty(Contact.Email)
                    ? "No email address."
                    : $"Invalid email address: {Contact.Email}";
            if (UnresolvedFields.Count > 0)
                return $"Missing data for: {string.Join(", ", UnresolvedFields)}";
            return null;
        }
    }
}
