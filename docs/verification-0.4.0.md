# 0.4.0 Verification

Date: 2026-09-04. Status: hardened beta, not a production certification.

## Environment

- Apple Silicon, macOS 26.0.1 (25A362).
- Local `batt` 0.8.0 client and daemon.
- Release bundle installed at `/Applications/OrcaBatteryGuardian.app`.

## Completed Checks

- `swift test`: 64 tests passed, including parameterized cases.
- `swift test -c release`: 64 tests passed, including parameterized cases.
- `git diff --check`: passed.
- Release packaging, Developer ID signing, hardened runtime, and strict code
  signature verification: passed.
- Installed bundle reports version 0.4.0, build 4, and runs from
  `/Applications`.
- Signing identity: Developer ID Application: TKGH GROUP COMPANY LIMITED
  (JGZ59SA7RF).
- Live daemon read-back remained enabled at 50-80%. At verification time the
  battery was at 82%, charging was disabled, and the Mac was using AC power.
- The in-app Diagnostics run passed battery telemetry, application location,
  `batt` installation, daemon compatibility, current limits, and calibration
  checks. It correctly reported that Apple's native Charge Limit is not
  available on the installed macOS version.
- Click-through smoke tests covered Overview, Settings, Diagnostics, and the
  menu bar popover. Displayed power, charge state, temperature, and limits
  agreed with the live daemon result.

## Automated Coverage Added in 0.4.0

- Temporary Charge to 100% can run for one, two, or four hours, persists across
  relaunches, restores the saved profile on expiry or shutdown, and cancels
  when protection is disabled.
- Temporary full charge preserves critical-low and thermal safety limits.
- Cooling Pause uses a five-minute minimum pause and a 3 C resume margin to
  avoid rapid state changes around the temperature threshold.
- Public IOPowerSources notifications trigger an immediate refresh, with a
  30-second reconciliation interval retained as a fallback.
- Diagnostics are read-only and surface missing backends and daemon failures.
- The native Charge Limit transition is ignored on unsupported macOS versions
  and disables Orca control before opening System Settings on supported ones.

## Not Completed

- Apple notarization and stapling: awaiting a usable `notarytool` Keychain
  Profile. No Accepted receipt or distribution ticket has been obtained.
- A physical Temporary Charge to 100% cycle was not started because that would
  change the user's active 50-80% battery policy. Its controller behavior is
  covered by injected tests.
- Native Charge Limit click-through could not be tested on macOS 26.0.1; the
  feature requires macOS 26.4 or later on Apple Silicon.
- Overnight/all-day endurance, restart and sleep/wake cycles, and physical
  threshold crossings still need longer-running hardware tests.
- Thermal-policy certification is outside this verification. Cooling Pause is
  an application policy, not a hardware safety system.

No verification step stopped the live daemon or deliberately changed the live
charge limits. Hardware failure, recovery, cooling, and temporary full-charge
scenarios used injected test doubles.
