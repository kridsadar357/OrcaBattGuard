import Testing
@testable import OrcaBatteryGuardian

@Test func pausesAtUpperLimitWithoutForcingDischarge() {
    let machine = GuardianStateMachine()
    let snapshot = BatterySnapshot(
        percentage: 80,
        powerSource: .acPower,
        isCharging: true,
        isFullyCharged: false,
        temperatureC: 31,
        cycleCount: 100,
        health: "Good"
    )

    let decision = machine.decide(snapshot: snapshot, thresholds: ChargeThresholds(lower: 50, upper: 80), protectionEnabled: true)

    #expect(decision.state == .holding)
    #expect(decision.desiredAction == .pauseCharging)
    #expect(decision.statusText == "Holding at 80%")
}

@Test func chargesAtLowerLimit() {
    let machine = GuardianStateMachine()
    let snapshot = BatterySnapshot(
        percentage: 50,
        powerSource: .acPower,
        isCharging: false,
        isFullyCharged: false,
        temperatureC: 30,
        cycleCount: nil,
        health: nil
    )

    let decision = machine.decide(snapshot: snapshot, thresholds: ChargeThresholds(lower: 50, upper: 80), protectionEnabled: true)

    #expect(decision.state == .charging)
    #expect(decision.desiredAction == .allowCharging)
    #expect(decision.statusText == "Charging to 80%")
}

@Test func criticalLowOverridesHeatPause() {
    let machine = GuardianStateMachine()
    let snapshot = BatterySnapshot(
        percentage: 12,
        powerSource: .acPower,
        isCharging: false,
        isFullyCharged: false,
        temperatureC: 42,
        cycleCount: nil,
        health: nil
    )

    let decision = machine.decide(snapshot: snapshot, thresholds: ChargeThresholds(lower: 50, upper: 80), protectionEnabled: true)

    #expect(decision.state == .safetyCharge)
    #expect(decision.desiredAction == .allowCharging)
}

@Test func highTemperaturePausesCharging() {
    let machine = GuardianStateMachine()
    let snapshot = BatterySnapshot(
        percentage: 64,
        powerSource: .acPower,
        isCharging: true,
        isFullyCharged: false,
        temperatureC: 39,
        cycleCount: nil,
        health: nil
    )

    let decision = machine.decide(snapshot: snapshot, thresholds: ChargeThresholds(lower: 50, upper: 80, hotTemperatureC: 38), protectionEnabled: true)

    #expect(decision.state == .coolingPause)
    #expect(decision.desiredAction == .pauseCharging)
}

@Test func convertsSmartBatteryTemperatureToCelsius() {
    #expect(IOKitBatteryDataProvider.celsiusTemperature(from: 3065) == 30.65)
    #expect(IOKitBatteryDataProvider.celsiusTemperature(from: 0) == nil)
}
