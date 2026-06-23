using System.IO.Compression;
using System.Text;
using HighRise.Core.Services;
using Xunit;

namespace HighRise.Core.Tests;

public class XlsxReaderTests
{
    [Theory]
    [InlineData("A1", 0)]
    [InlineData("B2", 1)]
    [InlineData("Z9", 25)]
    [InlineData("AA1", 26)]
    [InlineData("AB10", 27)]
    public void ColumnLettersMapToZeroBasedIndices(string reference, int expected) =>
        Assert.Equal(expected, XlsxReader.ColumnIndex(reference));

    [Fact]
    public void ReadsHeadersAndRowsViaSharedStrings()
    {
        var xlsx = BuildXlsx(
            shared: new[] { "Name", "Email", "Sam", "sam@acme.com" },
            rows: new[]
            {
                new[] { ("A1", "s", "0"), ("B1", "s", "1") },
                new[] { ("A2", "s", "2"), ("B2", "s", "3") },
            });

        var table = XlsxReader.Read(new MemoryStream(xlsx));

        Assert.Equal(new[] { "Name", "Email" }, table.Headers);
        Assert.Single(table.Rows);
        Assert.Equal("Sam", table.Rows[0][0]);
        Assert.Equal("sam@acme.com", table.Rows[0][1]);
    }

    [Fact]
    public void HandlesInlineStringsAndColumnGaps()
    {
        var xlsx = BuildXlsx(
            shared: Array.Empty<string>(),
            rows: new[]
            {
                new[] { ("A1", "inlineStr", "Name"), ("C1", "inlineStr", "City") },
                new[] { ("A2", "inlineStr", "Sam"), ("C2", "inlineStr", "NYC") },
            });

        var table = XlsxReader.Read(new MemoryStream(xlsx));

        Assert.Equal(3, table.Headers.Count);              // A, B (gap), C
        Assert.Equal("Name", table.Headers[0]);
        Assert.Equal("", table.Headers[1]);
        Assert.Equal("City", table.Headers[2]);
        Assert.Equal(new[] { "Sam", "", "NYC" }, table.Rows[0]);
    }

    // --- helpers: build a minimal .xlsx (ZIP of XML parts) in memory ---

    private static byte[] BuildXlsx(string[] shared, (string Ref, string T, string V)[][] rows)
    {
        using var ms = new MemoryStream();
        using (var zip = new ZipArchive(ms, ZipArchiveMode.Create, leaveOpen: true))
        {
            if (shared.Length > 0)
            {
                var sb = new StringBuilder();
                sb.Append("<?xml version=\"1.0\"?><sst xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">");
                foreach (var s in shared)
                    sb.Append($"<si><t>{Escape(s)}</t></si>");
                sb.Append("</sst>");
                WriteEntry(zip, "xl/sharedStrings.xml", sb.ToString());
            }

            var sheet = new StringBuilder();
            sheet.Append("<?xml version=\"1.0\"?><worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData>");
            var rowNumber = 1;
            foreach (var row in rows)
            {
                sheet.Append($"<row r=\"{rowNumber}\">");
                foreach (var (reference, type, value) in row)
                {
                    if (type == "inlineStr")
                        sheet.Append($"<c r=\"{reference}\" t=\"inlineStr\"><is><t>{Escape(value)}</t></is></c>");
                    else if (type == "s")
                        sheet.Append($"<c r=\"{reference}\" t=\"s\"><v>{Escape(value)}</v></c>");
                    else
                        sheet.Append($"<c r=\"{reference}\"><v>{Escape(value)}</v></c>");
                }
                sheet.Append("</row>");
                rowNumber++;
            }
            sheet.Append("</sheetData></worksheet>");
            WriteEntry(zip, "xl/worksheets/sheet1.xml", sheet.ToString());
        }
        return ms.ToArray();
    }

    private static void WriteEntry(ZipArchive zip, string name, string content)
    {
        var entry = zip.CreateEntry(name);
        using var writer = new StreamWriter(entry.Open(), new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
        writer.Write(content);
    }

    private static string Escape(string s) =>
        s.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;");
}
