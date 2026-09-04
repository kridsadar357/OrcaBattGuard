# 0.5.0 Verification

Date: 2026-09-04. Status: working beta with live benchmark collection.

## Environment

- Apple Silicon, macOS 26.0.1 (25A362).
- Local `batt` 0.8.0 client and daemon.
- Release bundle installed at `/Applications/OrcaBatteryGuardian.app`.

## Completed Checks

- `swift test`: 74 tests passed, including parameterized cases.
- `swift test -c release`: 74 tests passed, including parameterized cases.
- `git diff --check` and Info.plist validation: passed.
- Release packaging, Developer ID signing, hardened runtime, and strict code
  signature verification: passed.
- Installed bundle reports version 0.5.0, build 5, and runs from
  `/Applications`.
- Live charge limits remained enabled at 50-80% before and after installation.
- The first live benchmark baseline was saved with cycle count 234, full
  charge capacity 7,595 mAh, design capacity 8,579 mAh, and temperature
  30.86 C.
- `benchmark.json` was created with mode 0600 and survived application
  replacement and relaunch without resetting its baseline.
- Click-through and screenshot checks covered the four-tab header, Benchmark
  summary cards, 7/30/90-day selector, capacity placeholder, comparison table,
  scrolling, and compact 440-point window layout.
- Displayed benchmark values agreed with the saved daily summary. The live
  daemon still reported 82%, not charging, and using AC power during the
  initial check.

## Automated Coverage Added in 0.5.0

- Baseline creation, daily aggregation, capacity and health estimates, cycle
  changes, temperature, high-SOC time, protection time, and controller
  reliability.
- Observed intervals split correctly at local midnight.
- Gaps longer than five minutes are capped, and time while the app is closed
  is not counted after relaunch.
- Benchmark data survives relaunch, uses restrictive file permissions, and
  preserves an unreadable file until the user explicitly resets the baseline.
- Reset Baseline replaces earlier days, and CSV output contains the daily
  comparison fields.
- Simulation Mode never records into the live benchmark.

## Still Needs Time

- Only the first day exists, so the capacity graph will appear after a second
  daily point is available.
- Seven, 30, and 90-day comparisons need their corresponding real collection
  periods before their trends are meaningful.
- Capacity values can fluctuate with temperature and battery-controller
  estimation. A benchmark trend is observational and does not prove that Orca
  caused a capacity change.
- Longer sleep/wake, restart, and continuous-use testing remains useful even
  though gaps and relaunch behavior are covered by automated tests.

No verification step changed the live 50-80% policy, stopped the daemon, or
started a forced discharge or temporary full-charge cycle.
