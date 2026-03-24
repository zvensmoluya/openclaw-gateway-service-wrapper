namespace OpenClaw.Agent.Protocol;

public sealed class AgentRequest
{
    public string Command { get; set; } = string.Empty;
}

public sealed class AgentResponse
{
    public bool Success { get; set; }
    public string Message { get; set; } = string.Empty;
    public string StatusSource { get; set; } = "live";
    public bool HostReachable { get; set; }
    public AgentStatePayload State { get; set; } = new();
    public AgentHealthPayload Health { get; set; } = new();
    public List<string> Issues { get; set; } = [];
    public List<string> Warnings { get; set; } = [];
    public AgentPathsPayload Paths { get; set; } = new();
    public AgentProcessPayload? Process { get; set; }
    public AgentConfigPayload? Config { get; set; }
    public AutostartPayload? Autostart { get; set; }
    public ExitPayload? LastExit { get; set; }
}

public sealed class AgentStatePayload
{
    public string Current { get; set; } = "Stopped";
    public string Desired { get; set; } = "Stopped";
    public string? Reason { get; set; }
    public string? ObservedAt { get; set; }
    public string? StateFileUpdatedAt { get; set; }
    public int HostProcessId { get; set; }
    public int OpenClawProcessId { get; set; }
    public int SessionId { get; set; }
}

public sealed class AgentHealthPayload
{
    public bool Ok { get; set; }
    public int? StatusCode { get; set; }
    public string? Body { get; set; }
    public string? Error { get; set; }
    public string? ObservedAt { get; set; }
}

public sealed class AgentPathsPayload
{
    public string DataRoot { get; set; } = string.Empty;
    public string ConfigPath { get; set; } = string.Empty;
    public string HostStatePath { get; set; } = string.Empty;
    public string RunStatePath { get; set; } = string.Empty;
    public string AgentLogPath { get; set; } = string.Empty;
    public string StdOutLogPath { get; set; } = string.Empty;
    public string StdErrLogPath { get; set; } = string.Empty;
}

public sealed class AgentProcessPayload
{
    public string? Executable { get; set; }
    public List<string> Arguments { get; set; } = [];
    public string? WorkingDirectory { get; set; }
    public List<string> LastObservedListeners { get; set; } = [];
}

public sealed class AgentConfigPayload
{
    public string Bind { get; set; } = "loopback";
    public int Port { get; set; }
    public string? Executable { get; set; }
    public List<string> Arguments { get; set; } = [];
    public string? WorkingDirectory { get; set; }
    public string? OpenClawConfigPath { get; set; }
}

public sealed class AutostartPayload
{
    public bool Enabled { get; set; }
    public bool PathMatches { get; set; }
    public string? RegistryValue { get; set; }
    public string? ExpectedValue { get; set; }
}

public sealed class ExitPayload
{
    public string? Reason { get; set; }
    public int? ExitCode { get; set; }
    public string? ChildStoppedAt { get; set; }
}
