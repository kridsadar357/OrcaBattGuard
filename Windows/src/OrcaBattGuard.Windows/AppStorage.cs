using System.Collections.ObjectModel;
using System.Text.Json;

namespace OrcaBattGuard.Windows;

public sealed record AppSettings(bool ProtectionEnabled = true, bool SimulationEnabled = false, int LowerLimit = 50, int UpperLimit = 80);

public sealed record ActivityEntry(DateTimeOffset Timestamp, string Status, string Detail)
{
    public string TimeText => Timestamp.LocalDateTime.ToString("HH:mm:ss");
}

public sealed class AppStorage
{
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };
    private readonly string _directory;
    private readonly string _settingsPath;
    private readonly string _historyPath;

    public AppStorage(string? directory = null)
    {
        _directory = directory ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "OrcaBatteryGuardian");
        _settingsPath = Path.Combine(_directory, "settings.json");
        _historyPath = Path.Combine(_directory, "history.json");
    }

    public AppSettings LoadSettings()
    {
        try
        {
            return File.Exists(_settingsPath)
                ? JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(_settingsPath)) ?? new()
                : new();
        }
        catch (Exception exception) when (exception is IOException or JsonException or UnauthorizedAccessException)
        {
            return new();
        }
    }

    public void SaveSettings(AppSettings settings) => WriteAtomic(_settingsPath, JsonSerializer.Serialize(settings, JsonOptions));

    public ObservableCollection<ActivityEntry> LoadHistory()
    {
        try
        {
            var entries = File.Exists(_historyPath)
                ? JsonSerializer.Deserialize<List<ActivityEntry>>(File.ReadAllText(_historyPath)) ?? []
                : [];
            return new(entries.OrderByDescending(entry => entry.Timestamp).Take(200));
        }
        catch (Exception exception) when (exception is IOException or JsonException or UnauthorizedAccessException)
        {
            return [];
        }
    }

    public void SaveHistory(IEnumerable<ActivityEntry> entries) =>
        WriteAtomic(_historyPath, JsonSerializer.Serialize(entries.Take(200), JsonOptions));

    private void WriteAtomic(string path, string content)
    {
        Directory.CreateDirectory(_directory);
        var temporary = $"{path}.tmp";
        File.WriteAllText(temporary, content);
        File.Move(temporary, path, true);
    }
}
