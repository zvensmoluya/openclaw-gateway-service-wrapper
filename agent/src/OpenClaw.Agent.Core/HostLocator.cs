namespace OpenClaw.Agent.Core;

public sealed class HostLaunchInfo
{
    public string FileName { get; init; } = string.Empty;
    public List<string> Arguments { get; init; } = [];
    public string ExpectedHostExecutablePath { get; init; } = string.Empty;
}

public static class HostLocator
{
    public static HostLaunchInfo ResolveFromCliBaseDirectory(string cliBaseDirectory)
    {
        var overridePath = Environment.GetEnvironmentVariable(AgentConstants.HostPathOverrideEnvironmentVariable);
        if (!string.IsNullOrWhiteSpace(overridePath))
        {
            return BuildLaunchInfo(Path.GetFullPath(overridePath));
        }

        var hostExePath = Path.Combine(cliBaseDirectory, AgentConstants.HostExecutableName);
        if (File.Exists(hostExePath))
        {
            return BuildLaunchInfo(hostExePath);
        }

        var hostDllPath = Path.Combine(cliBaseDirectory, AgentConstants.HostDllName);
        if (File.Exists(hostDllPath))
        {
            return BuildLaunchInfo(hostDllPath);
        }

        throw new FileNotFoundException(
            $"Unable to locate {AgentConstants.HostExecutableName} or {AgentConstants.HostDllName} next to the CLI executable. Set {AgentConstants.HostPathOverrideEnvironmentVariable} to override the host path.");
    }

    private static HostLaunchInfo BuildLaunchInfo(string hostPath)
    {
        if (hostPath.EndsWith(".dll", StringComparison.OrdinalIgnoreCase))
        {
            return new HostLaunchInfo
            {
                FileName = "dotnet",
                Arguments = [hostPath],
                ExpectedHostExecutablePath = hostPath
            };
        }

        return new HostLaunchInfo
        {
            FileName = hostPath,
            Arguments = [],
            ExpectedHostExecutablePath = hostPath
        };
    }
}
