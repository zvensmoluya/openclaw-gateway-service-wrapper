namespace OpenClaw.Agent.Core;

public static class AgentConstants
{
    public const string DataRootOverrideEnvironmentVariable = "OPENCLAW_AGENT_DATA_ROOT";
    public const string HostPathOverrideEnvironmentVariable = "OPENCLAW_AGENT_HOST_PATH";
    public const string DefaultConfigFileName = "agent.json";
    public const string HostExecutableName = "OpenClaw.Agent.Host.exe";
    public const string HostDllName = "OpenClaw.Agent.Host.dll";
    public const string CliExecutableName = "OpenClaw.Agent.Cli.exe";
    public const string AutostartRegistryKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    public const string AutostartRegistryValueName = "OpenClaw.Agent.Host";
    public const string DefaultBind = "loopback";
    public const int DefaultPort = 18789;
    public const string HealthPath = "/health";
    public static readonly string[] StablePublishTail = ["dist", "v2", "win-x64", "current"];
}
