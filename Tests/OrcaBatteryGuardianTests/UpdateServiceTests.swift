import Testing
@testable import OrcaBatteryGuardian

@Test(arguments: [
    ("0.7.1", "0.7.0", true),
    ("0.8.0", "0.7.9", true),
    ("1.0.0", "0.9.9", true),
    ("0.7.0", "0.7.0", false),
    ("0.6.9", "0.7.0", false),
    ("0.7.0-beta", "0.7.0", false)
])
func semanticVersionComparison(input: (String, String, Bool)) {
    #expect(GitHubUpdateService.isNewer(input.0, than: input.1) == input.2)
}
