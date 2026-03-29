using System.Text.Json;
using OpenClaw.Agent.Protocol;

namespace OpenClaw.Agent.Core;

public sealed class AgentConfigLoader
{
    public AgentConfig Load(AgentPaths paths)
    {
        if (!File.Exists(paths.ConfigPath))
        {
            throw new FileNotFoundException($"Agent config file not found: {paths.ConfigPath}", paths.ConfigPath);
        }

        var config = JsonSerializer.Deserialize<AgentConfig>(File.ReadAllText(paths.ConfigPath), AgentJson.Options)
            ?? throw new InvalidOperationException($"Agent config file '{paths.ConfigPath}' is empty or invalid.");

        Normalize(config);
        Validate(config, paths);
        return config;
    }

    private static void Normalize(AgentConfig config)
    {
        config.OpenClaw.Executable = Environment.ExpandEnvironmentVariables(config.OpenClaw.Executable ?? string.Empty).Trim();
        config.OpenClaw.WorkingDirectory = string.IsNullOrWhiteSpace(config.OpenClaw.WorkingDirectory)
            ? null
            : PathHelpers.ExpandValue(config.OpenClaw.WorkingDirectory);
        config.OpenClaw.ConfigPath = PathHelpers.ExpandValue(config.OpenClaw.ConfigPath);
        config.Proxy.HttpProxy = NormalizeOptional(config.Proxy.HttpProxy);
        config.Proxy.HttpsProxy = NormalizeOptional(config.Proxy.HttpsProxy);
        config.Proxy.AllProxy = NormalizeOptional(config.Proxy.AllProxy);
        config.Proxy.NoProxy = NormalizeOptional(config.Proxy.NoProxy);
        config.Network.Bind = string.IsNullOrWhiteSpace(config.Network.Bind) ? AgentConstants.DefaultBind : config.Network.Bind.Trim();
        config.Tray.Title = NormalizeOptional(config.Tray.Title) ?? "OpenClaw";
        config.Tray.Notifications = NormalizeOptional(config.Tray.Notifications) ?? "all";
        config.Tray.Refresh.FastSeconds = NormalizeInt(config.Tray.Refresh.FastSeconds, 30);
        config.Tray.Refresh.DeepSeconds = NormalizeInt(config.Tray.Refresh.DeepSeconds, 180);
        config.Tray.Refresh.MenuSeconds = NormalizeInt(config.Tray.Refresh.MenuSeconds, 10);
    }

    private static void Validate(AgentConfig config, AgentPaths paths)
    {
        if (!string.Equals(config.Network.Bind, AgentConstants.DefaultBind, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException("Phase 1 only supports network.bind = 'loopback'.");
        }

        if (config.Network.Port < 1 || config.Network.Port > 65535)
        {
            throw new InvalidOperationException($"Port '{config.Network.Port}' is outside the valid range 1-65535.");
        }

        if (string.IsNullOrWhiteSpace(config.OpenClaw.Executable))
        {
            throw new InvalidOperationException("openclaw.executable must not be empty.");
        }

        if (string.IsNullOrWhiteSpace(config.OpenClaw.ConfigPath))
        {
            throw new InvalidOperationException("openclaw.configPath must not be empty.");
        }

        if (!Path.IsPathFullyQualified(paths.ConfigPath))
        {
            throw new InvalidOperationException("Resolved agent config path must be absolute.");
        }

        if (config.Tray.Notifications is not ("all" or "errorsOnly" or "off"))
        {
            throw new InvalidOperationException("tray.notifications must be one of: all, errorsOnly, off.");
        }

        if (config.Tray.Refresh.FastSeconds < 15 || config.Tray.Refresh.FastSeconds > 300)
        {
            throw new InvalidOperationException($"tray.refresh.fastSeconds '{config.Tray.Refresh.FastSeconds}' is outside the valid range 15-300.");
        }

        if (config.Tray.Refresh.DeepSeconds < 60 || config.Tray.Refresh.DeepSeconds > 900)
        {
            throw new InvalidOperationException($"tray.refresh.deepSeconds '{config.Tray.Refresh.DeepSeconds}' is outside the valid range 60-900.");
        }

        if (config.Tray.Refresh.MenuSeconds < 5 || config.Tray.Refresh.MenuSeconds > 60)
        {
            throw new InvalidOperationException($"tray.refresh.menuSeconds '{config.Tray.Refresh.MenuSeconds}' is outside the valid range 5-60.");
        }
    }

    private static string? NormalizeOptional(string? value)
    {
        return string.IsNullOrWhiteSpace(value) ? null : value.Trim();
    }

    private static int NormalizeInt(int value, int fallback)
    {
        return value <= 0 ? fallback : value;
    }
}
