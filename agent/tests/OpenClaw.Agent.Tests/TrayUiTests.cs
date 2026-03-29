using OpenClaw.Agent.Core;
using OpenClaw.Agent.Protocol;
using OpenClaw.Agent.Tray;

namespace OpenClaw.Agent.Tests;

public sealed class TrayUiTests
{
    [Fact]
    public void TrayIconResolver_ResolvesBundledInstalledAsset()
    {
        var installRoot = TestSupport.CreateTempInstallRoot();
        var baseDirectory = Path.Combine(installRoot, "current");
        Directory.CreateDirectory(Path.Combine(baseDirectory, "assets", "tray"));
        var iconPath = Path.Combine(baseDirectory, "assets", "tray", "openclaw-healthy.ico");
        File.Copy(Path.Combine(TestSupport.AgentRoot, "..", "assets", "tray", "openclaw-healthy.ico"), iconPath, overwrite: true);

        try
        {
            var resolver = new TrayIconResolver(baseDirectory);
            var path = resolver.ResolveIconPath(new TrayConfig(), "running");

            Assert.Equal(iconPath, path);
        }
        finally
        {
            Directory.Delete(installRoot, recursive: true);
        }
    }

    [Fact]
    public void TrayIssueReader_PicksRecentAuthenticationMismatch()
    {
        var dataRoot = TestSupport.CreateTempDataRoot();
        var paths = TestSupport.GetPaths(dataRoot);
        PathHelpers.EnsureDataDirectories(paths);
        File.WriteAllText(paths.StdErrLogPath, """
2026-03-29T15:38:13.957+08:00 [ws] unauthorized conn=1 reason=device_token_mismatch
2026-03-29T15:38:15.830+08:00 [ws] closed before connect reason=unauthorized: too many failed authentication attempts (retry later)
""");

        try
        {
            var reader = new TrayIssueReader();
            var issue = reader.GetRecentIssue(paths, new AgentResponse());

            Assert.Contains("too many failed authentication attempts", issue, StringComparison.OrdinalIgnoreCase);
        }
        finally
        {
            Directory.Delete(dataRoot, recursive: true);
        }
    }

    [Fact]
    public void TrayShellActions_OpenExpectedTargets()
    {
        var launcher = new RecordingTrayLauncher();
        var actions = new TrayShellActions(launcher);

        actions.OpenDashboard(18789);
        actions.OpenLogs(@"C:\logs");
        actions.OpenConfigDirectory(@"C:\config\agent.json");

        Assert.Equal(
            [
                "http://localhost:18789/",
                @"C:\logs",
                @"C:\config"
            ],
            launcher.Targets);
    }

    private sealed class RecordingTrayLauncher : ITrayLauncher
    {
        public List<string> Targets { get; } = [];

        public void Launch(string target)
        {
            Targets.Add(target);
        }
    }
}
