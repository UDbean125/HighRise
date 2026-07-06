using System.Collections.ObjectModel;
using HighRise.Core.Models;
using HighRise.Core.Services;
using HighRise.Mail;

namespace HighRise.App;

/// <summary>
/// Drives the Compose -> Import -> Review -> Send flow, delegating all real work
/// to HighRise.Core (parse/merge/validate) and HighRise.Mail (send).
/// </summary>
public sealed class HighRiseViewModel : ObservableObject
{
    private List<Contact> _contacts = new();

    // --- Compose ---
    private string _subject = string.Empty;
    public string Subject { get => _subject; set { if (Set(ref _subject, value)) Refresh(); } }

    private string _body = string.Empty;
    public string Body { get => _body; set { if (Set(ref _body, value)) Refresh(); } }

    private bool _isHtml;
    public bool IsHtml { get => _isHtml; set { if (Set(ref _isHtml, value)) Refresh(); } }

    // --- Import ---
    public ObservableCollection<MergePreview> Previews { get; } = new();

    private string _importSummary = string.Empty;
    public string ImportSummary { get => _importSummary; private set => Set(ref _importSummary, value); }

    // --- Review ---
    private string _reviewSummary = "Sendable: 0    Blocked: 0";
    public string ReviewSummary { get => _reviewSummary; private set => Set(ref _reviewSummary, value); }

    // --- Send ---
    public EmailProvider Provider { get; set; } = EmailProvider.Gmail;
    public SendMode Mode { get; set; } = SendMode.Draft;

    private string _status = string.Empty;
    public string Status { get => _status; private set => Set(ref _status, value); }

    public void ImportCsv(string text)
    {
        try
        {
            var table = CsvParser.Parse(text);
            var (contacts, header) = CsvParser.Contacts(table);
            _contacts = contacts;
            ImportSummary = $"Imported {contacts.Count} contact(s)"
                + (header is null ? string.Empty : $" · email column: “{header}”");
        }
        catch (Exception ex)
        {
            _contacts = new List<Contact>();
            ImportSummary = $"Import failed: {ex.Message}";
        }
        Refresh();
    }

    public async Task SendAsync(IAccessTokenProvider tokens, HttpClient http)
    {
        var sendable = BuildPreviews().Where(p => p.IsSendable).ToList();
        if (sendable.Count == 0)
        {
            Status = "Nothing to send — compose a message and import valid recipients first.";
            return;
        }

        IEmailSender sender = Provider == EmailProvider.Gmail
            ? new GmailSender(http, tokens)
            : new GraphSender(http, tokens);

        int ok = 0, failed = 0;
        foreach (var preview in sendable)
        {
            var message = ComposedMessage.FromPreview(preview, IsHtml);
            try
            {
                await sender.SendAsync(message, Mode);
                ok++;
            }
            catch (Exception ex)
            {
                failed++;
                Status = $"Error sending to {message.RecipientEmail}: {ex.Message}";
            }
        }

        var verb = Mode == SendMode.Send ? "Sent" : "Drafted";
        Status = $"{verb} {ok}/{sendable.Count}" + (failed > 0 ? $" ({failed} failed)" : string.Empty);
    }

    private List<MergePreview> BuildPreviews()
    {
        var template = new EmailTemplate(Subject, Body, IsHtml ? BodyFormat.Html : BodyFormat.PlainText);
        return TemplateMergeEngine.MergeAll(template, _contacts).ToList();
    }

    private void Refresh()
    {
        var previews = BuildPreviews();
        Previews.Clear();
        foreach (var preview in previews)
            Previews.Add(preview);

        var sendable = previews.Count(p => p.IsSendable);
        ReviewSummary = $"Sendable: {sendable}    Blocked: {previews.Count - sendable}";
    }
}
