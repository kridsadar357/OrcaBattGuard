using OrcaBattGuard.Core;

namespace OrcaBattGuard.Core.Tests;

public sealed class GuardianStateMachineTests
{
    private readonly GuardianStateMachine _machine = new();
    private readonly ChargeThresholds _limits = new(50, 80);

    [Fact]
    public void ChargingTelemetryWinsInsideRange()
    {
        var result = _machine.Decide(new(65, PowerSource.Ac, true), _limits, true);
        Assert.Equal(GuardianState.Charging, result.State);
    }

    [Fact]
    public void HotBatteryRaisesWarningBeforeUpperLimit()
    {
        var result = _machine.Decide(new(65, PowerSource.Ac, true, 40), _limits, true);
        Assert.Equal(GuardianState.CoolingPause, result.State);
        Assert.Equal("Temperature warning", result.Status);
    }

    [Fact]
    public void CriticalLowOverridesHeat()
    {
        var result = _machine.Decide(new(10, PowerSource.Ac, true, 45), _limits, true);
        Assert.Equal(GuardianState.CriticalCharge, result.State);
    }
}
