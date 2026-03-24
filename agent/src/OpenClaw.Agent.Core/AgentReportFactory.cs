using OpenClaw.Agent.Protocol;

namespace OpenClaw.Agent.Core;

public static class AgentReportFactory
{
    public static AgentResponse CreateStatusReport(
        AgentPaths paths,
        HostStateRecord? hostState,
        RunStateRecord? runState,
        AgentConfig? config,
        AutostartStatus autostartStatus,
        bool hostReachable,
        string statusSource,
        List<string> issues,
        List<string> warnings)
    {
        var state = hostState?.State ?? AgentState.Stopped;
        var success = issues.Count == 0 && state is not AgentState.Failed;

        return new AgentResponse
        {
            Success = success,
            Message = BuildMessage(state, hostReachable, issues),
            StatusSource = statusSource,
            HostReachable = hostReachable,
            State = new AgentStatePayload
            {
                Current = state.ToString(),
                Desired = (hostState?.DesiredState ?? AgentState.Stopped).ToString(),
                Reason = hostState?.Reason?.ToString(),
                ObservedAt = DateTimeOffset.UtcNow.ToString("O"),
                StateFileUpdatedAt = hostState?.UpdatedAt.ToString("O"),
                HostProcessId = hostState?.HostProcessId ?? 0,
                OpenClawProcessId = hostState?.OpenClawProcessId ?? 0,
                SessionId = hostState?.SessionId ?? 0
            },
            Health = ToHealthPayload(runState?.LastHealth),
            Issues = issues,
            Warnings = warnings,
            Paths = ToPathsPayload(paths),
            Process = new AgentProcessPayload
            {
                Executable = runState?.EffectiveExecutable,
                Arguments = runState?.EffectiveArguments ?? [],
                WorkingDirectory = runState?.WorkingDirectory,
                LastObservedListeners = runState?.LastObservedListeners ?? []
            },
            Config = ToConfigPayload(config),
            Autostart = ToAutostartPayload(autostartStatus),
            LastExit = new ExitPayload
            {
                Reason = hostState?.Reason?.ToString(),
                ExitCode = hostState?.LastExitCode,
                ChildStoppedAt = runState?.ChildStoppedAt?.ToString("O")
            }
        };
    }

    public static AgentResponse CreateDoctorReport(
        AgentPaths paths,
        HostStateRecord? hostState,
        RunStateRecord? runState,
        AgentConfig? config,
        AutostartStatus autostartStatus,
        bool hostReachable,
        string statusSource,
        List<string> issues,
        List<string> warnings)
    {
        var response = CreateStatusReport(paths, hostState, runState, config, autostartStatus, hostReachable, statusSource, issues, warnings);
        response.Message = hostReachable ? "Diagnostic report collected from the live host." : "Diagnostic report collected from cached files.";
        return response;
    }

    public static List<string> BuildIssues(
        HostStateRecord? hostState,
        RunStateRecord? runState,
        AgentConfig? config,
        bool hostReachable,
        bool configLoadFailed,
        string? configError)
    {
        var issues = new List<string>();

        if (configLoadFailed && !string.IsNullOrWhiteSpace(configError))
        {
            issues.Add(configError);
        }

        if (!hostReachable)
        {
            issues.Add("Host is not reachable; report is based on cached state.");
        }

        if (hostState?.State == AgentState.Failed)
        {
            issues.Add("Host reported a failed state.");
        }

        if (runState?.LastHealth is { Ok: false, Error: not null } health)
        {
            issues.Add($"Health probe is failing: {health.Error}");
        }

        if (config is not null && !File.Exists(config.OpenClaw.ConfigPath))
        {
            issues.Add($"OpenClaw config file does not exist: {config.OpenClaw.ConfigPath}");
        }

        return issues.Distinct(StringComparer.OrdinalIgnoreCase).ToList();
    }

    public static List<string> BuildWarnings(HostStateRecord? hostState, RunStateRecord? runState)
    {
        var warnings = new List<string>();

        if (hostState?.State == AgentState.Degraded)
        {
            warnings.Add("Host is running in a degraded state.");
        }

        if ((hostState?.State == AgentState.Running || hostState?.State == AgentState.Degraded)
            && hostState.OpenClawProcessId > 0
            && !ProcessUtilities.ProcessExists(hostState.OpenClawProcessId))
        {
            warnings.Add("Cached state says OpenClaw is running, but the recorded process is no longer alive.");
        }

        if (runState?.LastObservedListeners.Count == 0 && hostState?.State == AgentState.Running)
        {
            warnings.Add("No active listener was observed for the configured port.");
        }

        return warnings.Distinct(StringComparer.OrdinalIgnoreCase).ToList();
    }

    private static string BuildMessage(AgentState state, bool hostReachable, IReadOnlyCollection<string> issues)
    {
        if (!hostReachable)
        {
            return issues.Count == 0 ? "Host is not running." : issues.First();
        }

        return state switch
        {
            AgentState.Running => "OpenClaw host is running.",
            AgentState.Starting => "OpenClaw host is starting.",
            AgentState.Stopping => "OpenClaw host is stopping.",
            AgentState.Degraded => "OpenClaw host is running with degraded health.",
            AgentState.Failed => "OpenClaw host is in a failed state.",
            _ => "OpenClaw host is stopped."
        };
    }

    private static AgentHealthPayload ToHealthPayload(HealthSnapshot? snapshot)
    {
        return new AgentHealthPayload
        {
            Ok = snapshot?.Ok ?? false,
            StatusCode = snapshot?.StatusCode,
            Body = snapshot?.Body,
            Error = snapshot?.Error,
            ObservedAt = snapshot?.ObservedAt.ToString("O")
        };
    }

    private static AgentPathsPayload ToPathsPayload(AgentPaths paths)
    {
        return new AgentPathsPayload
        {
            DataRoot = paths.DataRoot,
            ConfigPath = paths.ConfigPath,
            HostStatePath = paths.HostStatePath,
            RunStatePath = paths.RunStatePath,
            AgentLogPath = paths.AgentLogPath,
            StdOutLogPath = paths.StdOutLogPath,
            StdErrLogPath = paths.StdErrLogPath
        };
    }

    private static AgentConfigPayload? ToConfigPayload(AgentConfig? config)
    {
        if (config is null)
        {
            return null;
        }

        return new AgentConfigPayload
        {
            Bind = config.Network.Bind,
            Port = config.Network.Port,
            Executable = config.OpenClaw.Executable,
            Arguments = config.OpenClaw.Arguments,
            WorkingDirectory = config.OpenClaw.WorkingDirectory,
            OpenClawConfigPath = config.OpenClaw.ConfigPath
        };
    }

    private static AutostartPayload ToAutostartPayload(AutostartStatus status)
    {
        return new AutostartPayload
        {
            Enabled = status.Enabled,
            PathMatches = status.PathMatches,
            RegistryValue = status.RegistryValue,
            ExpectedValue = status.ExpectedValue
        };
    }
}
