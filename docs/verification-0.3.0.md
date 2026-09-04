# 0.3.0 Verification

Date: 2026-09-03. Status: hardened beta, not a production certification.

## Environment

- Apple Silicon, macOS 26.0.1 (25A362).
- Local `batt` 0.8.0 daemon, existing charge limits 50-80%.
- Release bundle installed at `/Applications/OrcaBatteryGuardian.app`.

## Completed Checks

- `swift test`: 44 tests passed, including parameterized cases.
- `swift test -c release`: 44 tests passed, including parameterized cases.
- `git diff --check`: passed.
- Release packaging with the resource bundle and application icon: passed.
- Developer ID signature, hardened runtime, secure timestamp, and strict
  signature verification: passed.
- Signing identity: Developer ID Application: TKGH GROUP COMPANY LIMITED
  (JGZ59SA7RF).
- Installation and replacement of the installed app: passed. The installer
  waits for graceful shutdown before replacement and retains a ZIP backup.
- Live read-back confirmed the daemon's existing 50-80% configuration.
- Overview screenshot showed On Battery and Discharging, consistent with the
  actual power source. Charge limits verified was displayed separately.
- History was written to Application Support and retained its earlier event
  IDs after quitting, relaunching, and reinstalling the app.
- The app continued background monitoring while the screen was locked.

## Automated Coverage

- Failed writes, partially applied settings, malformed JSON, unsupported
  control, active calibration, daemon failure, and read-back mismatches never
  produce a verified result.
- Subsequent refreshes re-read the daemon, retry failed updates, and repair
  external configuration changes without relying on a command cache.
- External processes run off MainActor, have bounded output and timeouts, and
  are terminated on cancellation, including processes ignoring SIGTERM.
- Controller updates are serialized; refresh requests coalesce. Cancelled
  operations cannot issue subsequent writes or publish stale results.
- Simulation never invokes the real controller and does not clear existing
  hardware limits.
- State-machine tests cover charging inside the target range, pending stop,
  battery-only operation, unavailable data, cooling, and critical-low policy.
- History tests cover restart persistence, count/byte limits, duplicate IDs,
  file permissions, corrupt files, and write failures.

## Not Completed

- Apple notarization and stapling: awaiting a usable `notarytool` Keychain
  Profile. No Accepted receipt or distribution ticket has been obtained.
- Click-through testing of all tabs/menu controls in the new installed build:
  the Mac was screen-locked during the final smoke test.
- Overnight/all-day endurance, sleep/wake and login cycles, and physical
  charging through both thresholds on all supported Mac models.
- Thermal-policy certification. Critical-low still takes precedence over
  cooling, matching the previous policy; this is not a hardware safety layer.

No tests stopped the live daemon or deliberately changed live battery limits.
Hardware failure, repair, and cooling scenarios used injected fakes. The
notarization workflow is implemented but must succeed for the exact bundle
before public distribution.
