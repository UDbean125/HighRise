using System.Text.RegularExpressions;

namespace HighRise.Core.Services;

/// <summary>
/// Pragmatic email-address validation — deliberately not full RFC 5322. Catches
/// the mistakes that appear in pasted contact lists (missing <c>@</c>, missing
/// domain, spaces, trailing commas) while accepting addresses people really use.
/// Port of the Swift <c>EmailValidator</c>.
/// </summary>
public static class EmailValidator
{
    private static readonly Regex Pattern =
        new(@"^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$",
            RegexOptions.IgnoreCase | RegexOptions.Compiled);

    public static bool IsValid(string? candidate)
    {
        if (string.IsNullOrWhiteSpace(candidate))
            return false;
        return Pattern.IsMatch(candidate.Trim());
    }
}
