using System.Diagnostics;

namespace OpenClaw.Agent.Tray;

internal interface ITrayLauncher
{
    void Launch(string target);
}

internal sealed class ShellTrayLauncher : ITrayLauncher
{
    public void Launch(string target)
    {
        Process.Start(new ProcessStartInfo
        {
            FileName = target,
            UseShellExecute = true
        });
    }
}

internal sealed class TrayShellActions
{
    private readonly ITrayLauncher _launcher;

    public TrayShellActions(ITrayLauncher? launcher = null)
    {
        _launcher = launcher ?? new ShellTrayLauncher();
    }

    public void OpenDashboard(int port)
    {
        _launcher.Launch($"http://localhost:{port}/");
    }

    public void OpenLogs(string logsDirectory)
    {
        Directory.CreateDirectory(logsDirectory);
        _launcher.Launch(logsDirectory);
    }

    public void OpenConfigDirectory(string configPath)
    {
        var directory = Path.GetDirectoryName(configPath);
        if (!string.IsNullOrWhiteSpace(directory))
        {
            Directory.CreateDirectory(directory);
            _launcher.Launch(directory);
        }
    }
}
