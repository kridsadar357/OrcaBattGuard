using OrcaBattGuard.Core;

namespace OrcaBattGuard.Core.Tests;

public sealed class DellCctkChargeControllerTests
{
    [Fact]
    public async Task MatchingReadbackDoesNotWrite()
    {
        var path = CreateExecutablePlaceholder();
        try
        {
            var runner = new ScriptedRunner(new CommandResult(0, "PrimaryBattChargeCfg=Custom:50-80"));
            var result = await new DellCctkChargeController(runner, path)
                .ApplyAsync(new(50, 80), true, CancellationToken.None);

            Assert.True(result.IsVerified);
            Assert.False(result.DidWrite);
            Assert.Single(runner.Calls);
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public async Task WriteRequiresMatchingReadback()
    {
        var path = CreateExecutablePlaceholder();
        try
        {
            var runner = new ScriptedRunner(
                new CommandResult(0, "PrimaryBattChargeCfg=Adaptive"),
                new CommandResult(0, "PrimaryBattChargeCfg=Custom:50-80"),
                new CommandResult(0, "PrimaryBattChargeCfg=Custom:50-80"));
            var result = await new DellCctkChargeController(runner, path)
                .ApplyAsync(new(50, 80), true, CancellationToken.None);

            Assert.True(result.IsVerified);
            Assert.True(result.DidWrite);
            Assert.Equal("--PrimaryBattChargeCfg=Custom:50-80", runner.Calls[1].Single());
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public async Task MismatchedReadbackIsNeverVerified()
    {
        var path = CreateExecutablePlaceholder();
        try
        {
            var runner = new ScriptedRunner(
                new CommandResult(0, "PrimaryBattChargeCfg=Adaptive"),
                new CommandResult(0, "PrimaryBattChargeCfg=Custom:50-80"),
                new CommandResult(0, "PrimaryBattChargeCfg=Adaptive"));
            var result = await new DellCctkChargeController(runner, path)
                .ApplyAsync(new(50, 80), true, CancellationToken.None);

            Assert.False(result.IsVerified);
            Assert.True(result.DidWrite);
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public async Task DisablingRestoresOriginalSettingAcrossControllerInstances()
    {
        var path = CreateExecutablePlaceholder();
        var store = new MemoryControllerStateStore();
        try
        {
            var enableRunner = new ScriptedRunner(
                new CommandResult(0, "PrimaryBattChargeCfg=Adaptive"),
                new CommandResult(0, "PrimaryBattChargeCfg=Custom:50-80"),
                new CommandResult(0, "PrimaryBattChargeCfg=Custom:50-80"));
            var enabled = await new DellCctkChargeController(enableRunner, path, store)
                .ApplyAsync(new(50, 80), true, CancellationToken.None);

            var disableRunner = new ScriptedRunner(
                new CommandResult(0, "PrimaryBattChargeCfg=Custom:50-80"),
                new CommandResult(0, "PrimaryBattChargeCfg=Adaptive"),
                new CommandResult(0, "PrimaryBattChargeCfg=Adaptive"));
            var disabled = await new DellCctkChargeController(disableRunner, path, store)
                .ApplyAsync(new(50, 80), false, CancellationToken.None);

            Assert.True(enabled.IsVerified);
            Assert.True(disabled.IsVerified);
            Assert.True(disabled.DidWrite);
            Assert.Contains("Adaptive", disabled.Message);
            Assert.Null(await store.LoadOriginalSettingAsync(CancellationToken.None));
        }
        finally
        {
            File.Delete(path);
        }
    }

    private static string CreateExecutablePlaceholder()
    {
        var path = Path.GetTempFileName();
        return path;
    }

    private sealed class ScriptedRunner(params CommandResult[] results) : ICommandRunner
    {
        private readonly Queue<CommandResult> _results = new(results);
        public List<IReadOnlyList<string>> Calls { get; } = [];

        public Task<CommandResult> RunAsync(string executable, IReadOnlyList<string> arguments, TimeSpan timeout, CancellationToken cancellationToken)
        {
            Calls.Add(arguments);
            return Task.FromResult(_results.Dequeue());
        }
    }
}
