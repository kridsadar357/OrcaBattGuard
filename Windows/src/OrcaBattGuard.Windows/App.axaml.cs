using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Interactivity;
using Avalonia.Markup.Xaml;

namespace OrcaBattGuard.Windows;

public partial class App : Application
{
    private MainWindow? _window;

    public override void Initialize() => AvaloniaXamlLoader.Load(this);

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            desktop.ShutdownMode = ShutdownMode.OnExplicitShutdown;
            _window = new MainWindow();
            desktop.MainWindow = _window;
        }
        base.OnFrameworkInitializationCompleted();
    }

    private void ShowWindow_OnClick(object? sender, EventArgs args)
    {
        if (_window is null)
        {
            return;
        }
        _window.ShowInTaskbar = true;
        _window.Show();
        _window.WindowState = WindowState.Normal;
        _window.Activate();
    }

    private async void Refresh_OnClick(object? sender, EventArgs args)
    {
        if (_window is not null)
        {
            await _window.ViewModel.RefreshAsync();
        }
    }

    private void Quit_OnClick(object? sender, EventArgs args)
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            _window?.AllowClose();
            _window?.ViewModel.Dispose();
            desktop.Shutdown();
        }
    }
}
