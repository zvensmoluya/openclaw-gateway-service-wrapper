using System.Diagnostics;
using OpenClaw.Agent.Core;

namespace OpenClaw.Agent.Tests;

public sealed class AutostartAndCacheTests
{
    [Fact]
    public void AutostartManager_RequiresStablePublishLayout()
    {
        var registry = new FakeRegistryAccessor();
        var manager = new AutostartManager(registry);
        var stableRoot = Path.Combine(Path.GetTempPath(), "OpenClaw.Agent.Tests", Guid.NewGuid().ToString("N"), "dist", "v2", "win-x64", "current");
        Directory.CreateDirectory(stableRoot);
        var hostPath = Path.Combine(stableRoot, AgentConstants.HostExecutableName);
        File.WriteAllText(hostPath, string.Empty);

        var status = manager.Enable(hostPath);

        Assert.True(status.Enabled);
        Assert.True(status.PathMatches);
        Assert.NotNull(status.RegistryValue);
    }

    [Fact]
    public void AutostartManager_AcceptsInstalledLayout()
    {
        var registry = new FakeRegistryAccessor();
        var manager = new AutostartManager(registry);
        var installRoot = TestSupport.CreateTempInstallRoot();
        var appRoot = Path.Combine(installRoot, "OpenClaw", "app");
        var currentRoot = Path.Combine(appRoot, "current");
        Directory.CreateDirectory(currentRoot);
        var hostPath = Path.Combine(currentRoot, AgentConstants.HostExecutableName);
        File.WriteAllText(hostPath, string.Empty);

        using var installRootScope = new EnvironmentVariableScope(AgentConstants.InstallRootOverrideEnvironmentVariable, appRoot);
        var status = manager.Enable(hostPath);

        Assert.True(status.Enabled);
        Assert.True(status.PathMatches);
        Assert.NotNull(status.RegistryValue);
        Directory.Delete(installRoot, recursive: true);
    }

    [Fact]
    public void CacheReportReader_FlagsCrossSessionConflict()
    {
        var dataRoot = TestSupport.CreateTempDataRoot();
        try
        {
            var paths = TestSupport.GetPaths(dataRoot);
            PathHelpers.EnsureDataDirectories(paths);
            TestSupport.WriteAgentConfig(dataRoot, TestSupport.FakeExecutablePath, 19111);
            var store = new FileStateStore();
            store.Write(paths.HostStatePath, new HostStateRecord
            {
                State = AgentState.Running,
                DesiredState = AgentState.Running,
                HostProcessId = Environment.ProcessId,
                OpenClawProcessId = Environment.ProcessId,
                SessionId = Process.GetCurrentProcess().SessionId + 1,
                StartedAt = DateTimeOffset.UtcNow,
                UpdatedAt = DateTimeOffset.UtcNow
            });

            var reader = new CacheReportReader(
                autostartManager: new AutostartManager(new FakeRegistryAccessor()));
            var response = reader.ReadStatus(false, paths, TestSupport.HostExecutablePath, Process.GetCurrentProcess().SessionId);

            Assert.False(response.Success);
            Assert.Contains(response.Issues, issue => issue.Contains("does not support multiple interactive sessions", StringComparison.OrdinalIgnoreCase));
            Assert.Equal("cache", response.StatusSource);
        }
        finally
        {
            Directory.Delete(dataRoot, recursive: true);
        }
    }
}
