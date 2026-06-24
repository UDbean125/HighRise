using System.Text.Json;

namespace HighRise.App;

/// <summary>
/// OAuth client configuration, loaded from a local file that is never committed
/// (the repo is public). Place it at %LOCALAPPDATA%\HighRise\oauth.json — see
/// oauth.example.json for the shape.
/// </summary>
public sealed class OAuthConfig
{
    public GoogleSettings? Google { get; set; }
    public MicrosoftSettings? Microsoft { get; set; }

    public sealed class GoogleSettings
    {
        public string ClientId { get; set; } = string.Empty;
        public string ClientSecret { get; set; } = string.Empty;
    }

    public sealed class MicrosoftSettings
    {
        public string ClientId { get; set; } = string.Empty;
    }

    /// <summary>%LOCALAPPDATA%\HighRise\oauth.json — outside the repo, never committed.</summary>
    public static string DefaultPath =>
        Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "HighRise",
            "oauth.json");

    public static OAuthConfig Load()
    {
        try
        {
            if (!File.Exists(DefaultPath))
                return new OAuthConfig();
            var json = File.ReadAllText(DefaultPath);
            return JsonSerializer.Deserialize<OAuthConfig>(
                json, new JsonSerializerOptions { PropertyNameCaseInsensitive = true })
                ?? new OAuthConfig();
        }
        catch
        {
            return new OAuthConfig();
        }
    }
}
