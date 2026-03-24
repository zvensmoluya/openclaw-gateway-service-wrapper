using System.Diagnostics;
using System.Net.NetworkInformation;
using System.Text;

namespace OpenClaw.Agent.Core;

public static class ProcessUtilities
{
    public static string QuoteForCmd(string value)
    {
        if (string.IsNullOrEmpty(value))
        {
            return "\"\"";
        }

        if (!value.Contains(' ') && !value.Contains('"'))
        {
            return value;
        }

        return "\"" + value.Replace("\"", "\\\"") + "\"";
    }

    public static ProcessStartInfo CreateStartInfo(ResolvedLaunchCommand command, AgentConfig config, AgentPaths paths)
    {
        var info = new ProcessStartInfo
        {
            WorkingDirectory = command.WorkingDirectory,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };

        if (command.CommandKind == ResolvedCommandKind.CmdShim)
        {
            info.FileName = Environment.GetEnvironmentVariable("ComSpec") ?? "cmd.exe";
            var segments = new List<string> { QuoteForCmd(command.ResolvedExecutablePath) };
            segments.AddRange(command.EffectiveArguments.Select(QuoteForCmd));
            info.Arguments = "/d /s /c \"" + string.Join(" ", segments) + "\"";
        }
        else
        {
            info.FileName = command.ResolvedExecutablePath;
            foreach (var argument in command.EffectiveArguments)
            {
                info.ArgumentList.Add(argument);
            }
        }

        ApplyChildEnvironment(info, config, paths);
        return info;
    }

    public static async Task CopyToLogAsync(StreamReader reader, string path, CancellationToken cancellationToken)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path) ?? throw new InvalidOperationException($"No parent directory for '{path}'."));
        await using var writer = new StreamWriter(new FileStream(path, FileMode.Append, FileAccess.Write, FileShare.ReadWrite))
        {
            AutoFlush = true
        };

        while (!cancellationToken.IsCancellationRequested)
        {
            string? line;
            try
            {
                line = await reader.ReadLineAsync(cancellationToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }

            if (line is null)
            {
                break;
            }

            await writer.WriteLineAsync(line);
        }
    }

    public static bool ProcessExists(int processId)
    {
        if (processId <= 0)
        {
            return false;
        }

        try
        {
            using var process = Process.GetProcessById(processId);
            return !process.HasExited;
        }
        catch
        {
            return false;
        }
    }

    public static async Task KillProcessTreeAsync(int processId, CancellationToken cancellationToken)
    {
        if (processId <= 0 || !ProcessExists(processId))
        {
            return;
        }

        var taskkill = new ProcessStartInfo
        {
            FileName = "taskkill.exe",
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };

        taskkill.ArgumentList.Add("/PID");
        taskkill.ArgumentList.Add(processId.ToString());
        taskkill.ArgumentList.Add("/T");
        taskkill.ArgumentList.Add("/F");

        using var process = Process.Start(taskkill) ?? throw new InvalidOperationException("Unable to start taskkill.exe.");
        await process.WaitForExitAsync(cancellationToken);
    }

    public static List<string> GetActiveListeners(int port)
    {
        return IPGlobalProperties.GetIPGlobalProperties()
            .GetActiveTcpListeners()
            .Where(endpoint => endpoint.Port == port)
            .Select(endpoint => endpoint.ToString())
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    private static void ApplyChildEnvironment(ProcessStartInfo info, AgentConfig config, AgentPaths paths)
    {
        info.Environment["OPENCLAW_STATE_DIR"] = paths.DataRoot;
        info.Environment["OPENCLAW_CONFIG_PATH"] = config.OpenClaw.ConfigPath;
        info.Environment["OPENCLAW_GATEWAY_PORT"] = config.Network.Port.ToString();
        info.Environment["OPENCLAW_SERVICE_MARKER"] = "openclaw";
        info.Environment["OPENCLAW_SERVICE_KIND"] = "gateway";

        SetIfPresent(info, "HTTP_PROXY", config.Proxy.HttpProxy);
        SetIfPresent(info, "http_proxy", config.Proxy.HttpProxy);
        SetIfPresent(info, "HTTPS_PROXY", config.Proxy.HttpsProxy);
        SetIfPresent(info, "https_proxy", config.Proxy.HttpsProxy);
        SetIfPresent(info, "ALL_PROXY", config.Proxy.AllProxy);
        SetIfPresent(info, "all_proxy", config.Proxy.AllProxy);
        SetIfPresent(info, "NO_PROXY", config.Proxy.NoProxy);
        SetIfPresent(info, "no_proxy", config.Proxy.NoProxy);
    }

    private static void SetIfPresent(ProcessStartInfo info, string key, string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            info.Environment.Remove(key);
            return;
        }

        info.Environment[key] = value;
    }
}
