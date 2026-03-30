using System.Diagnostics;

namespace OpenClaw.Agent.Core;

public static class HostBootstrapper
{
    public static Task StartHostAsync(HostLaunchInfo hostLaunchInfo, string source)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = hostLaunchInfo.FileName,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            WorkingDirectory = Path.GetDirectoryName(hostLaunchInfo.ExpectedHostExecutablePath) ?? AppContext.BaseDirectory
        };

        var dotnetRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".dotnet");
        if (Directory.Exists(dotnetRoot))
        {
            startInfo.Environment["DOTNET_ROOT"] = dotnetRoot;
        }

        foreach (var argument in hostLaunchInfo.Arguments)
        {
            startInfo.ArgumentList.Add(argument);
        }

        if (string.Equals(source, "autostart", StringComparison.OrdinalIgnoreCase))
        {
            startInfo.ArgumentList.Add("--autostart");
        }

        using var process = Process.Start(startInfo);
        return Task.CompletedTask;
    }
}
