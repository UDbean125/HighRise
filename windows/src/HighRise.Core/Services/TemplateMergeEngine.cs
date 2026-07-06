using System.Text;
using System.Text.RegularExpressions;
using HighRise.Core.Models;

namespace HighRise.Core.Services;

/// <summary>
/// Substitutes <c>{{Field}}</c> placeholders in a template with a contact's
/// values. Pure and deterministic. Port of the Swift <c>TemplateMergeEngine</c>.
/// </summary>
public static class TemplateMergeEngine
{
    private static readonly Regex PlaceholderRegex =
        new(EmailTemplate.PlaceholderPattern, RegexOptions.Compiled);

    /// <summary>
    /// Merges <paramref name="template"/> against one <paramref name="contact"/>.
    /// Unresolved placeholders (no matching, non-empty field) are removed from the
    /// output — so no raw <c>{{…}}</c> ever reaches a recipient — and reported so
    /// the review step can block the send.
    /// </summary>
    public static MergePreview Merge(EmailTemplate template, Contact contact)
    {
        var unresolved = new List<string>();
        var seenUnresolved = new HashSet<string>();

        // `escaping` is true only for the HTML body, where substituted values
        // must be neutralized so a recipient's data can't inject/break markup.
        // Subjects are always plain text.
        string Substitute(string text, bool escaping) =>
            ReplacePlaceholders(text, fieldName =>
            {
                var value = contact.Value(fieldName);
                if (!string.IsNullOrWhiteSpace(value))
                    return escaping ? HtmlEscape(value!) : value!;

                var key = fieldName.ToLowerInvariant();
                if (seenUnresolved.Add(key))
                    unresolved.Add(fieldName);
                return string.Empty; // never leak a placeholder into outgoing mail
            });

        var subject = Substitute(template.Subject, escaping: false);
        var body = Substitute(template.Body, escaping: template.Format == BodyFormat.Html);

        return new MergePreview(
            contact.Id,
            contact,
            subject,
            body,
            unresolved,
            EmailValidator.IsValid(contact.Email));
    }

    /// <summary>Merges the template against every contact, preserving order.</summary>
    public static IReadOnlyList<MergePreview> MergeAll(EmailTemplate template, IEnumerable<Contact> contacts) =>
        contacts.Select(c => Merge(template, c)).ToList();

    /// <summary>Escapes the five characters significant in HTML text/attributes.</summary>
    public static string HtmlEscape(string value)
    {
        var sb = new StringBuilder(value.Length);
        foreach (var ch in value)
        {
            sb.Append(ch switch
            {
                '&' => "&amp;",
                '<' => "&lt;",
                '>' => "&gt;",
                '"' => "&quot;",
                '\'' => "&#39;",
                _ => ch.ToString()
            });
        }
        return sb.ToString();
    }

    /// <summary>Replaces every <c>{{ … }}</c> with <paramref name="resolver"/>'s output.</summary>
    private static string ReplacePlaceholders(string text, Func<string, string> resolver) =>
        PlaceholderRegex.Replace(text, match => resolver(match.Groups[1].Value.Trim()));
}
