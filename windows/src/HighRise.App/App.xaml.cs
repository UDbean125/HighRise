using Microsoft.UI.Xaml;

namespace HighRise.App;

/// <summary>Application entry point for the HighRise Windows edition.</summary>
public partial class App : Application
{
    private Window? _window;

    public App()
    {
        InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _window = new MainWindow();
        _window.Activate();
    }
}
