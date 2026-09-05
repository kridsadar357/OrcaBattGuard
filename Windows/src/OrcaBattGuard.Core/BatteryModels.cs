namespace OrcaBattGuard.Core;

public enum PowerSource
{
    Unknown,
    Battery,
    Ac
}

public enum GuardianState
{
    Monitoring,
    Charging,
    Holding,
    CoolingPause,
    CriticalCharge
}

public sealed record BatterySnapshot(
    int Percentage,
    PowerSource PowerSource,
    bool IsCharging,
    double? TemperatureC = null,
    int? CycleCount = null,
    int? FullChargeCapacityMwh = null,
    int? DesignCapacityMwh = null,
    DateTimeOffset? Timestamp = null)
{
    public DateTimeOffset CapturedAt { get; } = Timestamp ?? DateTimeOffset.Now;
    public int? HealthPercent => FullChargeCapacityMwh is > 0 && DesignCapacityMwh is > 0
        ? Math.Clamp((int)Math.Round(100d * FullChargeCapacityMwh.Value / DesignCapacityMwh.Value), 0, 100)
        : null;
}

public sealed record ChargeThresholds(int Lower, int Upper, int CriticalLow = 15, double HotTemperatureC = 38)
{
    public ChargeThresholds Normalized()
    {
        var lower = Math.Clamp(Lower, 5, 95);
        var upper = Math.Clamp(Upper, lower + 5, 100);
        return this with
        {
            Lower = lower,
            Upper = upper,
            CriticalLow = Math.Clamp(CriticalLow, 5, lower),
            HotTemperatureC = Math.Clamp(HotTemperatureC, 30, 55)
        };
    }
}

public sealed record GuardianDecision(GuardianState State, string Status, string Reason);

public sealed record ChargeControlResult(
    string Backend,
    bool IsAvailable,
    bool IsVerified,
    bool DidWrite,
    string Message,
    int? LowerLimit = null,
    int? UpperLimit = null);
