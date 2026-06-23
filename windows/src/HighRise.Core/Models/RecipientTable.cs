namespace HighRise.Core.Models;

/// <summary>
/// A source-agnostic tabular recipient list: a header row plus data rows. Every
/// importer (CSV, Excel, …) reduces its input to this shape so one pipeline can
/// serve every source. Port of the Swift <c>RecipientTable</c>.
/// </summary>
public sealed class RecipientTable
{
    /// <summary>Column headers, in order, original casing preserved.</summary>
    public IReadOnlyList<string> Headers { get; }

    /// <summary>Data rows; a row may be shorter than <see cref="Headers"/>.</summary>
    public IReadOnlyList<IReadOnlyList<string>> Rows { get; }

    public RecipientTable(IReadOnlyList<string> headers, IReadOnlyList<IReadOnlyList<string>> rows)
    {
        Headers = headers;
        Rows = rows;
    }
}
