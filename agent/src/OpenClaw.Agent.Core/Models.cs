namespace OpenClaw.Agent.Core;

public sealed class AgentConfig
{
    public OpenClawLaunchConfig OpenClaw { get; set; } = new();
    public NetworkConfig Network { get; set; } = new();
    public ProxyConfig Proxy { get; set; } = new();
}

public sealed class OpenClawLaunchConfig
{
    public string Executable { get; set; } = "openclaw.cmd";
    public List<string> Arguments { get; set; } = [];
    public string? WorkingDirectory { get; set; }
    public string ConfigPath { get; set; } = "%USERPROFILE%\\.openclaw\\openclaw.json";
}

public sealed class NetworkConfig
{
    public string Bind { get; set; } = AgentConstants.DefaultBind;
    public int Port { get; set; } = AgentConstants.DefaultPort;
}

public sealed class ProxyConfig
{
    public string? HttpProxy { get; set; }
    public string? HttpsProxy { get; set; }
    public string? AllProxy { get; set; }
    public string? NoProxy { get; set; }
}

public sealed class CurrentSessionContext
{
    public string UserSid { get; init; } = string.Empty;
    public string UserName { get; init; } = string.Empty;
    public int SessionId { get; init; }
}

public sealed class AgentPaths
{
    public string DataRoot { get; init; } = string.Empty;
    public string ConfigDirectory { get; init; } = string.Empty;
    public string StateDirectory { get; init; } = string.Empty;
    public string LogsDirectory { get; init; } = string.Empty;
    public string ConfigPath { get; init; } = string.Empty;
    public string HostStatePath { get; init; } = string.Empty;
    public string RunStatePath { get; init; } = string.Empty;
    public string AgentLogPath { get; init; } = string.Empty;
    public string StdOutLogPath { get; init; } = string.Empty;
    public string StdErrLogPath { get; init; } = string.Empty;
}

public sealed class ResolvedLaunchCommand
{
    public string ResolvedExecutablePath { get; init; } = string.Empty;
    public string WorkingDirectory { get; init; } = string.Empty;
    public ResolvedCommandKind CommandKind { get; init; }
    public List<string> EffectiveArguments { get; init; } = [];
    public string DisplayExecutable { get; init; } = string.Empty;
    public string HealthUrl { get; init; } = string.Empty;
    public string OpenClawConfigPath { get; init; } = string.Empty;
}

public sealed class HealthSnapshot
{
    public bool Ok { get; init; }
    public int? StatusCode { get; init; }
    public string? Body { get; init; }
    public string? Error { get; init; }
    public DateTimeOffset ObservedAt { get; init; } = DateTimeOffset.UtcNow;
}

public sealed class HostStateRecord
{
    public AgentState State { get; set; } = AgentState.Stopped;
    public AgentState DesiredState { get; set; } = AgentState.Stopped;
    public ExitReason? Reason { get; set; }
    public int HostProcessId { get; set; }
    public int OpenClawProcessId { get; set; }
    public int SessionId { get; set; }
    public DateTimeOffset StartedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
    public int? LastExitCode { get; set; }
    public string LastCommandSource { get; set; } = "manual";
    public bool AutostartEnabled { get; set; }
}

public sealed class RunStateRecord
{
    public string EffectiveExecutable { get; set; } = string.Empty;
    public List<string> EffectiveArguments { get; set; } = [];
    public string WorkingDirectory { get; set; } = string.Empty;
    public string ConfigPath { get; set; } = string.Empty;
    public int Port { get; set; }
    public string HealthUrl { get; set; } = string.Empty;
    public DateTimeOffset? ChildStartedAt { get; set; }
    public DateTimeOffset? ChildStoppedAt { get; set; }
    public HealthSnapshot? LastHealth { get; set; }
    public List<string> LastObservedListeners { get; set; } = [];
}

public sealed class AutostartStatus
{
    public bool Enabled { get; init; }
    public bool PathMatches { get; init; }
    public string? RegistryValue { get; init; }
    public string? ExpectedValue { get; init; }
}
