using System.Diagnostics;
using OpenClaw.Agent.Cli;
using OpenClaw.Agent.Core;
using OpenClaw.Agent.Protocol;

namespace OpenClaw.Agent.Tests;

[Trait("Category", "DesktopIntegration")]
public sealed class TrayIntegrationTests
{
    [Fact]
    public async Task Tray_ProcessExit_DoesNotStopLiveHost()
    {
        var dataRoot = TestSupport.CreateTempDataRoot();
        try
        {
            TestSupport.WriteAgentConfig(dataRoot, TestSupport.FakeExecutablePath, TestSupport.GetFreeTcpPort());
            using var dataRootScope = new EnvironmentVariableScope(AgentConstants.DataRootOverrideEnvironmentVariable, dataRoot);
            using var installRootScope = new EnvironmentVariableScope(AgentConstants.InstallRootOverrideEnvironmentVariable, TestSupport.CreateTempInstallRoot());
            using var hostPathScope = new EnvironmentVariableScope(AgentConstants.HostPathOverrideEnvironmentVariable, TestSupport.HostExecutablePath);
            using var healthModeScope = new EnvironmentVariableScope("FAKE_OPENCLAW_HEALTH_MODE", "ok");

            var startCli = new CliApplication(new StringWriter(), new StringWriter());
            var startExitCode = await startCli.RunAsync(["start", "--json"], CancellationToken.None);
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
                return response is not null && response.HostReachable && response.State.Current == "Running";
            }, TimeSpan.FromSeconds(10));

            using var trayProcess = Process.Start(new ProcessStartInfo
            {
                FileName = TestSupport.TrayExecutablePath,
                UseShellExecute = false,
                CreateNoWindow = true,
                WorkingDirectory = Path.GetDirectoryName(TestSupport.TrayExecutablePath) ?? dataRoot
            }) ?? throw new InvalidOperationException("Unable to start the tray process.");

            await TestSupport.WaitUntilAsync(() => Task.FromResult(!trayProcess.HasExited), TimeSpan.FromSeconds(5));

            trayProcess.Kill(entireProcessTree: true);
            await trayProcess.WaitForExitAsync();

            var statusOutput = new StringWriter();
            var statusError = new StringWriter();
            var statusCli = new CliApplication(statusOutput, statusError);
            var statusExitCode = await statusCli.RunAsync(["status", "--json"], CancellationToken.None);
            Assert.Equal(0, statusExitCode);

            var liveResponse = AgentJson.Deserialize<AgentResponse>(statusOutput.ToString())!;
            Assert.True(liveResponse.HostReachable);
            Assert.Equal("Running", liveResponse.State.Current);
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

    [Fact]
    public async Task Tray_AutoRecoversHost_WhenCachedStateRequestsRunning()
    {
        var dataRoot = TestSupport.CreateTempDataRoot();
        try
        {
            TestSupport.WriteAgentConfig(dataRoot, TestSupport.FakeExecutablePath, TestSupport.GetFreeTcpPort());
            var paths = TestSupport.GetPaths(dataRoot);
            PathHelpers.EnsureDataDirectories(paths);
            var store = new FileStateStore();
            store.Write(paths.HostStatePath, new HostStateRecord
            {
                State = AgentState.Starting,
                DesiredState = AgentState.Running,
                HostProcessId = 0,
                OpenClawProcessId = 0,
                SessionId = Process.GetCurrentProcess().SessionId,
                StartedAt = DateTimeOffset.UtcNow,
                UpdatedAt = DateTimeOffset.UtcNow,
                AutostartEnabled = true
            });

            using var dataRootScope = new EnvironmentVariableScope(AgentConstants.DataRootOverrideEnvironmentVariable, dataRoot);
            using var installRootScope = new EnvironmentVariableScope(AgentConstants.InstallRootOverrideEnvironmentVariable, TestSupport.CreateTempInstallRoot());
            using var hostPathScope = new EnvironmentVariableScope(AgentConstants.HostPathOverrideEnvironmentVariable, TestSupport.HostExecutablePath);
            using var healthModeScope = new EnvironmentVariableScope("FAKE_OPENCLAW_HEALTH_MODE", "ok");

            using var trayProcess = Process.Start(new ProcessStartInfo
            {
                FileName = TestSupport.TrayExecutablePath,
                UseShellExecute = false,
                CreateNoWindow = true,
                WorkingDirectory = Path.GetDirectoryName(TestSupport.TrayExecutablePath) ?? dataRoot
            }) ?? throw new InvalidOperationException("Unable to start the tray process.");

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
                    && response.State.Current == "Running";
            }, TimeSpan.FromSeconds(15));

            trayProcess.Kill(entireProcessTree: true);
            await trayProcess.WaitForExitAsync();
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
