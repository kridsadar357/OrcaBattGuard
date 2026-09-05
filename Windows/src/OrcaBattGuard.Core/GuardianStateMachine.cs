namespace OrcaBattGuard.Core;

public sealed class GuardianStateMachine
{
    public GuardianDecision Decide(BatterySnapshot snapshot, ChargeThresholds requested, bool protectionEnabled)
    {
        var limits = requested.Normalized();
        if (!protectionEnabled)
        {
            return new(GuardianState.Monitoring, "Protection off", "Windows or the OEM utility manages charging.");
        }

        if (snapshot.PowerSource == PowerSource.Unknown || snapshot.Percentage is < 0 or > 100)
        {
            return new(GuardianState.Monitoring, "Battery unavailable", "No reliable battery reading is available.");
        }

        if (snapshot.PowerSource == PowerSource.Battery)
        {
            return new(GuardianState.Monitoring, $"On battery at {snapshot.Percentage}%", "Connect AC power to charge.");
        }

        if (snapshot.Percentage <= limits.CriticalLow)
        {
            return new(GuardianState.CriticalCharge, $"Safety charging to {limits.Upper}%", "Critical-low protection overrides the cooling pause.");
        }

        if (snapshot.TemperatureC >= limits.HotTemperatureC)
        {
            return new(
                GuardianState.CoolingPause,
                "Temperature warning",
                "Battery temperature reached the configured limit. OEM firmware remains responsible for thermal protection.");
        }

        if (snapshot.IsCharging)
        {
            return new(GuardianState.Charging, $"Charging to {limits.Upper}%", "The battery is currently charging.");
        }

        if (snapshot.Percentage >= limits.Upper)
        {
            return new(GuardianState.Holding, $"Holding at {snapshot.Percentage}%", "The upper charge threshold has been reached.");
        }

        return new(GuardianState.Holding, "On AC power", "The OEM controller decides when charging resumes.");
    }
}
