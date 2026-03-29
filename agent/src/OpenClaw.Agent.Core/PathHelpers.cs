using System.Diagnostics;
using System.Security.Principal;

namespace OpenClaw.Agent.Core;

public static class PathHelpers
{
    public static AgentPaths GetDefaultPaths()
    {
        var overrideRoot = Environment.GetEnvironmentVariable(AgentConstants.DataRootOverrideEnvironmentVariable);
        var dataRoot = string.IsNullOrWhiteSpace(overrideRoot)
            ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "OpenClaw")
            : Path.GetFullPath(overrideRoot);

        var configDirectory = Path.Combine(dataRoot, "config");
        var stateDirectory = Path.Combine(dataRoot, "state");
        var logsDirectory = Path.Combine(dataRoot, "logs");

        return new AgentPaths
        {
            DataRoot = dataRoot,
            ConfigDirectory = configDirectory,
            StateDirectory = stateDirectory,
            LogsDirectory = logsDirectory,
            ConfigPath = Path.Combine(configDirectory, AgentConstants.DefaultConfigFileName),
            HostStatePath = Path.Combine(stateDirectory, "host-state.json"),
            RunStatePath = Path.Combine(stateDirectory, "run-state.json"),
            AgentLogPath = Path.Combine(logsDirectory, "agent.log"),
            StdOutLogPath = Path.Combine(logsDirectory, "openclaw.stdout.log"),
            StdErrLogPath = Path.Combine(logsDirectory, "openclaw.stderr.log")
        };
    }

    public static string GetInstallRoot()
    {
        var overrideRoot = Environment.GetEnvironmentVariable(AgentConstants.InstallRootOverrideEnvironmentVariable);
        return string.IsNullOrWhiteSpace(overrideRoot)
            ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "OpenClaw", "app")
            : Path.GetFullPath(overrideRoot);
    }

    public static string GetCurrentInstallDirectory()
    {
        return Path.Combine(GetInstallRoot(), "current");
    }

    public static CurrentSessionContext GetCurrentSession()
    {
        using var identity = WindowsIdentity.GetCurrent();
        return new CurrentSessionContext
        {
            UserSid = identity.User?.Value ?? throw new InvalidOperationException("Unable to resolve the current user SID."),
            UserName = identity.Name ?? Environment.UserName,
            SessionId = Process.GetCurrentProcess().SessionId
        };
    }

    public static void EnsureDataDirectories(AgentPaths paths)
    {
        Directory.CreateDirectory(paths.DataRoot);
        Directory.CreateDirectory(paths.ConfigDirectory);
        Directory.CreateDirectory(paths.StateDirectory);
        Directory.CreateDirectory(paths.LogsDirectory);
    }

    public static string ExpandValue(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return string.Empty;
        }

        return Path.GetFullPath(Environment.ExpandEnvironmentVariables(value));
    }

    public static bool IsStablePublishDirectory(string baseDirectory)
    {
        return HasPathTail(baseDirectory, AgentConstants.StablePublishTail);
    }

    public static bool IsInstalledLayoutDirectory(string baseDirectory)
    {
        var expected = GetCurrentInstallDirectory()
            .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        var actual = Path.GetFullPath(baseDirectory)
            .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        return string.Equals(actual, expected, StringComparison.OrdinalIgnoreCase)
            || HasPathTail(baseDirectory, AgentConstants.InstalledLayoutTail);
    }

    public static bool IsSupportedLaunchDirectory(string baseDirectory)
    {
        return IsStablePublishDirectory(baseDirectory) || IsInstalledLayoutDirectory(baseDirectory);
    }

    private static bool HasPathTail(string baseDirectory, IReadOnlyList<string> tail)
    {
        var fullPath = Path.GetFullPath(baseDirectory)
            .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);

        var current = new DirectoryInfo(fullPath);
        for (var index = tail.Count - 1; index >= 0; index--)
        {
            if (current is null || !string.Equals(current.Name, tail[index], StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }

            current = current.Parent;
        }

        return true;
    }
}
