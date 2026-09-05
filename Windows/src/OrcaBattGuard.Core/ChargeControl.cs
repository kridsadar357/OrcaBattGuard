using System.Diagnostics;
using System.Text.RegularExpressions;

namespace OrcaBattGuard.Core;

public interface IChargeController
{
    Task<ChargeControlResult> ApplyAsync(ChargeThresholds thresholds, bool enabled, CancellationToken cancellationToken);
}

public interface IControllerStateStore
{
    Task<string?> LoadOriginalSettingAsync(CancellationToken cancellationToken);
    Task SaveOriginalSettingAsync(string setting, CancellationToken cancellationToken);
    Task ClearOriginalSettingAsync(CancellationToken cancellationToken);
}

public sealed class MemoryControllerStateStore : IControllerStateStore
{
    private string? _setting;

    public Task<string?> LoadOriginalSettingAsync(CancellationToken cancellationToken) => Task.FromResult(_setting);

    public Task SaveOriginalSettingAsync(string setting, CancellationToken cancellationToken)
    {
        _setting = setting;
        return Task.CompletedTask;
    }

    public Task ClearOriginalSettingAsync(CancellationToken cancellationToken)
    {
        _setting = null;
        return Task.CompletedTask;
    }
}

public sealed record CommandResult(int ExitCode, string Output, bool TimedOut = false)
{
    public bool Succeeded => ExitCode == 0 && !TimedOut;
}

public interface ICommandRunner
{
    Task<CommandResult> RunAsync(string executable, IReadOnlyList<string> arguments, TimeSpan timeout, CancellationToken cancellationToken);
}

public sealed class ProcessCommandRunner : ICommandRunner
{
    public async Task<CommandResult> RunAsync(
        string executable,
        IReadOnlyList<string> arguments,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        using var process = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = executable,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            }
        };
        foreach (var argument in arguments)
        {
            process.StartInfo.ArgumentList.Add(argument);
        }

        try
        {
            process.Start();
            var outputTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
            var errorTask = process.StandardError.ReadToEndAsync(cancellationToken);
            using var timeoutSource = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeoutSource.CancelAfter(timeout);
            await process.WaitForExitAsync(timeoutSource.Token);
            var output = string.Join(Environment.NewLine, await outputTask, await errorTask).Trim();
            return new(process.ExitCode, output);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            TryKill(process);
            return new(124, "Command timed out.", true);
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            TryKill(process);
            return new(127, exception.Message);
        }
    }

    private static void TryKill(Process process)
    {
        try
        {
            if (!process.HasExited)
            {
                process.Kill(true);
            }
        }
        catch (InvalidOperationException)
        {
        }
    }
}

public sealed partial class DellCctkChargeController : IChargeController
{
    private readonly ICommandRunner _runner;
    private readonly string? _executable;
    private readonly TimeSpan _timeout;
    private readonly IControllerStateStore _stateStore;

    public DellCctkChargeController(
        ICommandRunner runner,
        string? executable,
        IControllerStateStore? stateStore = null,
        TimeSpan? timeout = null)
    {
        _runner = runner;
        _executable = executable;
        _stateStore = stateStore ?? new MemoryControllerStateStore();
        _timeout = timeout ?? TimeSpan.FromSeconds(5);
    }

    public static string? FindInstalledExecutable()
    {
        var candidates = new[]
        {
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Dell", "Command Configure", "X86_64", "cctk.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Dell", "Command Configure", "X86", "cctk.exe")
        };
        return candidates.FirstOrDefault(File.Exists);
    }

    public async Task<ChargeControlResult> ApplyAsync(
        ChargeThresholds thresholds,
        bool enabled,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(_executable) || !File.Exists(_executable))
        {
            return Unavailable("Dell Command Configure (cctk.exe) was not found.");
        }

        var requested = thresholds.Normalized();
        if (requested.Lower is < 50 or > 95 || requested.Upper is < 55 or > 100 || requested.Upper - requested.Lower < 5)
        {
            return Unavailable("Dell requires start 50-95%, stop 55-100%, with at least a 5% gap.");
        }

        var before = await ReadAsync(cancellationToken);
        if (before is null)
        {
            return Unavailable("Dell charge settings could not be read.");
        }

        var current = ExtractSetting(before);
        if (current is null)
        {
            return Unavailable("Dell charge settings returned an unsupported value.");
        }

        var original = await _stateStore.LoadOriginalSettingAsync(cancellationToken);
        if (!enabled && original is null)
        {
            return new("Dell Command Configure", true, true, false,
                $"Protection is off. Existing Dell setting was left unchanged ({current}).");
        }

        var expected = enabled ? $"Custom:{requested.Lower}-{requested.Upper}" : original!;
        if (Matches(before, expected))
        {
            if (!enabled)
            {
                await _stateStore.ClearOriginalSettingAsync(cancellationToken);
            }
            return Verified(expected, requested, enabled, false);
        }

        if (enabled && original is null)
        {
            await _stateStore.SaveOriginalSettingAsync(current, cancellationToken);
        }

        var write = await _runner.RunAsync(
            _executable,
            [$"--PrimaryBattChargeCfg={expected}"],
            _timeout,
            cancellationToken);
        if (!write.Succeeded)
        {
            return Unavailable($"Dell controller rejected the setting: {write.Output}", true);
        }

        var after = await ReadAsync(cancellationToken);
        if (after is null || !Matches(after, expected))
        {
            return Unavailable("Dell controller did not confirm the requested setting.", true);
        }

        if (!enabled)
        {
            await _stateStore.ClearOriginalSettingAsync(cancellationToken);
        }

        return Verified(expected, requested, enabled, true);
    }

    private async Task<string?> ReadAsync(CancellationToken cancellationToken)
    {
        var result = await _runner.RunAsync(_executable!, ["--PrimaryBattChargeCfg"], _timeout, cancellationToken);
        return result.Succeeded ? result.Output : null;
    }

    private static bool Matches(string output, string expected)
    {
        var value = ExtractSetting(output);
        return value is not null && string.Equals(value, expected, StringComparison.OrdinalIgnoreCase);
    }

    private static string? ExtractSetting(string output)
    {
        var value = OutputRegex().Match(output);
        if (!value.Success)
        {
            return null;
        }
        var setting = value.Groups[1].Value.Replace(" ", "");
        return SettingRegex().IsMatch(setting) ? setting : null;
    }

    private static ChargeControlResult Verified(string expected, ChargeThresholds limits, bool enabled, bool wrote) =>
        new("Dell Command Configure", true, true, wrote,
            $"Verified PrimaryBattChargeCfg={expected}.",
            enabled ? limits.Lower : null,
            enabled ? limits.Upper : null);

    private static ChargeControlResult Unavailable(string message, bool wrote = false) =>
        new("Dell Command Configure", false, false, wrote, message);

    [GeneratedRegex(@"PrimaryBattChargeCfg\s*=\s*([^\r\n]+)", RegexOptions.IgnoreCase)]
    private static partial Regex OutputRegex();

    [GeneratedRegex(@"^(Standard|Express|PrimAcUse|Adaptive|Custom:[5-9][0-9]-[5-9][0-9]|Custom:[5-9][0-9]-100)$", RegexOptions.IgnoreCase)]
    private static partial Regex SettingRegex();
}

public sealed class MonitoringChargeController : IChargeController
{
    public Task<ChargeControlResult> ApplyAsync(ChargeThresholds thresholds, bool enabled, CancellationToken cancellationToken) =>
        Task.FromResult(new ChargeControlResult(
            "Monitoring",
            false,
            false,
            false,
            "No verified charge-control backend is available for this manufacturer."));
}
