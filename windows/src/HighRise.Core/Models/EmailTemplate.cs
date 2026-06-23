using System.Text.RegularExpressions;

namespace HighRise.Core.Models;

/// <summary>How the body is interpreted when composing the message.</summary>
public enum BodyFormat
{
    PlainText,
    Html
}

/// <summary>
/// The draft written once and personalized per recipient. Placeholders use a
/// <c>{{Field}}</c> syntax mapping to contact column headers. Port of the Swift
/// <c>EmailTemplate</c>.
/// </summary>
public sealed class EmailTemplate
{
    /// <summary>Matches <c>{{ FieldName }}</c> — any run of non-brace characters
    /// inside double braces, with optional internal whitespace.</summary>
    public const string PlaceholderPattern = @"\{\{\s*([^{}]+?)\s*\}\}";

    private static readonly Regex PlaceholderRegex = new(PlaceholderPattern, RegexOptions.Compiled);

    public string Subject { get; }
    public string Body { get; }
    public BodyFormat Format { get; }

    public EmailTemplate(string subject = "", string body = "", BodyFormat format = BodyFormat.PlainText)
    {
        Subject = subject;
        Body = body;
        Format = format;
    }

    /// <summary>The distinct placeholder names referenced anywhere in subject or
    /// body, in first-appearance order (case-insensitive de-duplication).</summary>
    public IReadOnlyList<string> ReferencedFields
    {
        get
        {
            var seen = new HashSet<string>();
            var ordered = new List<string>();
            foreach (var name in PlaceholderNames(Subject).Concat(PlaceholderNames(Body)))
            {
                var key = name.ToLowerInvariant();
                if (seen.Add(key))
                    ordered.Add(name);
            }
            return ordered;
        }
    }

    /// <summary>Extracts the trimmed names inside every <c>{{ … }}</c> in <paramref name="text"/>.</summary>
    public static IReadOnlyList<string> PlaceholderNames(string text)
    {
        var names = new List<string>();
        foreach (Match match in PlaceholderRegex.Matches(text))
            names.Add(match.Groups[1].Value.Trim());
        return names;
    }
}
