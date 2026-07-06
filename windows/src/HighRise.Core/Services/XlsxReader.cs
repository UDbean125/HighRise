using System.IO.Compression;
using System.Xml.Linq;
using HighRise.Core.Models;

namespace HighRise.Core.Services;

/// <summary>
/// Reads the first worksheet of an <c>.xlsx</c> file into a <see cref="RecipientTable"/>,
/// using only in-box APIs (an .xlsx is a ZIP of XML parts). Port of the Swift
/// <c>XLSXReader</c>. Handles shared strings, inline strings, and gapped rows.
/// First worksheet only — matching the macOS app's documented limitation.
/// </summary>
public static class XlsxReader
{
    private static readonly XNamespace Main =
        "http://schemas.openxmlformats.org/spreadsheetml/2006/main";

    public static RecipientTable Read(string path)
    {
        using var stream = File.OpenRead(path);
        return Read(stream);
    }

    public static RecipientTable Read(Stream xlsxStream)
    {
        using var zip = new ZipArchive(xlsxStream, ZipArchiveMode.Read, leaveOpen: true);

        var shared = ReadSharedStrings(zip);

        var sheet = zip.Entries
            .Where(e => e.FullName.StartsWith("xl/worksheets/", StringComparison.OrdinalIgnoreCase)
                        && e.FullName.EndsWith(".xml", StringComparison.OrdinalIgnoreCase))
            .OrderBy(e => e.FullName, StringComparer.OrdinalIgnoreCase)
            .FirstOrDefault()
            ?? throw new InvalidDataException("No worksheet was found in the .xlsx file.");

        XDocument doc;
        using (var s = sheet.Open())
            doc = XDocument.Load(s);

        // Parse each row into a column-index -> value map, tracking the widest row.
        var parsedRows = new List<Dictionary<int, string>>();
        var maxColumn = -1;

        foreach (var rowEl in doc.Descendants(Main + "row"))
        {
            var cells = new Dictionary<int, string>();
            foreach (var cellEl in rowEl.Elements(Main + "c"))
            {
                var reference = (string?)cellEl.Attribute("r") ?? string.Empty;
                var column = ColumnIndex(reference);
                if (column < 0)
                    continue;

                var value = CellValue(cellEl, shared);
                cells[column] = value;
                if (column > maxColumn)
                    maxColumn = column;
            }
            parsedRows.Add(cells);
        }

        if (maxColumn < 0)
            return new RecipientTable(new List<string>(), new List<IReadOnlyList<string>>());

        // Expand each sparse row to a dense 0..maxColumn array.
        var dense = parsedRows
            .Select(cells =>
            {
                var row = new string[maxColumn + 1];
                for (var i = 0; i <= maxColumn; i++)
                    row[i] = cells.TryGetValue(i, out var v) ? v : string.Empty;
                return row;
            })
            .ToList();

        var headers = dense.Count > 0
            ? dense[0].Select(h => h.Trim()).ToList()
            : new List<string>();

        var dataRows = dense
            .Skip(1)
            .Where(row => row.Any(f => f.Trim().Length > 0))
            .Select(row => (IReadOnlyList<string>)row)
            .ToList();

        return new RecipientTable(headers, dataRows);
    }

    /// <summary>Maps the column letters of a cell reference (e.g. "AB10") to a
    /// zero-based index. Returns -1 if no letters are present.</summary>
    internal static int ColumnIndex(string cellReference)
    {
        var index = 0;
        var sawLetter = false;
        foreach (var c in cellReference)
        {
            if (c >= 'A' && c <= 'Z')
            {
                index = index * 26 + (c - 'A' + 1);
                sawLetter = true;
            }
            else if (c >= 'a' && c <= 'z')
            {
                index = index * 26 + (c - 'a' + 1);
                sawLetter = true;
            }
            else
            {
                break; // reached the row digits
            }
        }
        return sawLetter ? index - 1 : -1;
    }

    private static List<string> ReadSharedStrings(ZipArchive zip)
    {
        var result = new List<string>();
        var entry = zip.GetEntry("xl/sharedStrings.xml");
        if (entry is null)
            return result;

        XDocument doc;
        using (var s = entry.Open())
            doc = XDocument.Load(s);

        foreach (var si in doc.Descendants(Main + "si"))
        {
            // <si> may hold a single <t> or rich-text <r><t> runs; concatenate them.
            var text = string.Concat(si.Descendants(Main + "t").Select(t => t.Value));
            result.Add(text);
        }
        return result;
    }

    private static string CellValue(XElement cell, List<string> shared)
    {
        var type = (string?)cell.Attribute("t");

        if (type == "inlineStr")
            return string.Concat(cell.Descendants(Main + "t").Select(t => t.Value));

        var v = cell.Element(Main + "v");
        if (v is null)
            return string.Empty;

        if (type == "s")
        {
            return int.TryParse(v.Value, out var idx) && idx >= 0 && idx < shared.Count
                ? shared[idx]
                : string.Empty;
        }

        return v.Value;
    }
}
