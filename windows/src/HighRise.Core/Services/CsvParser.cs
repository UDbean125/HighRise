using System.Text;
using HighRise.Core.Models;

namespace HighRise.Core.Services;

/// <summary>
/// A minimal, dependency-free RFC 4180-style CSV reader: quoted fields, commas
/// and newlines inside quotes, and escaped quotes (<c>""</c>). Port of the Swift
/// <c>CSVParser</c>.
/// </summary>
public static class CsvParser
{
    public sealed class ParseException : Exception
    {
        public ParseException(string message) : base(message) { }
    }

    /// <summary>Splits raw CSV text into a header row plus data rows.</summary>
    public static RecipientTable Parse(string text)
    {
        var allRows = ParseRows(text);
        if (allRows.Count == 0)
            throw new ParseException("The file is empty.");

        var headers = allRows[0].Select(h => h.Trim()).ToList();
        if (!headers.Any(h => h.Length > 0))
            throw new ParseException("The file has no header row.");

        // Drop fully-empty trailing rows (common with a trailing newline).
        var dataRows = allRows
            .Skip(1)
            .Where(row => row.Any(f => f.Trim().Length > 0))
            .Select(row => (IReadOnlyList<string>)row)
            .ToList();

        return new RecipientTable(headers, dataRows);
    }

    /// <summary>The state-machine tokenizer. Returns one list of fields per record.</summary>
    public static List<List<string>> ParseRows(string text)
    {
        var rows = new List<List<string>>();
        var field = new StringBuilder();
        var record = new List<string>();
        var inQuotes = false;
        var n = text.Length;
        var i = 0;

        while (i < n)
        {
            var c = text[i];
            if (inQuotes)
            {
                if (c == '"')
                {
                    // Doubled quote inside a quoted field -> literal quote.
                    if (i + 1 < n && text[i + 1] == '"')
                    {
                        field.Append('"');
                        i++;
                    }
                    else
                    {
                        inQuotes = false;
                    }
                }
                else
                {
                    field.Append(c);
                }
            }
            else
            {
                switch (c)
                {
                    case '"':
                        inQuotes = true;
                        break;
                    case ',':
                        record.Add(field.ToString());
                        field.Clear();
                        break;
                    case '\r':
                        // Swallow CR; a following LF is handled as the record break.
                        if (i + 1 < n && text[i + 1] == '\n')
                            i++;
                        record.Add(field.ToString());
                        field.Clear();
                        rows.Add(record);
                        record = new List<string>();
                        break;
                    case '\n':
                        record.Add(field.ToString());
                        field.Clear();
                        rows.Add(record);
                        record = new List<string>();
                        break;
                    default:
                        field.Append(c);
                        break;
                }
            }
            i++;
        }

        // Flush the final record if the file didn't end on a newline.
        if (field.Length > 0 || record.Count > 0)
        {
            record.Add(field.ToString());
            rows.Add(record);
        }

        return rows;
    }

    /// <summary>
    /// Maps a parsed table onto <see cref="Contact"/> values. When
    /// <paramref name="emailHeader"/> is null, the email column is guessed via
    /// <see cref="DetectEmailColumn"/>. Returns the contacts plus the header
    /// actually used for email.
    /// </summary>
    public static (List<Contact> Contacts, string? EmailHeader) Contacts(
        RecipientTable table, string? emailHeader = null)
    {
        var chosen = emailHeader ?? DetectEmailColumn(table);
        if (chosen is null)
            return (new List<Contact>(), chosen);

        var emailIndex = -1;
        for (var idx = 0; idx < table.Headers.Count; idx++)
        {
            if (string.Equals(table.Headers[idx], chosen, StringComparison.OrdinalIgnoreCase))
            {
                emailIndex = idx;
                break;
            }
        }
        if (emailIndex < 0)
            return (new List<Contact>(), chosen);

        var contacts = new List<Contact>();
        foreach (var row in table.Rows)
        {
            var fields = new Dictionary<string, string>();
            for (var idx = 0; idx < table.Headers.Count; idx++)
            {
                var header = table.Headers[idx];
                if (header.Length == 0)
                    continue;
                var value = idx < row.Count ? row[idx] : string.Empty;
                fields[header] = value.Trim();
            }

            var email = (emailIndex < row.Count ? row[emailIndex] : string.Empty).Trim();
            if (email.Length == 0)
                continue;

            contacts.Add(new Contact(fields, email));
        }

        return (contacts, chosen);
    }

    /// <summary>Picks the most likely email column: a header mentioning "email",
    /// else the column whose values most often look like addresses.</summary>
    public static string? DetectEmailColumn(RecipientTable table)
    {
        var named = table.Headers.FirstOrDefault(h =>
        {
            var lower = h.ToLowerInvariant();
            return lower.Contains("email") || lower.Contains("e-mail") || lower == "mail";
        });
        if (named is not null)
            return named;

        string? bestHeader = null;
        var bestScore = 0;
        for (var idx = 0; idx < table.Headers.Count; idx++)
        {
            var header = table.Headers[idx];
            if (header.Length == 0)
                continue;

            var score = 0;
            foreach (var row in table.Rows)
            {
                if (idx < row.Count && EmailValidator.IsValid(row[idx]))
                    score++;
            }
            if (score > bestScore)
            {
                bestScore = score;
                bestHeader = header;
            }
        }
        return bestHeader;
    }
}
