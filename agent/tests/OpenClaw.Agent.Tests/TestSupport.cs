using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using OpenClaw.Agent.Core;
using OpenClaw.Agent.Protocol;

namespace OpenClaw.Agent.Tests;

internal static class TestSupport
{
    public static string AgentRoot => FindAgentRoot();
    public static string CliExecutablePath => Path.Combine(AgentRoot, "src", "OpenClaw.Agent.Cli", "bin", "Debug", "net8.0-windows", "OpenClaw.Agent.Cli.exe");
    public static string HostExecutablePath => Path.Combine(AgentRoot, "src", "OpenClaw.Agent.Host", "bin", "Debug", "net8.0-windows", "OpenClaw.Agent.Host.exe");
    public static string TrayExecutablePath => Path.Combine(AgentRoot, "src", "OpenClaw.Agent.Tray", "bin", "Debug", "net8.0-windows", "OpenClaw.Agent.Tray.exe");
    public static string FakeExecutablePath => Path.Combine(AgentRoot, "tests", "OpenClaw.Agent.FakeOpenClaw", "bin", "Debug", "net8.0", "OpenClaw.Agent.FakeOpenClaw.exe");

    public static string CreateTempDataRoot()
    {
        var path = Path.Combine(Path.GetTempPath(), "OpenClaw.Agent.Tests", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(path);
        return path;
    }

    public static AgentPaths GetPaths(string dataRoot)
    {
        return new AgentPaths
        {
            DataRoot = dataRoot,
            ConfigDirectory = Path.Combine(dataRoot, "config"),
            StateDirectory = Path.Combine(dataRoot, "state"),
            LogsDirectory = Path.Combine(dataRoot, "logs"),
            ConfigPath = Path.Combine(dataRoot, "config", AgentConstants.DefaultConfigFileName),
            HostStatePath = Path.Combine(dataRoot, "state", "host-state.json"),
            RunStatePath = Path.Combine(dataRoot, "state", "run-state.json"),
            AgentLogPath = Path.Combine(dataRoot, "logs", "agent.log"),
            StdOutLogPath = Path.Combine(dataRoot, "logs", "openclaw.stdout.log"),
            StdErrLogPath = Path.Combine(dataRoot, "logs", "openclaw.stderr.log")
        };
    }

    public static string CreateTempInstallRoot()
    {
        var path = Path.Combine(Path.GetTempPath(), "OpenClaw.Agent.Install.Tests", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(path);
        return path;
    }

    public static void WriteAgentConfig(string dataRoot, string executablePath, int port, IReadOnlyList<string>? arguments = null, string? workingDirectory = null)
    {
        var paths = GetPaths(dataRoot);
        PathHelpers.EnsureDataDirectories(paths);
        var config = new AgentConfig
        {
            OpenClaw = new OpenClawLaunchConfig
            {
                Executable = executablePath,
                Arguments = arguments?.ToList() ?? [],
                WorkingDirectory = workingDirectory,
                ConfigPath = "%USERPROFILE%\\.openclaw\\openclaw.json"
            },
            Network = new NetworkConfig
            {
                Bind = AgentConstants.DefaultBind,
                Port = port
            }
        };

        File.WriteAllText(paths.ConfigPath, AgentJson.Serialize(config));
    }

    public static int GetFreeTcpPort()
    {
        var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        try
        {
            return ((IPEndPoint)listener.LocalEndpoint).Port;
        }
        finally
        {
            listener.Stop();
        }
    }

    public static async Task<(int ExitCode, string StdOut, string StdErr)> RunCliAsync(
        string dataRoot,
        IReadOnlyList<string> arguments,
        IDictionary<string, string?>? extraEnvironment = null)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = CliExecutablePath,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            WorkingDirectory = Path.GetDirectoryName(CliExecutablePath) ?? AgentRoot
        };

        foreach (var argument in arguments)
        {
            startInfo.ArgumentList.Add(argument);
        }

        startInfo.Environment[AgentConstants.DataRootOverrideEnvironmentVariable] = dataRoot;
        startInfo.Environment[AgentConstants.HostPathOverrideEnvironmentVariable] = HostExecutablePath;
        if (extraEnvironment is not null)
        {
            foreach (var entry in extraEnvironment)
            {
                if (entry.Value is null)
                {
                    startInfo.Environment.Remove(entry.Key);
                }
                else
                {
                    startInfo.Environment[entry.Key] = entry.Value;
                }
            }
        }

        using var process = new Process
        {
            StartInfo = startInfo,
            EnableRaisingEvents = true
        };

        var stdout = new List<string>();
        var stderr = new List<string>();
        var stdoutClosed = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var stderrClosed = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);

        process.OutputDataReceived += (_, eventArgs) =>
        {
            if (eventArgs.Data is null)
            {
                stdoutClosed.TrySetResult();
                return;
            }

            stdout.Add(eventArgs.Data);
        };

        process.ErrorDataReceived += (_, eventArgs) =>
        {
            if (eventArgs.Data is null)
            {
                stderrClosed.TrySetResult();
                return;
            }

            stderr.Add(eventArgs.Data);
        };

        process.Start();
        process.BeginOutputReadLine();
        process.BeginErrorReadLine();
        await process.WaitForExitAsync();
        await Task.WhenAny(Task.WhenAll(stdoutClosed.Task, stderrClosed.Task), Task.Delay(1000));
        return (process.ExitCode, string.Join(Environment.NewLine, stdout), string.Join(Environment.NewLine, stderr));
    }

    public static async Task WaitUntilAsync(Func<Task<bool>> condition, TimeSpan timeout)
    {
        var deadline = DateTimeOffset.UtcNow + timeout;
        while (DateTimeOffset.UtcNow < deadline)
        {
            if (await condition())
            {
                return;
            }

            await Task.Delay(150);
        }

        throw new TimeoutException("Timed out waiting for a condition.");
    }

    public static void CleanupHost(string dataRoot)
    {
        var paths = GetPaths(dataRoot);
        var store = new FileStateStore();
        var hostState = store.Read<HostStateRecord>(paths.HostStatePath);
        if (hostState is not null && hostState.HostProcessId > 0 && ProcessUtilities.ProcessExists(hostState.HostProcessId))
        {
            ProcessUtilities.KillProcessTreeAsync(hostState.HostProcessId, CancellationToken.None).GetAwaiter().GetResult();
        }
    }

    private static string FindAgentRoot()
    {
        var current = new DirectoryInfo(AppContext.BaseDirectory);
        while (current is not null)
        {
            var candidate = Path.Combine(current.FullName, "OpenClaw.Agent.sln");
            if (File.Exists(candidate))
            {
                return current.FullName;
            }

            current = current.Parent;
        }

        throw new DirectoryNotFoundException("Unable to locate the agent solution root.");
    }
}

internal sealed class EnvironmentVariableScope : IDisposable
{
    private readonly string _name;
    private readonly string? _previousValue;

    public EnvironmentVariableScope(string name, string? value)
    {
        _name = name;
        _previousValue = Environment.GetEnvironmentVariable(name);
        Environment.SetEnvironmentVariable(name, value);
    }

    public void Dispose()
    {
        Environment.SetEnvironmentVariable(_name, _previousValue);
    }
}

internal sealed class FakeRegistryAccessor : IRegistryAccessor
{
    private readonly Dictionary<(string KeyPath, string ValueName), string> _values = new();

    public string? GetValue(string keyPath, string valueName)
    {
        return _values.TryGetValue((keyPath, valueName), out var value) ? value : null;
    }

    public void SetValue(string keyPath, string valueName, string value)
    {
        _values[(keyPath, valueName)] = value;
    }

    public void DeleteValue(string keyPath, string valueName)
    {
        _values.Remove((keyPath, valueName));
    }
}
