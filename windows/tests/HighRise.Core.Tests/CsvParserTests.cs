using HighRise.Core.Services;
using Xunit;

namespace HighRise.Core.Tests;

public class CsvParserTests
{
    [Fact]
    public void ParsesHeadersAndRows()
    {
        var table = CsvParser.Parse("Name,Email\nSam,sam@acme.com\n");

        Assert.Equal(new[] { "Name", "Email" }, table.Headers);
        Assert.Single(table.Rows);
        Assert.Equal("sam@acme.com", table.Rows[0][1]);
    }

    [Fact]
    public void HandlesQuotedCommasAndDoubledQuotes()
    {
        var rows = CsvParser.ParseRows("\"Acme, Inc.\",\"Bob \"\"X\"\" Jones\"\n");

        Assert.Equal("Acme, Inc.", rows[0][0]);
        Assert.Equal("Bob \"X\" Jones", rows[0][1]);
    }

    [Fact]
    public void HandlesCrlfLineEndings()
    {
        var rows = CsvParser.ParseRows("a,b\r\nc,d\r\n");

        Assert.Equal(2, rows.Count);
        Assert.Equal(new[] { "a", "b" }, rows[0]);
        Assert.Equal(new[] { "c", "d" }, rows[1]);
    }

    [Fact]
    public void DetectsNamedEmailColumn()
    {
        var table = CsvParser.Parse("Name,E-Mail\nSam,sam@acme.com\n");

        Assert.Equal("E-Mail", CsvParser.DetectEmailColumn(table));
    }

    [Fact]
    public void DetectsEmailColumnByContentWhenUnnamed()
    {
        var table = CsvParser.Parse("Name,Addr\nSam,sam@acme.com\nLee,lee@x.io\n");

        Assert.Equal("Addr", CsvParser.DetectEmailColumn(table));
    }

    [Fact]
    public void BuildsContactsAndSkipsRowsWithoutEmail()
    {
        var table = CsvParser.Parse("Name,Email\nSam,sam@acme.com\nNoEmail,\n");

        var (contacts, header) = CsvParser.Contacts(table);

        Assert.Equal("Email", header);
        Assert.Single(contacts);
        Assert.Equal("Sam", contacts[0].DisplayName);
        Assert.Equal("sam@acme.com", contacts[0].Email);
    }

    [Fact]
    public void TrimsFieldValuesAndResolvesViaContact()
    {
        var table = CsvParser.Parse("Name,Email\n  Sam  ,  sam@acme.com  \n");

        var (contacts, _) = CsvParser.Contacts(table);

        Assert.Single(contacts);
        Assert.Equal("Sam", contacts[0].Value("name"));
        Assert.Equal("sam@acme.com", contacts[0].Email);
    }

    [Fact]
    public void EmptyInputThrows()
    {
        Assert.Throws<CsvParser.ParseException>(() => CsvParser.Parse(""));
    }
}
