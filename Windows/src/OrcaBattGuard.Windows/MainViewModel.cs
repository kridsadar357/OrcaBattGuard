using System.ComponentModel;
using System.Collections.ObjectModel;
using System.Runtime.CompilerServices;
using System.Windows.Input;
using Avalonia.Threading;
using OrcaBattGuard.Core;

namespace OrcaBattGuard.Windows;

public sealed class MainViewModel : INotifyPropertyChanged, IDisposable
{
    private readonly BatteryReader _batteryReader = new();
    private readonly GuardianStateMachine _stateMachine = new();
    private readonly AppStorage _storage = new();
    private readonly Timer _timer;
    private readonly SemaphoreSlim _refreshGate = new(1, 1);
    private IChargeController? _controller;
    private string _manufacturer = "Detecting";
    private int _percentage = -1;
    private int _lowerLimit = 50;
    private int _upperLimit = 80;
    private bool _protectionEnabled = true;
    private bool _simulationEnabled;
    private string _status = "Reading battery...";
    private string _reason = "";
    private string _telemetryText = "";
    private string _controllerState = "Checking";
    private string _controllerMessage = "Detecting a verified OEM backend.";
    private string? _lastActivityFingerprint;

    public MainViewModel()
    {
        var saved = _storage.LoadSettings();
        var savedLimits = new ChargeThresholds(saved.LowerLimit, saved.UpperLimit).Normalized();
        _lowerLimit = savedLimits.Lower;
        _upperLimit = savedLimits.Upper;
        _protectionEnabled = saved.ProtectionEnabled;
        _simulationEnabled = saved.SimulationEnabled;
        Activity = _storage.LoadHistory();
        RefreshCommand = new AsyncCommand(RefreshAsync);
        SetMaxLifeCommand = new RelayCommand(() => SetProfile(50, 70));
        SetBalancedCommand = new RelayCommand(() => SetProfile(50, 80));
        SetTravelCommand = new RelayCommand(() => SetProfile(50, 100));
        _timer = new Timer(
            _ => Dispatcher.UIThread.Post(async () => await RefreshAsync()),
            null,
            TimeSpan.FromSeconds(30),
            TimeSpan.FromSeconds(30));
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    public ICommand RefreshCommand { get; }
    public ICommand SetMaxLifeCommand { get; }
    public ICommand SetBalancedCommand { get; }
    public ICommand SetTravelCommand { get; }
    public ObservableCollection<ActivityEntry> Activity { get; }

    public string PercentageText => _percentage < 0 ? "--" : $"{_percentage}%";
    public string Status { get => _status; private set => Set(ref _status, value); }
    public string Reason { get => _reason; private set => Set(ref _reason, value); }
    public string TelemetryText { get => _telemetryText; private set => Set(ref _telemetryText, value); }
    public string ControllerState { get => _controllerState; private set => Set(ref _controllerState, value); }
    public string ControllerMessage { get => _controllerMessage; private set => Set(ref _controllerMessage, value); }
    public string ManufacturerText => $"Manufacturer: {_manufacturer}";
    public string RangeText => $"{LowerLimit}-{UpperLimit}%";
    public string LowerText => $"{LowerLimit}%";
    public string UpperText => $"{UpperLimit}%";

    public int LowerLimit
    {
        get => _lowerLimit;
        set
        {
            var safe = Math.Min(value, UpperLimit - 5);
            if (Set(ref _lowerLimit, safe))
            {
                NotifyRange();
                SaveSettings();
                _ = RefreshAsync();
            }
        }
    }

    public int UpperLimit
    {
        get => _upperLimit;
        set
        {
            var safe = Math.Max(value, LowerLimit + 5);
            if (Set(ref _upperLimit, safe))
            {
                NotifyRange();
                SaveSettings();
                _ = RefreshAsync();
            }
        }
    }

    public bool ProtectionEnabled
    {
        get => _protectionEnabled;
        set
        {
            if (Set(ref _protectionEnabled, value))
            {
                SaveSettings();
                _ = RefreshAsync();
            }
        }
    }

    public bool SimulationEnabled
    {
        get => _simulationEnabled;
        set
        {
            if (Set(ref _simulationEnabled, value))
            {
                SaveSettings();
                _ = RefreshAsync();
            }
        }
    }

    public async Task RefreshAsync()
    {
        if (!await _refreshGate.WaitAsync(0))
        {
            return;
        }

        try
        {
            var snapshot = SimulationEnabled
                ? new BatterySnapshot(76, PowerSource.Ac, false, 31, 142, 51_200, 60_000)
                : await Task.Run(_batteryReader.Read);
            if (_controller is null)
            {
                _manufacturer = await Task.Run(_batteryReader.ReadManufacturer);
                _controller = CreateController(_manufacturer);
                OnPropertyChanged(nameof(ManufacturerText));
            }

            _percentage = snapshot.Percentage;
            OnPropertyChanged(nameof(PercentageText));
            var limits = new ChargeThresholds(LowerLimit, UpperLimit);
            var decision = _stateMachine.Decide(snapshot, limits, ProtectionEnabled);
            Status = decision.Status;
            Reason = decision.Reason;
            TelemetryText = BuildTelemetry(snapshot);

            var result = SimulationEnabled
                ? new ChargeControlResult("Simulation", false, false, false, "Simulation is isolated from hardware control.")
                : await _controller.ApplyAsync(limits, ProtectionEnabled, CancellationToken.None);
            ControllerState = result.IsVerified ? "Verified" : result.IsAvailable ? "Available" : "Monitoring";
            ControllerMessage = result.Message;
            RecordActivity(decision, result);
        }
        finally
        {
            _refreshGate.Release();
        }
    }

    private static IChargeController CreateController(string manufacturer)
    {
        if (manufacturer.Contains("Dell", StringComparison.OrdinalIgnoreCase))
        {
            return new DellCctkChargeController(
                new ProcessCommandRunner(),
                DellCctkChargeController.FindInstalledExecutable(),
                new FileControllerStateStore());
        }
        return new MonitoringChargeController();
    }

    private static string BuildTelemetry(BatterySnapshot snapshot)
    {
        var source = snapshot.PowerSource == PowerSource.Ac ? "AC power" : snapshot.PowerSource == PowerSource.Battery ? "Battery" : "Unknown power";
        var temperature = snapshot.TemperatureC is { } value ? $"{value:F1} C" : "temperature unavailable";
        var health = snapshot.HealthPercent is { } percent ? $"health {percent}%" : "health unavailable";
        var cycles = snapshot.CycleCount is { } count ? $"{count} cycles" : "cycles unavailable";
        return $"{source}  |  {temperature}  |  {health}  |  {cycles}";
    }

    private void SetProfile(int lower, int upper)
    {
        _lowerLimit = lower;
        _upperLimit = upper;
        OnPropertyChanged(nameof(LowerLimit));
        OnPropertyChanged(nameof(UpperLimit));
        NotifyRange();
        SaveSettings();
        _ = RefreshAsync();
    }

    private void NotifyRange()
    {
        OnPropertyChanged(nameof(RangeText));
        OnPropertyChanged(nameof(LowerText));
        OnPropertyChanged(nameof(UpperText));
    }

    private void SaveSettings()
    {
        try
        {
            _storage.SaveSettings(new(ProtectionEnabled, SimulationEnabled, LowerLimit, UpperLimit));
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            ControllerMessage = $"Settings could not be saved: {exception.Message}";
        }
    }

    private void RecordActivity(GuardianDecision decision, ChargeControlResult control)
    {
        var fingerprint = $"{decision.State}|{control.IsVerified}|{control.Message}";
        if (fingerprint == _lastActivityFingerprint)
        {
            return;
        }
        _lastActivityFingerprint = fingerprint;
        Activity.Insert(0, new ActivityEntry(DateTimeOffset.Now, decision.Status, control.Message));
        while (Activity.Count > 200)
        {
            Activity.RemoveAt(Activity.Count - 1);
        }
        try
        {
            _storage.SaveHistory(Activity);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            ControllerMessage = $"History could not be saved: {exception.Message}";
        }
    }

    private bool Set<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value))
        {
            return false;
        }
        field = value;
        OnPropertyChanged(propertyName);
        return true;
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));

    public void Dispose()
    {
        _timer.Dispose();
        _refreshGate.Dispose();
    }
}

internal sealed class RelayCommand(Action execute) : ICommand
{
    public event EventHandler? CanExecuteChanged { add { } remove { } }
    public bool CanExecute(object? parameter) => true;
    public void Execute(object? parameter) => execute();
}

internal sealed class AsyncCommand(Func<Task> execute) : ICommand
{
    private bool _running;
    public event EventHandler? CanExecuteChanged;
    public bool CanExecute(object? parameter) => !_running;

    public async void Execute(object? parameter)
    {
        if (_running)
        {
            return;
        }
        _running = true;
        CanExecuteChanged?.Invoke(this, EventArgs.Empty);
        try
        {
            await execute();
        }
        finally
        {
            _running = false;
            CanExecuteChanged?.Invoke(this, EventArgs.Empty);
        }
    }
}
