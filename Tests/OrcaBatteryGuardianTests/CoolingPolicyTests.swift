import Foundation
import Testing
@testable import OrcaBatteryGuardian

@Test func coolingPauseStartsAtConfiguredTemperature() {
    let now = Date(timeIntervalSince1970: 1_000)
    let result = CoolingPolicy().evaluate(temperatureC: 38, pauseAtC: 38, startedAt: nil, now: now)
    #expect(result.isActive)
    #expect(result.startedAt == now)
}

@Test func coolingPauseDoesNotOscillateNearThreshold() {
    let started = Date(timeIntervalSince1970: 1_000)
    let policy = CoolingPolicy(resumeDeltaC: 3, minimumPause: 300)
    #expect(policy.evaluate(temperatureC: 34, pauseAtC: 38, startedAt: started, now: started.addingTimeInterval(299)).isActive)
    #expect(policy.evaluate(temperatureC: 36, pauseAtC: 38, startedAt: started, now: started.addingTimeInterval(600)).isActive)
    #expect(policy.evaluate(temperatureC: nil, pauseAtC: 38, startedAt: started, now: started.addingTimeInterval(600)).isActive)
}

@Test func coolingPauseEndsOnlyAfterTimeAndTemperatureConditionsPass() {
    let started = Date(timeIntervalSince1970: 1_000)
    let result = CoolingPolicy().evaluate(temperatureC: 35, pauseAtC: 38,
        startedAt: started, now: started.addingTimeInterval(300))
    #expect(!result.isActive)
}

@Test func stateMachineHonorsActiveCoolingPauseBelowTriggerTemperature() {
    let decision = GuardianStateMachine().decide(snapshot: sampleBattery(65, charging: true, temperature: 35),
        thresholds: testLimits, protectionEnabled: true, coolingPauseActive: true)
    #expect(decision.state == .coolingPause)
    #expect(decision.desiredAction == .pauseCharging)
}

@Test(arguments: [
    (OperatingSystemVersion(majorVersion: 26, minorVersion: 3, patchVersion: 9), false),
    (OperatingSystemVersion(majorVersion: 26, minorVersion: 4, patchVersion: 0), true),
    (OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0), true)
]) func nativeChargeLimitAvailabilityHasCorrectBoundary(input: (OperatingSystemVersion, Bool)) {
    #expect(NativeChargeLimitSupport.isAvailable(on: input.0) == input.1)
}

@Test func nativeChargeLimitIsNotAdvertisedOnIntel() {
    let futureVersion = OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)
    #expect(!NativeChargeLimitSupport.isAvailable(on: futureVersion, architecture: .intel))
}
