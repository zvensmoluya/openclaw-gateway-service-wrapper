using OpenClaw.Agent.Core;
using OpenClaw.Agent.Protocol;

namespace OpenClaw.Agent.Tray;

internal sealed class TrayStatusForm : Form
{
    private readonly Label _stateValue;
    private readonly Label _healthValue;
    private readonly Label _endpointValue;
    private readonly Label _dataRootValue;
    private readonly Label _configValue;
    private readonly Label _logsValue;
    private readonly TextBox _recentIssuesBox;
    private readonly Button _openDashboardButton;
    private readonly Button _startButton;
    private readonly Button _stopButton;
    private readonly Button _restartButton;
    private readonly Button _refreshButton;
    private readonly Button _openLogsButton;
    private readonly Button _openConfigButton;

    public TrayStatusForm(
        Func<Task> start,
        Func<Task> stop,
        Func<Task> restart,
        Func<Task> refresh,
        Action openDashboard,
        Action openLogs,
        Action openConfig)
    {
        Text = "OpenClaw Tray";
        StartPosition = FormStartPosition.CenterScreen;
        MinimumSize = new Size(700, 480);
        Size = new Size(760, 560);

        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 3,
            Padding = new Padding(16)
        };
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));

        var summary = new TableLayoutPanel
        {
            Dock = DockStyle.Top,
            AutoSize = true,
            ColumnCount = 2
        };
        summary.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        summary.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));

        _stateValue = AddRow(summary, 0, "Current State");
        _healthValue = AddRow(summary, 1, "Health");
        _endpointValue = AddRow(summary, 2, "Endpoint");
        _dataRootValue = AddRow(summary, 3, "Data Root");
        _configValue = AddRow(summary, 4, "Config Path");
        _logsValue = AddRow(summary, 5, "Logs");

        _recentIssuesBox = new TextBox
        {
            Dock = DockStyle.Fill,
            ReadOnly = true,
            Multiline = true,
            ScrollBars = ScrollBars.Vertical
        };

        var issuesGroup = new GroupBox
        {
            Dock = DockStyle.Fill,
            Text = "Recent Issues"
        };
        issuesGroup.Controls.Add(_recentIssuesBox);

        var actions = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            AutoSize = true,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = true
        };

        _openDashboardButton = AddButton(actions, "Open Dashboard", (_, _) => openDashboard());
        _startButton = AddButton(actions, "Start", (_, _) => _ = start());
        _stopButton = AddButton(actions, "Stop", (_, _) => _ = stop());
        _restartButton = AddButton(actions, "Restart", (_, _) => _ = restart());
        _refreshButton = AddButton(actions, "Refresh", (_, _) => _ = refresh());
        _openLogsButton = AddButton(actions, "Open Logs", (_, _) => openLogs());
        _openConfigButton = AddButton(actions, "Open Config", (_, _) => openConfig());

        root.Controls.Add(summary, 0, 0);
        root.Controls.Add(issuesGroup, 0, 1);
        root.Controls.Add(actions, 0, 2);

        Controls.Add(root);
        FormClosing += OnFormClosing;
    }

    public void UpdateView(AgentResponse response, string? recentIssue, int port)
    {
        Text = $"OpenClaw Tray - {response.State.Current}";
        _stateValue.Text = response.State.Current;
        _healthValue.Text = response.Health.Ok ? "OK" : $"FAIL - {response.Health.Error ?? "Unknown"}";
        _endpointValue.Text = $"ws://localhost:{port}";
        _dataRootValue.Text = response.Paths.DataRoot;
        _configValue.Text = response.Paths.ConfigPath;
        _logsValue.Text = response.Paths.AgentLogPath;
        _recentIssuesBox.Text = string.IsNullOrWhiteSpace(recentIssue) ? "No recent issues." : recentIssue;

        var hostReachable = response.HostReachable;
        _openDashboardButton.Enabled = hostReachable;
        _startButton.Enabled = hostReachable
            ? response.State.Current is not nameof(AgentState.Running) and not nameof(AgentState.Starting)
            : response.State.Current is not nameof(AgentState.Stopping);
        _stopButton.Enabled = hostReachable && response.State.Current is not nameof(AgentState.Stopped) and not nameof(AgentState.Stopping);
        _restartButton.Enabled = hostReachable
            ? response.State.Current is not nameof(AgentState.Starting) and not nameof(AgentState.Stopping)
            : response.State.Current is not nameof(AgentState.Stopping);
        _refreshButton.Enabled = true;
        _openLogsButton.Enabled = true;
        _openConfigButton.Enabled = true;
    }

    public void ShowAndActivateWindow()
    {
        Show();
        WindowState = FormWindowState.Normal;
        Activate();
        BringToFront();
    }

    private static Label AddRow(TableLayoutPanel panel, int rowIndex, string labelText)
    {
        if (panel.RowCount <= rowIndex)
        {
            panel.RowCount = rowIndex + 1;
        }

        panel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        var label = new Label
        {
            Text = labelText,
            AutoSize = true,
            Margin = new Padding(0, 8, 12, 8)
        };
        var value = new Label
        {
            AutoSize = true,
            Margin = new Padding(0, 8, 0, 8)
        };
        panel.Controls.Add(label, 0, rowIndex);
        panel.Controls.Add(value, 1, rowIndex);
        return value;
    }

    private static Button AddButton(FlowLayoutPanel panel, string text, EventHandler onClick)
    {
        var button = new Button
        {
            Text = text,
            AutoSize = true
        };
        button.Click += onClick;
        panel.Controls.Add(button);
        return button;
    }

    private void OnFormClosing(object? sender, FormClosingEventArgs e)
    {
        if (e.CloseReason == CloseReason.UserClosing)
        {
            e.Cancel = true;
            Hide();
        }
    }
}
