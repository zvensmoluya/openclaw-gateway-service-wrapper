using System.Diagnostics;
using OpenClaw.Agent.Protocol;

namespace OpenClaw.Agent.Core;

public sealed class AgentRuntime : IAsyncDisposable
{
    private readonly AgentPaths _paths;
    private readonly CurrentSessionContext _session;
    private readonly AgentConfigLoader _configLoader;
    private readonly FileStateStore _stateStore;
    private readonly AgentLogWriter _logWriter;
    private readonly HealthChecker _healthChecker;
    private readonly AutostartManager _autostartManager;
    private readonly OpenClawCommandResolver _commandResolver;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private readonly DateTimeOffset _hostStartedAt = DateTimeOffset.UtcNow;
    private readonly string _hostExecutablePath;
    private readonly TimeSpan _healthPollInterval;
    private readonly TimeSpan _startupGracePeriod;

    private ActiveProcessContext? _activeProcess;
    private AgentConfig? _lastConfig;
    private string? _lastConfigError;

    public AgentRuntime(
        AgentPaths paths,
        CurrentSessionContext session,
        string hostExecutablePath,
        AgentConfigLoader? configLoader = null,
        FileStateStore? stateStore = null,
        AgentLogWriter? logWriter = null,
        HealthChecker? healthChecker = null,
        AutostartManager? autostartManager = null,
        OpenClawCommandResolver? commandResolver = null,
        TimeSpan? healthPollInterval = null,
        TimeSpan? startupGracePeriod = null)
    {
        _paths = paths;
        _session = session;
        _hostExecutablePath = hostExecutablePath;
        _configLoader = configLoader ?? new AgentConfigLoader();
        _stateStore = stateStore ?? new FileStateStore();
        _logWriter = logWriter ?? new AgentLogWriter(paths.AgentLogPath);
        _healthChecker = healthChecker ?? new HealthChecker();
        _autostartManager = autostartManager ?? new AutostartManager();
        _commandResolver = commandResolver ?? new OpenClawCommandResolver();
        _healthPollInterval = healthPollInterval ?? TimeSpan.FromSeconds(2);
        _startupGracePeriod = startupGracePeriod ?? TimeSpan.FromSeconds(30);
    }

    public async Task InitializeAsync(string launchSource, CancellationToken cancellationToken)
    {
        PathHelpers.EnsureDataDirectories(_paths);
        EnsureNoCrossSessionConflict();
        await _logWriter.WriteAsync("INFO", $"Host initializing in session {_session.SessionId} as '{_session.UserName}'.", cancellationToken);
        await UpdateHostStateAsync(AgentState.Stopped, AgentState.Running, reason: null, lastCommandSource: launchSource, cancellationToken: cancellationToken);
        await StartAsync(launchSource, cancellationToken);
    }

    public async Task<AgentResponse> StartAsync(string source, CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            if (_activeProcess is not null && !_activeProcess.Process.HasExited)
            {
                return BuildLiveReport(hostReachable: true, doctor: false);
            }

            try
            {
                _lastConfig = _configLoader.Load(_paths);
                _lastConfigError = null;
            }
            catch (Exception ex)
            {
                _lastConfig = null;
                _lastConfigError = ex.Message;
                await _logWriter.WriteAsync("ERROR", ex.Message, cancellationToken);
                await UpdateHostStateAsync(AgentState.Failed, AgentState.Running, null, source, cancellationToken);
                return BuildLiveReport(hostReachable: true, doctor: false);
            }

            var resolved = _commandResolver.Resolve(_lastConfig);
            await UpdateHostStateAsync(AgentState.Starting, AgentState.Running, null, source, cancellationToken);
            WriteRunState(new RunStateRecord
            {
                EffectiveExecutable = resolved.ResolvedExecutablePath,
                EffectiveArguments = resolved.EffectiveArguments,
                WorkingDirectory = resolved.WorkingDirectory,
                ConfigPath = resolved.OpenClawConfigPath,
                Port = _lastConfig.Network.Port,
                HealthUrl = resolved.HealthUrl,
                ChildStartedAt = null,
                ChildStoppedAt = null,
                LastHealth = null,
                LastObservedListeners = []
            });

            var startInfo = ProcessUtilities.CreateStartInfo(resolved, _lastConfig, _paths);
            var process = Process.Start(startInfo) ?? throw new InvalidOperationException("Failed to start the OpenClaw process.");
            var context = new ActiveProcessContext
            {
                Process = process,
                ResolvedCommand = resolved
            };

            _activeProcess = context;
            WriteRunState(new RunStateRecord
            {
                EffectiveExecutable = resolved.ResolvedExecutablePath,
                EffectiveArguments = resolved.EffectiveArguments,
                WorkingDirectory = resolved.WorkingDirectory,
                ConfigPath = resolved.OpenClawConfigPath,
                Port = _lastConfig.Network.Port,
                HealthUrl = resolved.HealthUrl,
                ChildStartedAt = DateTimeOffset.UtcNow,
                ChildStoppedAt = null,
                LastHealth = null,
                LastObservedListeners = []
            });
            await UpdateHostStateAsync(AgentState.Starting, AgentState.Running, null, source, cancellationToken, openClawProcessId: process.Id);

            context.StdOutTask = ProcessUtilities.CopyToLogAsync(process.StandardOutput, _paths.StdOutLogPath, context.StreamCancellationTokenSource.Token);
            context.StdErrTask = ProcessUtilities.CopyToLogAsync(process.StandardError, _paths.StdErrLogPath, context.StreamCancellationTokenSource.Token);
            context.ExitMonitorTask = MonitorProcessExitAsync(context);
            context.HealthMonitorTask = MonitorHealthAsync(context);

            await _logWriter.WriteAsync("INFO", $"Started OpenClaw process {process.Id} using '{resolved.ResolvedExecutablePath}'.", cancellationToken);
            return BuildLiveReport(hostReachable: true, doctor: false);
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task<AgentResponse> StopAsync(ExitReason reason, string source, CancellationToken cancellationToken)
    {
        ActiveProcessContext? context;
        await _gate.WaitAsync(cancellationToken);
        try
        {
            context = _activeProcess;
            if (context is null || context.Process.HasExited)
            {
                await UpdateHostStateAsync(AgentState.Stopped, AgentState.Stopped, reason, source, cancellationToken);
                return BuildLiveReport(hostReachable: true, doctor: false);
            }

            context.PlannedExitReason = reason;
            await UpdateHostStateAsync(AgentState.Stopping, AgentState.Stopped, reason, source, cancellationToken, openClawProcessId: context.Process.Id);
        }
        finally
        {
            _gate.Release();
        }

        await ProcessUtilities.KillProcessTreeAsync(context.Process.Id, cancellationToken);
        await context.ExitHandled.Task.WaitAsync(cancellationToken);
        return BuildLiveReport(hostReachable: true, doctor: false);
    }

    public async Task<AgentResponse> RestartAsync(string source, CancellationToken cancellationToken)
    {
        if (_activeProcess is null || _activeProcess.Process.HasExited)
        {
            return await StartAsync(source, cancellationToken);
        }

        await StopAsync(ExitReason.UserRestart, source, cancellationToken);
        return await StartAsync(source, cancellationToken);
    }

    public Task<AgentResponse> GetStatusAsync(CancellationToken cancellationToken)
    {
        return Task.FromResult(BuildLiveReport(hostReachable: true, doctor: false));
    }

    public Task<AgentResponse> GetDoctorAsync(CancellationToken cancellationToken)
    {
        return Task.FromResult(BuildLiveReport(hostReachable: true, doctor: true));
    }

    public async Task HandleSessionSignOutAsync(CancellationToken cancellationToken)
    {
        await _logWriter.WriteAsync("INFO", "Handling session sign-out.", cancellationToken);
        await StopAsync(ExitReason.SessionSignOut, "session-sign-out", cancellationToken);
    }

    public async Task ShutdownAsync(CancellationToken cancellationToken)
    {
        await _logWriter.WriteAsync("INFO", "Host shutdown requested.", cancellationToken);
        if (_activeProcess is not null && !_activeProcess.Process.HasExited)
        {
            await StopAsync(ExitReason.HostShutdown, "host-shutdown", cancellationToken);
        }
    }

    public async ValueTask DisposeAsync()
    {
        if (_activeProcess is not null)
        {
            _activeProcess.StreamCancellationTokenSource.Cancel();
        }

        _gate.Dispose();
        await Task.CompletedTask;
    }

    private AgentResponse BuildLiveReport(bool hostReachable, bool doctor)
    {
        var hostState = _stateStore.Read<HostStateRecord>(_paths.HostStatePath);
        var runState = _stateStore.Read<RunStateRecord>(_paths.RunStatePath);
        var config = _lastConfig;
        var configLoadFailed = false;

        if (config is null && string.IsNullOrWhiteSpace(_lastConfigError))
        {
            try
            {
                config = _configLoader.Load(_paths);
            }
            catch (Exception ex)
            {
                _lastConfigError = ex.Message;
                configLoadFailed = true;
            }
        }
        else if (config is null)
        {
            configLoadFailed = true;
        }

        var autostartStatus = _autostartManager.GetStatus(_hostExecutablePath);
        var issues = AgentReportFactory.BuildIssues(hostState, runState, config, hostReachable, configLoadFailed, _lastConfigError);
        var warnings = AgentReportFactory.BuildWarnings(hostState, runState);

        return doctor
            ? AgentReportFactory.CreateDoctorReport(_paths, hostState, runState, config, autostartStatus, hostReachable, "live", issues, warnings)
            : AgentReportFactory.CreateStatusReport(_paths, hostState, runState, config, autostartStatus, hostReachable, "live", issues, warnings);
    }

    private void EnsureNoCrossSessionConflict()
    {
        var hostState = _stateStore.Read<HostStateRecord>(_paths.HostStatePath);
        if (hostState is null)
        {
            return;
        }

        if (hostState.SessionId != 0
            && hostState.SessionId != _session.SessionId
            && hostState.HostProcessId > 0
            && ProcessUtilities.ProcessExists(hostState.HostProcessId))
        {
            throw new InvalidOperationException(
                $"An active host is already running in session {hostState.SessionId}. Phase 1 does not support multiple interactive sessions for the same Windows user.");
        }
    }

    private void WriteRunState(RunStateRecord record)
    {
        _stateStore.Write(_paths.RunStatePath, record);
    }

    private async Task UpdateHostStateAsync(
        AgentState state,
        AgentState desiredState,
        ExitReason? reason,
        string lastCommandSource,
        CancellationToken cancellationToken,
        int? openClawProcessId = null,
        int? lastExitCode = null)
    {
        var status = _autostartManager.GetStatus(_hostExecutablePath);
        var record = _stateStore.Read<HostStateRecord>(_paths.HostStatePath) ?? new HostStateRecord
        {
            StartedAt = _hostStartedAt
        };

        record.State = state;
        record.DesiredState = desiredState;
        record.Reason = reason;
        record.HostProcessId = Environment.ProcessId;
        record.OpenClawProcessId = openClawProcessId ?? record.OpenClawProcessId;
        record.SessionId = _session.SessionId;
        record.UpdatedAt = DateTimeOffset.UtcNow;
        record.LastExitCode = lastExitCode ?? record.LastExitCode;
        record.LastCommandSource = lastCommandSource;
        record.AutostartEnabled = status.Enabled && status.PathMatches;

        _stateStore.Write(_paths.HostStatePath, record);
        await _logWriter.WriteAsync("INFO", $"State => {state}, desired => {desiredState}, reason => {reason?.ToString() ?? "none"}.", cancellationToken);
    }

    private async Task MonitorProcessExitAsync(ActiveProcessContext context)
    {
        try
        {
            await context.Process.WaitForExitAsync();
            var exitCode = context.Process.ExitCode;
            context.StreamCancellationTokenSource.Cancel();
            try
            {
                await Task.WhenAny(
                    Task.WhenAll(context.StdOutTask ?? Task.CompletedTask, context.StdErrTask ?? Task.CompletedTask),
                    Task.Delay(TimeSpan.FromSeconds(2)));
            }
            catch
            {
            }

            await _gate.WaitAsync();
            try
            {
                if (!ReferenceEquals(_activeProcess, context))
                {
                    context.ExitHandled.TrySetResult(new ExitObservation(context.PlannedExitReason ?? ExitReason.UnexpectedExit, exitCode, DateTimeOffset.UtcNow));
                    return;
                }

                _activeProcess = null;
                var reason = context.PlannedExitReason ?? ExitReason.UnexpectedExit;
                var finalState = reason == ExitReason.UnexpectedExit ? AgentState.Failed : AgentState.Stopped;
                var desiredState = reason == ExitReason.UserRestart ? AgentState.Running : AgentState.Stopped;
                var stoppedAt = DateTimeOffset.UtcNow;
                var runState = _stateStore.Read<RunStateRecord>(_paths.RunStatePath) ?? new RunStateRecord();
                runState.ChildStoppedAt = stoppedAt;
                _stateStore.Write(_paths.RunStatePath, runState);
                await UpdateHostStateAsync(finalState, desiredState, reason, "process-exit", CancellationToken.None, openClawProcessId: 0, lastExitCode: exitCode);
                context.ExitHandled.TrySetResult(new ExitObservation(reason, exitCode, stoppedAt));
            }
            finally
            {
                _gate.Release();
            }
        }
        catch (Exception ex)
        {
            await _logWriter.WriteAsync("ERROR", $"Process exit monitor failed: {ex}", CancellationToken.None);
            context.ExitHandled.TrySetException(ex);
        }
    }

    private async Task MonitorHealthAsync(ActiveProcessContext context)
    {
        try
        {
            var startTime = DateTimeOffset.UtcNow;
            while (!context.StreamCancellationTokenSource.IsCancellationRequested)
            {
                try
                {
                    await Task.Delay(_healthPollInterval, context.StreamCancellationTokenSource.Token);
                }
                catch (OperationCanceledException)
                {
                    break;
                }

                if (context.Process.HasExited)
                {
                    break;
                }

                var snapshot = await _healthChecker.CheckAsync(context.ResolvedCommand.HealthUrl, context.StreamCancellationTokenSource.Token);
                await _gate.WaitAsync();
                try
                {
                    if (!ReferenceEquals(_activeProcess, context))
                    {
                        break;
                    }

                    var runState = _stateStore.Read<RunStateRecord>(_paths.RunStatePath) ?? new RunStateRecord();
                    runState.LastHealth = snapshot;
                    runState.LastObservedListeners = snapshot.Ok
                        ? [$"127.0.0.1:{_lastConfig?.Network.Port ?? AgentConstants.DefaultPort}"]
                        : [];
                    _stateStore.Write(_paths.RunStatePath, runState);

                    var hostState = _stateStore.Read<HostStateRecord>(_paths.HostStatePath) ?? new HostStateRecord
                    {
                        StartedAt = _hostStartedAt
                    };

                    var timeSinceStart = DateTimeOffset.UtcNow - startTime;
                    if (snapshot.Ok)
                    {
                        hostState.State = AgentState.Running;
                        hostState.Reason = null;
                    }
                    else if (timeSinceStart >= _startupGracePeriod || hostState.State == AgentState.Running)
                    {
                        hostState.State = AgentState.Degraded;
                        hostState.Reason = ExitReason.HealthFailure;
                    }

                    hostState.UpdatedAt = DateTimeOffset.UtcNow;
                    hostState.HostProcessId = Environment.ProcessId;
                    hostState.OpenClawProcessId = context.Process.Id;
                    hostState.SessionId = _session.SessionId;
                    _stateStore.Write(_paths.HostStatePath, hostState);
                }
                finally
                {
                    _gate.Release();
                }
            }
        }
        catch (Exception ex)
        {
            await _logWriter.WriteAsync("ERROR", $"Health monitor failed: {ex}", CancellationToken.None);
        }
    }

    private sealed class ActiveProcessContext
    {
        public required Process Process { get; init; }
        public required ResolvedLaunchCommand ResolvedCommand { get; init; }
        public ExitReason? PlannedExitReason { get; set; }
        public CancellationTokenSource StreamCancellationTokenSource { get; } = new();
        public Task? StdOutTask { get; set; }
        public Task? StdErrTask { get; set; }
        public Task? ExitMonitorTask { get; set; }
        public Task? HealthMonitorTask { get; set; }
        public TaskCompletionSource<ExitObservation> ExitHandled { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
    }

    private sealed record ExitObservation(ExitReason Reason, int ExitCode, DateTimeOffset StoppedAt);
}
