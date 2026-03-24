using OpenClaw.Agent.Protocol;

namespace OpenClaw.Agent.Core;

public sealed class CacheReportReader
{
    private readonly AgentConfigLoader _configLoader;
    private readonly FileStateStore _fileStateStore;
    private readonly AutostartManager _autostartManager;

    public CacheReportReader(
        AgentConfigLoader? configLoader = null,
        FileStateStore? fileStateStore = null,
        AutostartManager? autostartManager = null)
    {
        _configLoader = configLoader ?? new AgentConfigLoader();
        _fileStateStore = fileStateStore ?? new FileStateStore();
        _autostartManager = autostartManager ?? new AutostartManager();
    }

    public AgentResponse ReadStatus(bool doctor, AgentPaths paths, string expectedHostPath, int currentSessionId)
    {
        AgentConfig? config = null;
        var configError = default(string);
        var configLoadFailed = false;
        try
        {
            config = _configLoader.Load(paths);
        }
        catch (Exception ex)
        {
            configError = ex.Message;
            configLoadFailed = true;
        }

        var hostState = _fileStateStore.Read<HostStateRecord>(paths.HostStatePath);
        var runState = _fileStateStore.Read<RunStateRecord>(paths.RunStatePath);
        var hostReachable = false;
        var issues = AgentReportFactory.BuildIssues(hostState, runState, config, hostReachable, configLoadFailed, configError);
        var warnings = AgentReportFactory.BuildWarnings(hostState, runState);

        if (hostState is not null && hostState.SessionId != 0 && hostState.SessionId != currentSessionId && ProcessUtilities.ProcessExists(hostState.HostProcessId))
        {
            issues.Insert(0, $"An active host is already running in session {hostState.SessionId}. Phase 1 does not support multiple interactive sessions for the same Windows user.");
        }

        var autostartStatus = _autostartManager.GetStatus(expectedHostPath);
        return doctor
            ? AgentReportFactory.CreateDoctorReport(paths, hostState, runState, config, autostartStatus, hostReachable, "cache", issues, warnings)
            : AgentReportFactory.CreateStatusReport(paths, hostState, runState, config, autostartStatus, hostReachable, "cache", issues, warnings);
    }
}
