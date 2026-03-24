namespace OpenClaw.Agent.Core;

public enum AgentState
{
    Stopped,
    Starting,
    Running,
    Stopping,
    Degraded,
    Failed
}

public enum ExitReason
{
    UserStop,
    UserRestart,
    UnexpectedExit,
    HostShutdown,
    SessionSignOut,
    HealthFailure
}

public enum ResolvedCommandKind
{
    Executable,
    CmdShim
}
