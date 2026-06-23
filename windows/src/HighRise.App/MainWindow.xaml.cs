using HighRise.Mail;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace HighRise.App;

public sealed partial class MainWindow : Window
{
    private readonly HttpClient _http = new();
    private readonly IAccessTokenProvider _tokens = new NotConfiguredTokenProvider();

    public HighRiseViewModel ViewModel { get; } = new();

    public MainWindow()
    {
        InitializeComponent();
        Title = "HighRise";
    }

    private void OnImport(object sender, RoutedEventArgs e) =>
        ViewModel.ImportCsv(PasteBox.Text);

    private async void OnSend(object sender, RoutedEventArgs e) =>
        await ViewModel.SendAsync(_tokens, _http);

    private void OnProviderChanged(object sender, SelectionChangedEventArgs e) =>
        ViewModel.Provider = ((ComboBox)sender).SelectedIndex == 0
            ? EmailProvider.Gmail
            : EmailProvider.Outlook;

    private void OnModeChanged(object sender, SelectionChangedEventArgs e) =>
        ViewModel.Mode = ((ComboBox)sender).SelectedIndex == 0
            ? SendMode.Draft
            : SendMode.Send;
}
