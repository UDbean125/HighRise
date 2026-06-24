namespace HighRise.Core.Models;

/// <summary>
/// A single recipient parsed from an imported list: an open bag of named fields
/// (whatever column headers the source had) plus a designated email address.
/// Port of the Swift <c>Contact</c>.
/// </summary>
public sealed class Contact
{
    private static readonly string[] PreferredNameKeys =
    {
        "name", "full name", "fullname", "contact",
        "contact name", "first name", "firstname", "company"
    };

    public Guid Id { get; } = Guid.NewGuid();

    /// <summary>Field values keyed by their original-cased column header.
    /// Lookups via <see cref="Value"/> are case-insensitive.</summary>
    public IReadOnlyDictionary<string, string> Fields { get; }

    /// <summary>The recipient's email address (also present in <see cref="Fields"/>).</summary>
    public string Email { get; }

    public Contact(IDictionary<string, string> fields, string email)
    {
        Fields = new Dictionary<string, string>(fields);
        Email = email;
    }

    /// <summary>Case-insensitive, whitespace-tolerant field lookup.
    /// <c>{{ company }}</c>, <c>{{Company}}</c>, and <c>{{COMPANY}}</c> all resolve the same.</summary>
    public string? Value(string key)
    {
        var wanted = key.Trim().ToLowerInvariant();
        foreach (var kv in Fields)
        {
            if (kv.Key.ToLowerInvariant() == wanted)
                return kv.Value;
        }
        return null;
    }

    /// <summary>A human label, preferring a name-like column, falling back to the email.</summary>
    public string DisplayName
    {
        get
        {
            foreach (var key in PreferredNameKeys)
            {
                var v = Value(key);
                if (!string.IsNullOrWhiteSpace(v))
                    return v!;
            }
            return Email;
        }
    }
}
