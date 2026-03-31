using System.Diagnostics;
using OpenClaw.Agent.Core;
using OpenClaw.Agent.Cli;
using OpenClaw.Agent.Protocol;

namespace OpenClaw.Agent.Tests;

[Trait("Category", "DesktopIntegration")]
public sealed class RuntimeAndCliIntegrationTests
{
    [Fact]
    public async Task Runtime_TransitionsToDegraded_WhenHealthFails()
    {
        var dataRoot = TestSupport.CreateTempDataRoot();
        var paths = TestSupport.GetPaths(dataRoot);
        var registry = new FakeRegistryAccessor();
        var session = PathHelpers.GetCurrentSession();
        TestSupport.WriteAgentConfig(dataRoot, TestSupport.FakeExecutablePath, TestSupport.GetFreeTcpPort());

        using var healthModeScope = new EnvironmentVariableScope("FAKE_OPENCLAW_HEALTH_MODE", "failing");
        var runtime = new AgentRuntime(
            paths,
            session,
            TestSupport.HostExecutablePath,
            autostartManager: new AutostartManager(registry),
            healthPollInterval: TimeSpan.FromMilliseconds(200),
            startupGracePeriod: TimeSpan.FromMilliseconds(600));

        try
        {
            await runtime.InitializeAsync("test", CancellationToken.None);
            await TestSupport.WaitUntilAsync(async () =>
            {
                var status = await runtime.GetStatusAsync(CancellationToken.None);
                return string.Equals(status.State.Current, AgentState.Degraded.ToString(), StringComparison.Ordinal);
            }, TimeSpan.FromSeconds(8));

            var response = await runtime.GetStatusAsync(CancellationToken.None);
            Assert.Equal("Degraded", response.State.Current);
            Assert.False(response.Health.Ok);
        }
        finally
        {
            await runtime.ShutdownAsync(CancellationToken.None);
            await runtime.DisposeAsync();
            Directory.Delete(dataRoot, recursive: true);
        }
    }

    [Fact]
    public async Task Cli_StartStatusStop_WorksAgainstLiveHost()
    {
        var dataRoot = TestSupport.CreateTempDataRoot();
        try
        {
            TestSupport.WriteAgentConfig(dataRoot, TestSupport.FakeExecutablePath, TestSupport.GetFreeTcpPort());
            using var dataRootScope = new EnvironmentVariableScope(AgentConstants.DataRootOverrideEnvironmentVariable, dataRoot);
            using var hostPathScope = new EnvironmentVariableScope(AgentConstants.HostPathOverrideEnvironmentVariable, TestSupport.HostExecutablePath);
            using var healthModeScope = new EnvironmentVariableScope("FAKE_OPENCLAW_HEALTH_MODE", "ok");
            using var exitAfterScope = new EnvironmentVariableScope("FAKE_OPENCLAW_EXIT_AFTER_MS", null);
            using var exitCodeScope = new EnvironmentVariableScope("FAKE_OPENCLAW_EXIT_CODE", null);

            var startOutput = new StringWriter();
            var startError = new StringWriter();
            var cli = new CliApplication(startOutput, startError);
            var startExitCode = await cli.RunAsync(["start", "--json"], CancellationToken.None);
            Assert.Equal(0, startExitCode);

            await TestSupport.WaitUntilAsync(async () =>
            {
                var writer = new StringWriter();
                var error = new StringWriter();
                var statusCli = new CliApplication(writer, error);
                var statusExitCode = await statusCli.RunAsync(["status", "--json"], CancellationToken.None);
                if (statusExitCode != 0)
                {
                    return false;
                }

                var response = AgentJson.Deserialize<AgentResponse>(writer.ToString());
                return response is not null
                    && response.HostReachable
                    && response.StatusSource == "live"
                    && response.State.Current == "Running";
            }, TimeSpan.FromSeconds(10));

            var statusOutput = new StringWriter();
            var statusError = new StringWriter();
            var statusCli = new CliApplication(statusOutput, statusError);
            var statusExitCode = await statusCli.RunAsync(["status", "--json"], CancellationToken.None);
            Assert.Equal(0, statusExitCode);
            var liveResponse = AgentJson.Deserialize<AgentResponse>(statusOutput.ToString())!;
            Assert.Equal("live", liveResponse.StatusSource);
            Assert.True(liveResponse.HostReachable);

            var stopOutput = new StringWriter();
            var stopError = new StringWriter();
            var stopCli = new CliApplication(stopOutput, stopError);
            var stopExitCode = await stopCli.RunAsync(["stop", "--json"], CancellationToken.None);
            Assert.Equal(0, stopExitCode);

            TestSupport.CleanupHost(dataRoot);
            var cachedOutput = new StringWriter();
            var cachedError = new StringWriter();
            var cachedCli = new CliApplication(cachedOutput, cachedError);
            var cachedExitCode = await cachedCli.RunAsync(["status", "--json"], CancellationToken.None);
            Assert.Equal(1, cachedExitCode);
            var cachedResponse = AgentJson.Deserialize<AgentResponse>(cachedOutput.ToString())!;
            Assert.Equal("cache", cachedResponse.StatusSource);
            Assert.False(cachedResponse.HostReachable);
            Assert.Equal("Stopped", cachedResponse.State.Current);
        }
        finally
        {
            TestSupport.CleanupHost(dataRoot);
            if (Directory.Exists(dataRoot))
            {
                Directory.Delete(dataRoot, recursive: true);
            }
        }
    }
}
