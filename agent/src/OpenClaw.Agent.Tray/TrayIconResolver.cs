using System.Drawing;
using OpenClaw.Agent.Core;

namespace OpenClaw.Agent.Tray;

internal sealed class TrayIconResolver
{
    private readonly string _baseDirectory;

    public TrayIconResolver(string baseDirectory)
    {
        _baseDirectory = baseDirectory;
    }

    public string? ResolveIconPath(TrayConfig config, string trayState)
    {
        var configuredPath = trayState switch
        {
            "running" => config.Icons.Healthy,
            "degraded" => config.Icons.Degraded,
            "failed" => config.Icons.Error,
            "starting" => config.Icons.Loading,
            "stopping" => config.Icons.Loading,
            _ => config.Icons.Stopped
        } ?? config.Icons.Default;

        var normalizedConfiguredPath = NormalizePath(configuredPath);
        if (!string.IsNullOrWhiteSpace(normalizedConfiguredPath) && File.Exists(normalizedConfiguredPath))
        {
            return normalizedConfiguredPath;
        }

        var bundledIconName = trayState switch
        {
            "running" => "openclaw-healthy.ico",
            "degraded" => "openclaw-degraded.ico",
            "failed" => "openclaw-error.ico",
            "starting" => "openclaw-loading.ico",
            "stopping" => "openclaw-loading.ico",
            _ => "openclaw-stopped.ico"
        };

        var bundledPath = Path.Combine(_baseDirectory, "assets", "tray", bundledIconName);
        return File.Exists(bundledPath) ? bundledPath : null;
    }

    public Icon ResolveFallbackIcon(string trayState)
    {
        return trayState switch
        {
            "running" => SystemIcons.Information,
            "degraded" => SystemIcons.Warning,
            "failed" => SystemIcons.Error,
            "starting" => SystemIcons.Application,
            "stopping" => SystemIcons.Application,
            _ => SystemIcons.Application
        };
    }

    private string? NormalizePath(string? path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return null;
        }

        var expanded = Environment.ExpandEnvironmentVariables(path.Trim());
        if (Path.IsPathRooted(expanded))
        {
            return Path.GetFullPath(expanded);
        }

        return Path.GetFullPath(Path.Combine(_baseDirectory, expanded));
    }
}
