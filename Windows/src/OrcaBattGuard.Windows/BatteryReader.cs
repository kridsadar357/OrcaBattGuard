using System.Management;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using OrcaBattGuard.Core;

namespace OrcaBattGuard.Windows;

public sealed class BatteryReader
{
    public BatterySnapshot Read()
    {
        if (!OperatingSystem.IsWindows())
        {
            return new(76, PowerSource.Ac, false, 31, 142, 51_200, 60_000);
        }
        return ReadWindows();
    }

    [SupportedOSPlatform("windows")]
    private static BatterySnapshot ReadWindows()
    {
        if (!GetSystemPowerStatus(out var status) || status.BatteryLifePercent == byte.MaxValue)
        {
            return new(-1, PowerSource.Unknown, false);
        }

        var details = ReadWmiDetails();
        return new BatterySnapshot(
            status.BatteryLifePercent,
            status.ACLineStatus switch { 0 => PowerSource.Battery, 1 => PowerSource.Ac, _ => PowerSource.Unknown },
            (status.BatteryFlag & 8) != 0,
            details.TemperatureC,
            details.CycleCount,
            details.FullChargeCapacity,
            details.DesignCapacity);
    }

    public string ReadManufacturer()
    {
        if (!OperatingSystem.IsWindows())
        {
            return "Simulation host";
        }
        return ReadWindowsManufacturer();
    }

    [SupportedOSPlatform("windows")]
    private static string ReadWindowsManufacturer()
    {
        try
        {
            using var searcher = new ManagementObjectSearcher("SELECT Manufacturer FROM Win32_ComputerSystem");
            return searcher.Get().Cast<ManagementObject>().FirstOrDefault()?["Manufacturer"]?.ToString() ?? "Unknown";
        }
        catch (ManagementException)
        {
            return "Unknown";
        }
    }

    [SupportedOSPlatform("windows")]
    private static BatteryDetails ReadWmiDetails()
    {
        return new(
            ReadUInt("root\\wmi", "BatteryTemperature", "CurrentTemperature") is { } rawTemperature
                ? (rawTemperature / 10d) - 273.15
                : null,
            ReadUInt("root\\wmi", "BatteryCycleCount", "CycleCount") is { } cycles ? (int)cycles : null,
            ReadUInt("root\\wmi", "BatteryFullChargedCapacity", "FullChargedCapacity") is { } full ? (int)full : null,
            ReadUInt("root\\wmi", "BatteryStaticData", "DesignedCapacity") is { } design ? (int)design : null);
    }

    [SupportedOSPlatform("windows")]
    private static uint? ReadUInt(string scope, string className, string property)
    {
        try
        {
            using var searcher = new ManagementObjectSearcher(scope, $"SELECT {property} FROM {className}");
            var value = searcher.Get().Cast<ManagementObject>().FirstOrDefault()?[property];
            return value is null ? null : Convert.ToUInt32(value);
        }
        catch (Exception exception) when (exception is ManagementException or UnauthorizedAccessException or FormatException)
        {
            return null;
        }
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetSystemPowerStatus(out SystemPowerStatus status);

    [StructLayout(LayoutKind.Sequential)]
    private struct SystemPowerStatus
    {
        public byte ACLineStatus;
        public byte BatteryFlag;
        public byte BatteryLifePercent;
        public byte SystemStatusFlag;
        public uint BatteryLifeTime;
        public uint BatteryFullLifeTime;
    }

    private sealed record BatteryDetails(double? TemperatureC, int? CycleCount, int? FullChargeCapacity, int? DesignCapacity);
}
