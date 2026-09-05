using OrcaBattGuard.Core;

namespace OrcaBattGuard.Windows;

public sealed class FileControllerStateStore : IControllerStateStore
{
    private readonly string _path;

    public FileControllerStateStore(string? path = null)
    {
        _path = path ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "OrcaBatteryGuardian",
            "controller-state.txt");
    }

    public async Task<string?> LoadOriginalSettingAsync(CancellationToken cancellationToken)
    {
        if (!File.Exists(_path))
        {
            return null;
        }
        var value = await File.ReadAllTextAsync(_path, cancellationToken);
        return string.IsNullOrWhiteSpace(value) ? null : value.Trim();
    }

    public async Task SaveOriginalSettingAsync(string setting, CancellationToken cancellationToken)
    {
        var directory = Path.GetDirectoryName(_path)!;
        Directory.CreateDirectory(directory);
        var temporary = $"{_path}.tmp";
        await File.WriteAllTextAsync(temporary, setting, cancellationToken);
        File.Move(temporary, _path, true);
    }

    public Task ClearOriginalSettingAsync(CancellationToken cancellationToken)
    {
        if (File.Exists(_path))
        {
            File.Delete(_path);
        }
        return Task.CompletedTask;
    }
}
