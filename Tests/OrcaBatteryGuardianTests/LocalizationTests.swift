import AppKit
import Foundation
import Testing
@testable import OrcaBatteryGuardian

@Test func thaiLocalizationFormatsBatteryStatus() {
    #expect(L10n.string("Holding at %d%%", language: .thai, 78) == "คงระดับที่ 78%")
    #expect(L10n.string("Charging to %d%%", language: .thai, 80) == "กำลังชาร์จถึง 80%")
    #expect(PowerSource.acPower.title(language: .thai) == "ไฟจากอะแดปเตอร์")
}

@Test func englishLocalizationUsesSourceText() {
    #expect(L10n.string("Battery protection", language: .english) == "Battery protection")
    #expect(GuardianMode.maximumLife.title(language: .english) == "Maximum Life")
}

@Test func stateMachineReturnsThaiDecisionText() {
    let decision = GuardianStateMachine().decide(
        snapshot: sampleBattery(65, charging: true),
        thresholds: testLimits,
        protectionEnabled: true,
        language: .thai
    )

    #expect(decision.statusText == "กำลังชาร์จถึง 80%")
    #expect(decision.reason == "ชาร์จต่อภายในช่วงเป้าหมายจนถึงเพดานที่กำหนด")
}

@Test @MainActor func selectedLanguagePersistsAcrossRelaunch() throws {
    let suite = "OrcaLanguageTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    let first = GuardianSettings(defaults: defaults)
    first.language = .thai

    #expect(GuardianSettings(defaults: defaults).language == .thai)
}

@Test func controllerResultIsLocalizedWithoutHidingVerification() {
    let result = ChargeControlResult(
        backendName: "batt",
        isHardwareControlAvailable: true,
        didAttemptHardwareChange: true,
        message: "Verified charge limits: 50-80%. Hardware charging may take time to reflect the policy.",
        verifiedAt: Date(),
        isLimitEnabled: true,
        upperLimit: 80,
        lowerLimit: 50
    ).localized(language: .thai)

    #expect(result.backendName == "batt")
    #expect(result.message.contains("50-80%"))
    #expect(result.message.hasPrefix("ยืนยันช่วงชาร์จ"))
}

@Test func sarabunFontsAreBundledAndRegisterable() {
    BundledFontRegistrar.registerSarabun()
    #expect(NSFont(name: "Sarabun-Regular", size: 14) != nil)
    #expect(NSFont(name: "Sarabun-Bold", size: 14) != nil)
}
