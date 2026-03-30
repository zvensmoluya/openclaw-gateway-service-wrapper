using System.Diagnostics;
using System.Drawing;
using System.Windows.Forms;
using OpenClaw.Agent.Core;
using OpenClaw.Agent.Protocol;

namespace OpenClaw.Agent.Tray;

internal static class Program
{
    [STAThread]
    private static int Main()
    {
        var session = PathHelpers.GetCurrentSession();
        var paths = PathHelpers.GetDefaultPaths();
        using var mutex = new Mutex(initiallyOwned: true, GetMutexName(session, paths.DataRoot), out var createdNew);
        if (!createdNew)
        {
            return 0;
        }

        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        using var context = new TrayApplicationContext(session, paths);
        Application.Run(context);
        return 0;
    }

    private static string GetMutexName(CurrentSessionContext session, string dataRoot)
    {
        return NamedPipeNames.GetTrayMutexName(session, dataRoot);
    }
}

internal sealed class TrayApplicationContext : ApplicationContext
{
    private readonly CurrentSessionContext _session;
    private readonly AgentPaths _paths;
    private readonly AgentPipeClient _pipeClient;
    private readonly CacheReportReader _cacheReportReader;
    private readonly AgentConfigLoader _configLoader;
    private readonly TrayIconResolver _iconResolver;
    private readonly TrayIssueReader _issueReader;
    private readonly TrayShellActions _shellActions;
    private readonly HostLaunchInfo _hostLaunchInfo;
    private readonly NotifyIcon _notifyIcon;
    private readonly ToolStripMenuItem _openDashboardItem;
    private readonly ToolStripMenuItem _startItem;
    private readonly ToolStripMenuItem _stopItem;
    private readonly ToolStripMenuItem _restartItem;
    private readonly ToolStripMenuItem _refreshItem;
    private readonly ToolStripMenuItem _openLogsItem;
    private readonly ToolStripMenuItem _openConfigItem;
    private readonly ToolStripMenuItem _exitItem;
    private readonly ContextMenuStrip _menu;
    private readonly System.Windows.Forms.Timer _refreshTimer;
    private readonly Dictionary<string, Icon> _iconCache = new(StringComparer.OrdinalIgnoreCase);
    private readonly string _expectedHostPath;

    private AgentConfig? _config;
    private string? _lastTrayState;
    private DateTimeOffset _lastRefreshAt = DateTimeOffset.MinValue;
    private bool _refreshInProgress;
    private TrayStatusForm? _statusForm;
    private string? _recentIssue;
    private DateTimeOffset _lastHostRecoveryAttemptAt = DateTimeOffset.MinValue;

    public TrayApplicationContext(CurrentSessionContext session, AgentPaths paths)
    {
        _session = session;
        _paths = paths;
        PathHelpers.EnsureDataDirectories(_paths);
        _pipeClient = new AgentPipeClient(session, _paths.DataRoot);
        _cacheReportReader = new CacheReportReader();
        _configLoader = new AgentConfigLoader();
        _iconResolver = new TrayIconResolver(AppContext.BaseDirectory);
        _issueReader = new TrayIssueReader();
        _shellActions = new TrayShellActions();
        _hostLaunchInfo = HostLocator.ResolveFromCliBaseDirectory(AppContext.BaseDirectory);
        _expectedHostPath = Path.Combine(PathHelpers.GetCurrentInstallDirectory(), AgentConstants.HostExecutableName);

        _menu = new ContextMenuStrip();
        _menu.Opening += OnMenuOpening;

        _openDashboardItem = AddItem("Open Dashboard", (_, _) => OpenDashboard());
        _startItem = AddItem("Start", (_, _) => _ = RunActionAsync("start"));
        _stopItem = AddItem("Stop", (_, _) => _ = RunActionAsync("stop"));
        _restartItem = AddItem("Restart", (_, _) => _ = RunActionAsync("restart"));
        _refreshItem = AddItem("Refresh", (_, _) => _ = RefreshStatusAsync(force: true));
        _openLogsItem = AddItem("Open Logs", (_, _) => OpenLogs());
        _openConfigItem = AddItem("Open Config", (_, _) => OpenConfig());
        _menu.Items.Add(new ToolStripSeparator());
        _exitItem = AddItem("Exit Tray", (_, _) => ExitThread());

        var initialIcon = ResolveIcon("stopped");
        _notifyIcon = new NotifyIcon
        {
            Icon = initialIcon,
            Visible = true,
            ContextMenuStrip = _menu,
            Text = "OpenClaw"
        };
        _notifyIcon.DoubleClick += (_, _) => ShowStatusWindow();

        _refreshTimer = new System.Windows.Forms.Timer();
        _refreshTimer.Tick += async (_, _) => await RefreshStatusAsync(force: false);

        _ = RefreshStatusAsync(force: true);
    }

    protected override void ExitThreadCore()
    {
        _refreshTimer.Stop();
        if (_statusForm is not null)
        {
            _statusForm.FormClosing -= OnStatusFormClosing;
            _statusForm.Close();
            _statusForm.Dispose();
        }
        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
        _menu.Dispose();
        foreach (var icon in _iconCache.Values)
        {
            icon.Dispose();
        }

        _refreshTimer.Dispose();
        base.ExitThreadCore();
    }

    private ToolStripMenuItem AddItem(string text, EventHandler handler)
    {
        var item = new ToolStripMenuItem(text);
        item.Click += handler;
        _menu.Items.Add(item);
        return item;
    }

    private async void OnMenuOpening(object? sender, System.ComponentModel.CancelEventArgs e)
    {
        var menuAge = GetTrayConfig().Refresh.MenuSeconds;
        if (DateTimeOffset.UtcNow - _lastRefreshAt > TimeSpan.FromSeconds(menuAge))
        {
            await RefreshStatusAsync(force: true);
        }
    }

    private async Task RunActionAsync(string command)
    {
        var response = await _pipeClient.TrySendAsync(command, CancellationToken.None);
        if (response is null)
        {
            if (command is "start" or "restart")
            {
                var cached = _cacheReportReader.ReadStatus(false, _paths, _expectedHostPath, _session.SessionId);
                await RecoverHostAsync(cached, command == "restart" ? "tray-restart" : "tray-start");
                await RefreshStatusAsync(force: true);
                return;
            }

            ShowNotification(
                "OpenClaw Tray",
                "Host is not reachable. Tray lifecycle actions only work when the background host is running.",
                ToolTipIcon.Warning,
                errorOnly: true);
            await RefreshStatusAsync(force: true);
            return;
        }

        UpdateFromResponse(response);
        ShowNotification("OpenClaw Tray", response.Message, response.Success ? ToolTipIcon.Info : ToolTipIcon.Warning, errorOnly: !response.Success);
        await RefreshStatusAsync(force: true);
    }

    private async Task RefreshStatusAsync(bool force)
    {
        if (_refreshInProgress)
        {
            return;
        }

        _refreshInProgress = true;
        try
        {
            TryLoadConfig();
            var response = await _pipeClient.TrySendAsync("status", CancellationToken.None)
                ?? _cacheReportReader.ReadStatus(false, _paths, _expectedHostPath, _session.SessionId);
            await TryRecoverHostAsync(response);
            response = await _pipeClient.TrySendAsync("status", CancellationToken.None)
                ?? _cacheReportReader.ReadStatus(false, _paths, _expectedHostPath, _session.SessionId);
            UpdateFromResponse(response);

            var intervalSeconds = SelectRefreshIntervalSeconds(response);
            if (force || _refreshTimer.Interval != intervalSeconds * 1000)
            {
                _refreshTimer.Interval = intervalSeconds * 1000;
            }

            if (!_refreshTimer.Enabled)
            {
                _refreshTimer.Start();
            }
        }
        finally
        {
            _lastRefreshAt = DateTimeOffset.UtcNow;
            _refreshInProgress = false;
        }
    }

    private void TryLoadConfig()
    {
        try
        {
            _config = _configLoader.Load(_paths);
        }
        catch
        {
            _config = null;
        }
    }

    private void UpdateFromResponse(AgentResponse response)
    {
        var trayState = MapTrayState(response);
        var title = GetTrayTitle();
        _recentIssue = _issueReader.GetRecentIssue(_paths, response);
        var nextIcon = ResolveIcon(trayState);
        if (!ReferenceEquals(_notifyIcon.Icon, nextIcon))
        {
            _notifyIcon.Icon = nextIcon;
        }

        _notifyIcon.Text = BuildTooltip(title, response);
        SetMenuState(response);
        EnsureStatusForm().UpdateView(response, _recentIssue, response.Config?.Port ?? AgentConstants.DefaultPort);

        if (!string.Equals(_lastTrayState, trayState, StringComparison.OrdinalIgnoreCase))
        {
            var showErrorOnly = trayState is "degraded" or "failed";
            var notificationText = string.IsNullOrWhiteSpace(_recentIssue) ? response.Message : _recentIssue!;
            ShowNotification(title, notificationText, showErrorOnly ? ToolTipIcon.Warning : ToolTipIcon.Info, errorOnly: showErrorOnly);
            _lastTrayState = trayState;
        }
    }

    private void SetMenuState(AgentResponse response)
    {
        var hostReachable = response.HostReachable;
        _openDashboardItem.Enabled = hostReachable;
        _startItem.Enabled = CanStart(response);
        _stopItem.Enabled = hostReachable && response.State.Current is not nameof(AgentState.Stopped) and not nameof(AgentState.Stopping);
        _restartItem.Enabled = CanRestart(response);
        _refreshItem.Enabled = true;
        _openLogsItem.Enabled = Directory.Exists(_paths.LogsDirectory);
        _openConfigItem.Enabled = File.Exists(_paths.ConfigPath);
        _exitItem.Enabled = true;
    }

    private int SelectRefreshIntervalSeconds(AgentResponse response)
    {
        var refresh = GetTrayConfig().Refresh;
        return response.State.Current is nameof(AgentState.Degraded) or nameof(AgentState.Failed) || !response.HostReachable
            ? refresh.FastSeconds
            : refresh.DeepSeconds;
    }

    private TrayConfig GetTrayConfig()
    {
        return _config?.Tray ?? new TrayConfig();
    }

    private string GetTrayTitle()
    {
        return string.IsNullOrWhiteSpace(GetTrayConfig().Title) ? "OpenClaw" : GetTrayConfig().Title!;
    }

    private string MapTrayState(AgentResponse response)
    {
        return response.State.Current switch
        {
            nameof(AgentState.Running) => "running",
            nameof(AgentState.Degraded) => "degraded",
            nameof(AgentState.Failed) => "failed",
            nameof(AgentState.Starting) => "starting",
            nameof(AgentState.Stopping) => "stopping",
            _ => "stopped"
        };
    }

    private Icon ResolveIcon(string trayState)
    {
        var configuredPath = _iconResolver.ResolveIconPath(GetTrayConfig(), trayState);
        if (!string.IsNullOrWhiteSpace(configuredPath))
        {
            return GetCachedIcon(configuredPath);
        }

        return _iconResolver.ResolveFallbackIcon(trayState);
    }

    private Icon GetCachedIcon(string path)
    {
        if (_iconCache.TryGetValue(path, out var icon))
        {
            return icon;
        }

        icon = new Icon(path);
        _iconCache[path] = icon;
        return icon;
    }

    private void OpenLogs()
    {
        _shellActions.OpenLogs(_paths.LogsDirectory);
    }

    private void OpenConfig()
    {
        _shellActions.OpenConfigDirectory(_paths.ConfigPath);
    }

    private void OpenDashboard()
    {
        _shellActions.OpenDashboard(_config?.Network.Port ?? AgentConstants.DefaultPort);
    }

    private static bool CanStart(AgentResponse response)
    {
        if (!response.HostReachable)
        {
            return response.State.Current is not nameof(AgentState.Stopping);
        }

        return response.State.Current is not nameof(AgentState.Running) and not nameof(AgentState.Starting);
    }

    private static bool CanRestart(AgentResponse response)
    {
        if (!response.HostReachable)
        {
            return response.State.Current is not nameof(AgentState.Stopping);
        }

        return response.State.Current is not nameof(AgentState.Starting) and not nameof(AgentState.Stopping);
    }

    private async Task TryRecoverHostAsync(AgentResponse response)
    {
        if (!ShouldRecoverHost(response))
        {
            return;
        }

        if (DateTimeOffset.UtcNow - _lastHostRecoveryAttemptAt < TimeSpan.FromSeconds(10))
        {
            return;
        }

        _lastHostRecoveryAttemptAt = DateTimeOffset.UtcNow;
        await RecoverHostAsync(response, "tray-autorecover");
        await Task.Delay(500);
    }

    private static bool ShouldRecoverHost(AgentResponse response)
    {
        if (response.HostReachable)
        {
            return false;
        }

        if (response.State.Desired == nameof(AgentState.Running))
        {
            return true;
        }

        return response.Autostart?.Enabled == true && response.State.Current is not nameof(AgentState.Stopped);
    }

    private async Task RecoverHostAsync(AgentResponse response, string source)
    {
        var hostProcessAlive = response.State.HostProcessId > 0 && ProcessUtilities.ProcessExists(response.State.HostProcessId);
        if (!hostProcessAlive && response.State.OpenClawProcessId > 0 && ProcessUtilities.ProcessExists(response.State.OpenClawProcessId))
        {
            try
            {
                await ProcessUtilities.KillProcessTreeAsync(response.State.OpenClawProcessId, CancellationToken.None);
            }
            catch
            {
            }
        }

        await HostBootstrapper.StartHostAsync(_hostLaunchInfo, source);
    }

    private void ShowStatusWindow()
    {
        EnsureStatusForm().ShowAndActivateWindow();
    }

    private TrayStatusForm EnsureStatusForm()
    {
        if (_statusForm is not null)
        {
            return _statusForm;
        }

        _statusForm = new TrayStatusForm(
            start: () => RunActionAsync("start"),
            stop: () => RunActionAsync("stop"),
            restart: () => RunActionAsync("restart"),
            refresh: () => RefreshStatusAsync(force: true),
            openDashboard: OpenDashboard,
            openLogs: OpenLogs,
            openConfig: OpenConfig);
        _statusForm.FormClosing += OnStatusFormClosing;
        return _statusForm;
    }

    private void OnStatusFormClosing(object? sender, FormClosingEventArgs e)
    {
        if (e.CloseReason == CloseReason.ApplicationExitCall)
        {
            return;
        }
    }

    private void ShowNotification(string title, string text, ToolTipIcon icon, bool errorOnly)
    {
        var notifications = GetTrayConfig().Notifications;
        if (string.Equals(notifications, "off", StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        if (errorOnly && !string.Equals(notifications, "all", StringComparison.OrdinalIgnoreCase)
            && !string.Equals(notifications, "errorsOnly", StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        if (!errorOnly && !string.Equals(notifications, "all", StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        _notifyIcon.ShowBalloonTip(3000, title, text, icon);
    }

    private static string BuildTooltip(string title, AgentResponse response)
    {
        var text = $"{title}: {response.State.Current} - {response.Message}";
        return text.Length <= 63 ? text : text[..63];
    }
}
