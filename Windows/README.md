# Orca Battery Guardian for Windows

Windows companion app for Orca Battery Guardian. The first Windows build uses Avalonia on .NET 8 and runs as a compact dashboard plus system-tray utility.

## Current support

| Feature | Support |
| --- | --- |
| Battery percentage, AC source and charging state | Windows 10/11 |
| Temperature, cycle count and capacity | When exposed by the battery WMI driver |
| Presets and custom thresholds | Included |
| Persistent settings, Simulation and bounded activity history | Included |
| Verified hardware charge control | Dell systems supported by Dell Command Configure |
| Other manufacturers | Monitoring mode until a documented, verifiable backend is added |

Windows itself exposes battery status but does not provide one universal user-mode API for charge thresholds. Orca therefore enables control only after detecting a supported OEM backend and reading the configured value back.

Settings and the latest 200 state changes are stored locally under `%LOCALAPPDATA%\OrcaBatteryGuardian`. Simulation mode never invokes an OEM controller.

The temperature threshold is currently a warning, not a claim that charging was paused. Windows and the laptop firmware remain responsible for thermal protection until an OEM backend can request and verify an immediate pause safely.

## Dell charge control

Install Dell Command Configure from Dell Support. Orca looks for `cctk.exe` in the standard installation directories and uses `PrimaryBattChargeCfg=Custom:start-stop`.

Dell requires Administrator privileges for Command Configure, so the Windows executable requests elevation through UAC when it starts. A later production helper service can narrow this privilege boundary; the current beta keeps the requirement visible instead of silently failing to apply BIOS settings.

Dell supports a start value of 50-95%, a stop value of 55-100%, and requires at least a 5% gap. Orca reads the current value before every update and reads it again after writing. A successful process exit without matching readback is not shown as verified.

Before Orca changes the Dell setting, it stores the original BIOS value under `%LOCALAPPDATA%\OrcaBatteryGuardian`. Disabling protection restores that exact value and verifies the readback. If Orca has never changed the setting, turning protection off leaves the existing Dell configuration untouched. Some Dell models do not expose this BIOS option; those machines remain in Monitoring mode.

## Build

Use Windows 10/11 with the .NET 8 SDK:

```powershell
dotnet restore OrcaBattGuard.Windows.sln
dotnet test OrcaBattGuard.Windows.sln
dotnet build OrcaBattGuard.Windows.sln -c Release
dotnet publish src/OrcaBattGuard.Windows/OrcaBattGuard.Windows.csproj -c Release -r win-x64 --self-contained true
```

The app and tests can be built on macOS, but final tray, WMI and OEM-controller verification must be performed on Windows hardware.

For a self-contained zip on Windows, run:

```powershell
.\Scripts\package-windows.ps1
```

The same test and publish steps run on GitHub Actions using `windows-latest`. The workflow uploads a `win-x64` artifact for hardware testing. The bundled Sarabun font is licensed under the SIL Open Font License and is ready for the Thai UI localization pass.
