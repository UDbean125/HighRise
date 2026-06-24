using HighRise.Core.Services;
using Xunit;

namespace HighRise.Core.Tests;

public class EmailValidatorTests
{
    [Theory]
    [InlineData("ada@example.com")]
    [InlineData("first.last@sub.domain.co")]
    [InlineData("name+tag@host.io")]
    [InlineData("a@b.cd")]
    public void AcceptsOrdinaryAddresses(string address) =>
        Assert.True(EmailValidator.IsValid(address));

    [Theory]
    [InlineData("")]
    [InlineData("no-at-sign")]
    [InlineData("missing@domain")]
    [InlineData("@example.com")]
    [InlineData("spaces in@x.com")]
    [InlineData("trailing@x.com,")]
    public void RejectsMalformedAddresses(string address) =>
        Assert.False(EmailValidator.IsValid(address));

    [Fact]
    public void TrimsSurroundingWhitespaceBeforeValidating() =>
        Assert.True(EmailValidator.IsValid("  ada@example.com  "));

    [Fact]
    public void NullIsInvalid() =>
        Assert.False(EmailValidator.IsValid(null));
}
