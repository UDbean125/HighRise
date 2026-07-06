using HighRise.Core.Models;
using HighRise.Core.Services;
using Xunit;

namespace HighRise.Core.Tests;

public class TemplateMergeEngineTests
{
    private static Contact MakeContact(string email, params (string Key, string Value)[] fields)
    {
        var dict = new Dictionary<string, string>();
        foreach (var (key, value) in fields)
            dict[key] = value;
        return new Contact(dict, email);
    }

    [Fact]
    public void SubstitutesFieldsInSubjectAndBody()
    {
        var template = new EmailTemplate("Hi {{Name}}", "Welcome to {{Company}}, {{Name}}!");
        var contact = MakeContact("a@b.co", ("Name", "Sam"), ("Company", "Acme"));

        var preview = TemplateMergeEngine.Merge(template, contact);

        Assert.Equal("Hi Sam", preview.ResolvedSubject);
        Assert.Equal("Welcome to Acme, Sam!", preview.ResolvedBody);
        Assert.True(preview.IsSendable);
    }

    [Fact]
    public void PlaceholderMatchingIsCaseAndWhitespaceInsensitive()
    {
        var template = new EmailTemplate("x", "Hi {{ name }} / {{NAME}}");
        var contact = MakeContact("a@b.co", ("Name", "Sam"));

        var preview = TemplateMergeEngine.Merge(template, contact);

        Assert.Equal("Hi Sam / Sam", preview.ResolvedBody);
        Assert.Empty(preview.UnresolvedFields);
    }

    [Fact]
    public void MissingFieldsAreReportedAndNeverLeakedAsRawBraces()
    {
        var template = new EmailTemplate("Hi {{Name}}", "About {{Company}}");
        var contact = MakeContact("a@b.co", ("Name", "Sam"));

        var preview = TemplateMergeEngine.Merge(template, contact);

        Assert.DoesNotContain("{{", preview.ResolvedBody);
        Assert.Equal("About ", preview.ResolvedBody);
        Assert.Contains("Company", preview.UnresolvedFields);
        Assert.False(preview.IsSendable);
        Assert.Equal("Missing data for: Company", preview.BlockingReason);
    }

    [Fact]
    public void AnEmptyFieldCountsAsUnresolved()
    {
        var template = new EmailTemplate("x", "Hi {{Name}}");
        var contact = MakeContact("a@b.co", ("Name", "   "));

        var preview = TemplateMergeEngine.Merge(template, contact);

        Assert.Contains("Name", preview.UnresolvedFields);
    }

    [Fact]
    public void InvalidEmailMakesThePreviewNonSendable()
    {
        var template = new EmailTemplate("x", "y");
        var contact = MakeContact("not-an-email");

        var preview = TemplateMergeEngine.Merge(template, contact);

        Assert.False(preview.HasValidEmail);
        Assert.False(preview.IsSendable);
        Assert.Equal("Invalid email address: not-an-email", preview.BlockingReason);
    }

    [Fact]
    public void HtmlBodyEscapesSubstitutedFieldValues()
    {
        var template = new EmailTemplate("x", "Hi {{Name}}", BodyFormat.Html);
        var contact = MakeContact("a@b.co", ("Name", "<b>&'\""));

        var preview = TemplateMergeEngine.Merge(template, contact);

        Assert.Equal("Hi &lt;b&gt;&amp;&#39;&quot;", preview.ResolvedBody);
    }

    [Fact]
    public void PlainTextBodyDoesNotEscapeValues()
    {
        var template = new EmailTemplate("x", "Hi {{Name}}", BodyFormat.PlainText);
        var contact = MakeContact("a@b.co", ("Name", "Tom & Jerry's <Toys>"));

        var preview = TemplateMergeEngine.Merge(template, contact);

        Assert.Equal("Hi Tom & Jerry's <Toys>", preview.ResolvedBody);
    }

    [Fact]
    public void ReferencedFieldsListsDistinctPlaceholdersInOrder()
    {
        var template = new EmailTemplate("{{Company}} for {{Name}}", "{{Name}}, {{company}}");

        Assert.Equal(new[] { "Company", "Name" }, template.ReferencedFields);
    }
}
