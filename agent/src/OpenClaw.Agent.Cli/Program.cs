using System.Diagnostics;
using OpenClaw.Agent.Core;
using OpenClaw.Agent.Protocol;

namespace OpenClaw.Agent.Cli;

internal static class Program
{
    private static async Task<int> Main(string[] args)
    {
        var app = new CliApplication();
        return await app.RunAsync(args, CancellationToken.None);
    }
}

public sealed class CliApplication
{
    private readonly TextWriter _output;
    private readonly TextWriter _error;

    public CliApplication(TextWriter? output = null, TextWriter? error = null)
    {
        _output = output ?? Console.Out;
        _error = error ?? Console.Error;
    }

    public async Task<int> RunAsync(string[] args, CancellationToken cancellationToken)
    {
        if (args.Length == 0)
        {
            WriteUsage();
            return 1;
        }

        var command = args[0].ToLowerInvariant();
        var json = args.Any(argument => string.Equals(argument, "--json", StringComparison.OrdinalIgnoreCase));
        var session = PathHelpers.GetCurrentSession();
        var paths = PathHelpers.GetDefaultPaths();
        PathHelpers.EnsureDataDirectories(paths);
        var hostLaunchInfo = HostLocator.ResolveFromCliBaseDirectory(AppContext.BaseDirectory);
        var pipeClient = new AgentPipeClient(session, paths.DataRoot);
        var cacheReader = new CacheReportReader();
        var autostartManager = new AutostartManager();
        var migrator = new WrapperConfigMigrator();

        return command switch
        {
            "start" => await RunMutatingCommandAsync("start", json, pipeClient, cacheReader, session, paths, hostLaunchInfo, cancellationToken),
            "restart" => await RunMutatingCommandAsync("restart", json, pipeClient, cacheReader, session, paths, hostLaunchInfo, cancellationToken),
            "stop" => await RunStopAsync(json, pipeClient, cacheReader, session, paths, hostLaunchInfo, cancellationToken),
            "status" => await RunReadCommandAsync("status", json, pipeClient, cacheReader, session, paths, hostLaunchInfo, cancellationToken),
            "doctor" => await RunReadCommandAsync("doctor", json, pipeClient, cacheReader, session, paths, hostLaunchInfo, cancellationToken),
            "autostart" => await RunAutostartAsync(args.Skip(1).ToArray(), json, autostartManager, hostLaunchInfo, cancellationToken),
            "init-config" => await RunInitConfigAsync(args.Skip(1).ToArray(), json, migrator, paths, cancellationToken),
            _ => WriteUnknownCommand(command)
        };
    }

    private async Task<int> RunMutatingCommandAsync(
        string command,
        bool json,
        AgentPipeClient pipeClient,
        CacheReportReader cacheReader,
        CurrentSessionContext session,
        AgentPaths paths,
        HostLaunchInfo hostLaunchInfo,
        CancellationToken cancellationToken)
    {
        var conflict = GetCrossSessionConflict(paths, session);
        if (conflict is not null)
        {
            return WriteResponse(
                new AgentResponse
                {
                    Success = false,
                    Message = conflict,
                    StatusSource = "cache",
                    HostReachable = false,
                    Issues = [conflict]
                },
                json);
        }

        var liveResponse = await pipeClient.TrySendAsync(command, cancellationToken);
        if (liveResponse is not null)
        {
            return WriteResponse(liveResponse, json);
        }

        await StartHostAsync(hostLaunchInfo, command == "restart" ? "cli-restart" : "cli-start");
        var waitDeadline = DateTimeOffset.UtcNow.AddSeconds(10);
        while (DateTimeOffset.UtcNow < waitDeadline)
        {
            await Task.Delay(500, cancellationToken);
            liveResponse = await pipeClient.TrySendAsync("status", cancellationToken);
            if (liveResponse is not null)
            {
                if (command == "restart")
                {
                    liveResponse.Message = "Host was not running; restart was treated as start.";
                }

                return WriteResponse(liveResponse, json);
            }
        }

        var cacheResponse = cacheReader.ReadStatus(doctor: false, paths, hostLaunchInfo.ExpectedHostExecutablePath, session.SessionId);
        cacheResponse.Issues.Insert(0, "Host did not become reachable within 10 seconds.");
        cacheResponse.Message = cacheResponse.Issues[0];
        cacheResponse.Success = false;
        return WriteResponse(cacheResponse, json);
    }

    private async Task<int> RunStopAsync(
        bool json,
        AgentPipeClient pipeClient,
        CacheReportReader cacheReader,
        CurrentSessionContext session,
        AgentPaths paths,
        HostLaunchInfo hostLaunchInfo,
        CancellationToken cancellationToken)
    {
        var liveResponse = await pipeClient.TrySendAsync("stop", cancellationToken);
        if (liveResponse is not null)
        {
            return WriteResponse(liveResponse, json);
        }

        var cacheResponse = cacheReader.ReadStatus(doctor: false, paths, hostLaunchInfo.ExpectedHostExecutablePath, session.SessionId);
        cacheResponse.Success = true;
        cacheResponse.Message = "Host is not running. OpenClaw is already stopped.";
        cacheResponse.Issues = [];
        cacheResponse.Warnings = [];
        cacheResponse.State.Current = AgentState.Stopped.ToString();
        cacheResponse.State.Desired = AgentState.Stopped.ToString();
        return WriteResponse(cacheResponse, json);
    }

    private async Task<int> RunReadCommandAsync(
        string command,
        bool json,
        AgentPipeClient pipeClient,
        CacheReportReader cacheReader,
        CurrentSessionContext session,
        AgentPaths paths,
        HostLaunchInfo hostLaunchInfo,
        CancellationToken cancellationToken)
    {
        var liveResponse = await pipeClient.TrySendAsync(command, cancellationToken);
        if (liveResponse is not null)
        {
            return WriteResponse(liveResponse, json);
        }

        var cached = cacheReader.ReadStatus(command == "doctor", paths, hostLaunchInfo.ExpectedHostExecutablePath, session.SessionId);
        return WriteResponse(cached, json);
    }

    private Task<int> RunAutostartAsync(
        string[] args,
        bool json,
        AutostartManager autostartManager,
        HostLaunchInfo hostLaunchInfo,
        CancellationToken cancellationToken)
    {
        if (args.Length == 0)
        {
            WriteUsage();
            return Task.FromResult(1);
        }

        AutostartStatus status;
        switch (args[0].ToLowerInvariant())
        {
            case "enable":
                status = autostartManager.Enable(hostLaunchInfo.ExpectedHostExecutablePath);
                break;
            case "disable":
                autostartManager.Disable();
                status = autostartManager.GetStatus(hostLaunchInfo.ExpectedHostExecutablePath);
                break;
            case "status":
                status = autostartManager.GetStatus(hostLaunchInfo.ExpectedHostExecutablePath);
                break;
            default:
                WriteUsage();
                return Task.FromResult(1);
        }

        var response = new AgentResponse
        {
            Success = args[0].Equals("disable", StringComparison.OrdinalIgnoreCase) || status.PathMatches || !status.Enabled,
            Message = status.Enabled
                ? status.PathMatches ? "Autostart is enabled." : "Autostart is enabled but the registry value does not match the expected host path."
                : "Autostart is disabled.",
            HostReachable = false,
            StatusSource = "cache",
            Autostart = new AutostartPayload
            {
                Enabled = status.Enabled,
                PathMatches = status.PathMatches,
                RegistryValue = status.RegistryValue,
                ExpectedValue = status.ExpectedValue
            }
        };

        return Task.FromResult(WriteResponse(response, json));
    }

    private Task<int> RunInitConfigAsync(
        string[] args,
        bool json,
        WrapperConfigMigrator migrator,
        AgentPaths paths,
        CancellationToken cancellationToken)
    {
        var wrapperPath = default(string);
        var force = args.Any(argument => string.Equals(argument, "--force", StringComparison.OrdinalIgnoreCase));

        for (var index = 0; index < args.Length; index++)
        {
            if (string.Equals(args[index], "--from-wrapper", StringComparison.OrdinalIgnoreCase) && index + 1 < args.Length)
            {
                wrapperPath = args[index + 1];
                index++;
            }
        }

        if (string.IsNullOrWhiteSpace(wrapperPath))
        {
            _error.WriteLine("init-config requires --from-wrapper <path>.");
            WriteUsage();
            return Task.FromResult(1);
        }

        try
        {
            var result = migrator.InitializeConfig(wrapperPath, paths.ConfigPath, force);
            return Task.FromResult(WriteInitConfigResponse(result, json));
        }
        catch (Exception ex)
        {
            if (json)
            {
                _output.WriteLine(AgentJson.Serialize(new InitConfigPayload
                {
                    Success = false,
                    Message = ex.Message,
                    SourcePath = Path.GetFullPath(wrapperPath),
                    OutputPath = paths.ConfigPath
                }));
            }
            else
            {
                _error.WriteLine(ex.Message);
            }

            return Task.FromResult(1);
        }
    }

    private static async Task StartHostAsync(HostLaunchInfo hostLaunchInfo, string source)
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
        await Task.CompletedTask;
    }

    private static string? GetCrossSessionConflict(AgentPaths paths, CurrentSessionContext session)
    {
        var store = new FileStateStore();
        var hostState = store.Read<HostStateRecord>(paths.HostStatePath);
        if (hostState is null)
        {
            return null;
        }

        if (hostState.SessionId != 0
            && hostState.SessionId != session.SessionId
            && hostState.HostProcessId > 0
            && ProcessUtilities.ProcessExists(hostState.HostProcessId))
        {
            return $"An active host is already running in session {hostState.SessionId}. Phase 1 does not support multiple interactive sessions for the same Windows user.";
        }

        return null;
    }

    private int WriteResponse(AgentResponse response, bool json)
    {
        if (json)
        {
            _output.WriteLine(AgentJson.Serialize(response));
        }
        else
        {
            _output.WriteLine($"Success      : {response.Success}");
            _output.WriteLine($"Message      : {response.Message}");
            _output.WriteLine($"Source       : {response.StatusSource}");
            _output.WriteLine($"HostReachable: {response.HostReachable}");
            _output.WriteLine($"State        : {response.State.Current}");
            _output.WriteLine($"Desired      : {response.State.Desired}");
            _output.WriteLine($"Reason       : {response.State.Reason}");
            _output.WriteLine($"SessionId    : {response.State.SessionId}");
            _output.WriteLine($"Host PID     : {response.State.HostProcessId}");
            _output.WriteLine($"OpenClaw PID : {response.State.OpenClawProcessId}");
            _output.WriteLine($"Health       : {(response.Health.Ok ? "OK" : "FAIL")}");
            _output.WriteLine($"Config       : {response.Paths.ConfigPath}");
            _output.WriteLine($"Agent Log    : {response.Paths.AgentLogPath}");

            if (response.Issues.Count > 0)
            {
                _output.WriteLine("Issues       :");
                foreach (var issue in response.Issues)
                {
                    _output.WriteLine($"  - {issue}");
                }
            }

            if (response.Warnings.Count > 0)
            {
                _output.WriteLine("Warnings     :");
                foreach (var warning in response.Warnings)
                {
                    _output.WriteLine($"  - {warning}");
                }
            }

            if (response.Autostart is not null)
            {
                _output.WriteLine($"Autostart    : {(response.Autostart.Enabled ? "enabled" : "disabled")}");
                _output.WriteLine($"PathMatches  : {response.Autostart.PathMatches}");
            }
        }

        return response.Success ? 0 : 1;
    }

    private int WriteUnknownCommand(string command)
    {
        _error.WriteLine($"Unknown command '{command}'.");
        WriteUsage();
        return 1;
    }

    private int WriteInitConfigResponse(InitConfigResult result, bool json)
    {
        if (json)
        {
            _output.WriteLine(AgentJson.Serialize(new InitConfigPayload
            {
                Success = result.Success,
                Message = result.Message,
                SourcePath = result.SourcePath,
                OutputPath = result.OutputPath,
                RetainedFields = result.RetainedFields,
                RetiredFields = result.RetiredFields,
                Warnings = result.Warnings
            }));
        }
        else
        {
            _output.WriteLine($"Success      : {result.Success}");
            _output.WriteLine($"Message      : {result.Message}");
            _output.WriteLine($"SourcePath   : {result.SourcePath}");
            _output.WriteLine($"OutputPath   : {result.OutputPath}");
            if (result.RetainedFields.Count > 0)
            {
                _output.WriteLine($"Retained     : {string.Join(", ", result.RetainedFields)}");
            }

            if (result.RetiredFields.Count > 0)
            {
                _output.WriteLine($"Retired      : {string.Join(", ", result.RetiredFields)}");
            }

            if (result.Warnings.Count > 0)
            {
                _output.WriteLine($"Warnings     : {string.Join(" | ", result.Warnings)}");
            }
        }

        return result.Success ? 0 : 1;
    }

    private void WriteUsage()
    {
        _output.WriteLine("Usage:");
        _output.WriteLine("  OpenClaw.Agent.Cli start");
        _output.WriteLine("  OpenClaw.Agent.Cli stop");
        _output.WriteLine("  OpenClaw.Agent.Cli restart");
        _output.WriteLine("  OpenClaw.Agent.Cli status [--json]");
        _output.WriteLine("  OpenClaw.Agent.Cli doctor [--json]");
        _output.WriteLine("  OpenClaw.Agent.Cli autostart enable|disable|status [--json]");
        _output.WriteLine("  OpenClaw.Agent.Cli init-config --from-wrapper <path> [--force] [--json]");
    }
}
