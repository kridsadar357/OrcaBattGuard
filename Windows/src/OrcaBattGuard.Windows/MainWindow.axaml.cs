using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;

namespace OrcaBattGuard.Windows;

public partial class MainWindow : Window
{
    private bool _allowClose;
    public MainViewModel ViewModel { get; } = new();

    public MainWindow()
    {
        InitializeComponent();
        DataContext = ViewModel;
        Opened += async (_, _) => await ViewModel.RefreshAsync();
        Closing += (_, args) =>
        {
            if (!_allowClose)
            {
                args.Cancel = true;
                ShowInTaskbar = false;
                Hide();
            }
        };
    }

    public void AllowClose() => _allowClose = true;
}
