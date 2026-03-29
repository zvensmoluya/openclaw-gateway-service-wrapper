using System.Runtime.InteropServices;
using System.Text.Json.Nodes;
using OpenClaw.Agent.Protocol;

namespace OpenClaw.Agent.Core;

public sealed class WrapperConfigMigrator
{
    private static readonly string[] RetiredFields =
    [
        "serviceName",
        "displayName",
        "serviceAccountMode",
        "winswVersion",
        "winswDownloadUrl",
        "winswChecksum",
        "failureActions",
        "resetFailure",
        "startMode",
        "delayedAutoStart",
        "restartTask",
        "restart-task"
    ];

    public InitConfigResult InitializeConfig(string wrapperConfigPath, string outputPath, bool overwrite)
    {
        var sourcePath = Path.GetFullPath(wrapperConfigPath);
        if (!File.Exists(sourcePath))
        {
            throw new FileNotFoundException($"Wrapper config file not found: {sourcePath}", sourcePath);
        }

        var resolvedOutputPath = Path.GetFullPath(outputPath);
        if (File.Exists(resolvedOutputPath) && !overwrite)
        {
            throw new InvalidOperationException($"Agent config already exists: {resolvedOutputPath}. Use --force to overwrite it.");
        }

        var root = JsonNode.Parse(File.ReadAllText(sourcePath)) as JsonObject
            ?? throw new InvalidOperationException($"Wrapper config '{sourcePath}' is empty or invalid.");

        var bind = root["bind"]?.GetValue<string>()?.Trim();
        if (!string.IsNullOrWhiteSpace(bind) && !string.Equals(bind, AgentConstants.DefaultBind, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException($"Wrapper config bind '{bind}' is not supported. V2 currently requires bind = '{AgentConstants.DefaultBind}'.");
        }

        var retainedFields = new List<string>();
        var warnings = new List<string>();
        var agentConfig = new AgentConfig
        {
            OpenClaw = new OpenClawLaunchConfig
            {
                ConfigPath = ReadString(root, "configPath", "%USERPROFILE%\\.openclaw\\openclaw.json", retainedFields),
                WorkingDirectory = null
            },
            Network = new NetworkConfig
            {
                Bind = AgentConstants.DefaultBind,
                Port = ReadInt(root, "port", AgentConstants.DefaultPort, retainedFields)
            },
            Proxy = new ProxyConfig
            {
                HttpProxy = ReadOptionalString(root, "httpProxy", retainedFields),
                HttpsProxy = ReadOptionalString(root, "httpsProxy", retainedFields),
                AllProxy = ReadOptionalString(root, "allProxy", retainedFields),
                NoProxy = ReadOptionalString(root, "noProxy", retainedFields)
            },
            Tray = BuildTrayConfig(root, retainedFields)
        };

        var commandLine = ReadOptionalString(root, "openclawCommand", retainedFields);
        if (string.IsNullOrWhiteSpace(commandLine))
        {
            agentConfig.OpenClaw.Executable = "openclaw.cmd";
            agentConfig.OpenClaw.Arguments = [];
            warnings.Add("wrapper openclawCommand was empty; defaulting to 'openclaw.cmd'.");
        }
        else
        {
            var parts = SplitCommandLine(commandLine);
            if (parts.Count == 0)
            {
                throw new InvalidOperationException("wrapper openclawCommand could not be parsed.");
            }

            agentConfig.OpenClaw.Executable = parts[0];
            agentConfig.OpenClaw.Arguments = parts.Skip(1).ToList();
        }

        Directory.CreateDirectory(Path.GetDirectoryName(resolvedOutputPath) ?? throw new InvalidOperationException($"No parent directory for '{resolvedOutputPath}'."));
        File.WriteAllText(resolvedOutputPath, AgentJson.Serialize(agentConfig));

        return new InitConfigResult
        {
            Success = true,
            Message = "Agent config was generated from the wrapper config.",
            SourcePath = sourcePath,
            OutputPath = resolvedOutputPath,
            RetainedFields = retainedFields.Distinct(StringComparer.OrdinalIgnoreCase).ToList(),
            RetiredFields = GetRetiredFields(root),
            Warnings = warnings
        };
    }

    private static TrayConfig BuildTrayConfig(JsonObject root, List<string> retainedFields)
    {
        var displayName = ReadOptionalString(root, "displayName");
        var tray = root["tray"] as JsonObject;
        if (tray is not null)
        {
            retainedFields.Add("tray");
        }

        var trayConfig = new TrayConfig
        {
            Title = ReadOptionalString(tray, "title") ?? displayName ?? "OpenClaw",
            Notifications = ReadString(tray, "notifications", "all", retainedFields, "tray.notifications"),
            Refresh = new TrayRefreshConfig
            {
                FastSeconds = ReadInt(tray?["refresh"] as JsonObject, "fastSeconds", 30, retainedFields, "tray.refresh.fastSeconds"),
                DeepSeconds = ReadInt(tray?["refresh"] as JsonObject, "deepSeconds", 180, retainedFields, "tray.refresh.deepSeconds"),
                MenuSeconds = ReadInt(tray?["refresh"] as JsonObject, "menuSeconds", 10, retainedFields, "tray.refresh.menuSeconds")
            },
            Icons = new TrayIconConfig
            {
                Default = ReadOptionalString(tray?["icons"] as JsonObject, "default", retainedFields, "tray.icons.default"),
                Healthy = ReadOptionalString(tray?["icons"] as JsonObject, "healthy", retainedFields, "tray.icons.healthy"),
                Degraded = ReadOptionalString(tray?["icons"] as JsonObject, "degraded", retainedFields, "tray.icons.degraded"),
                Unhealthy = ReadOptionalString(tray?["icons"] as JsonObject, "unhealthy", retainedFields, "tray.icons.unhealthy"),
                Stopped = ReadOptionalString(tray?["icons"] as JsonObject, "stopped", retainedFields, "tray.icons.stopped"),
                Error = ReadOptionalString(tray?["icons"] as JsonObject, "error", retainedFields, "tray.icons.error"),
                Loading = ReadOptionalString(tray?["icons"] as JsonObject, "loading", retainedFields, "tray.icons.loading"),
                NotInstalled = ReadOptionalString(tray?["icons"] as JsonObject, "notInstalled", retainedFields, "tray.icons.notInstalled")
            }
        };

        return trayConfig;
    }

    private static List<string> GetRetiredFields(JsonObject root)
    {
        var retired = new List<string>();
        foreach (var field in RetiredFields)
        {
            if (root.ContainsKey(field))
            {
                retired.Add(field);
            }
        }

        return retired;
    }

    private static string ReadString(JsonObject? root, string propertyName, string fallback, List<string>? retainedFields = null, string? retainedName = null)
    {
        var value = ReadOptionalString(root, propertyName, retainedFields, retainedName);
        return string.IsNullOrWhiteSpace(value) ? fallback : value;
    }

    private static string? ReadOptionalString(JsonObject? root, string propertyName, List<string>? retainedFields = null, string? retainedName = null)
    {
        if (root is null || !root.TryGetPropertyValue(propertyName, out var node) || node is null)
        {
            return null;
        }

        retainedFields?.Add(retainedName ?? propertyName);
        return node.GetValue<string>()?.Trim();
    }

    private static int ReadInt(JsonObject? root, string propertyName, int fallback, List<string>? retainedFields = null, string? retainedName = null)
    {
        if (root is null || !root.TryGetPropertyValue(propertyName, out var node) || node is null)
        {
            return fallback;
        }

        retainedFields?.Add(retainedName ?? propertyName);
        if (node is JsonValue value && value.TryGetValue<int>(out var parsed))
        {
            return parsed;
        }

        if (int.TryParse(node.ToJsonString().Trim('"'), out parsed))
        {
            return parsed;
        }

        throw new InvalidOperationException($"Expected integer value for '{retainedName ?? propertyName}'.");
    }

    private static List<string> SplitCommandLine(string commandLine)
    {
        var argc = 0;
        var argv = CommandLineToArgvW(commandLine, out argc);
        if (argv == IntPtr.Zero)
        {
            throw new InvalidOperationException($"Unable to parse command line '{commandLine}'.");
        }

        try
        {
            var parts = new List<string>();
            for (var index = 0; index < argc; index++)
            {
                var item = Marshal.ReadIntPtr(argv, index * IntPtr.Size);
                parts.Add(Marshal.PtrToStringUni(item) ?? string.Empty);
            }

            return parts;
        }
        finally
        {
            LocalFree(argv);
        }
    }

    [DllImport("shell32.dll", SetLastError = true)]
    private static extern IntPtr CommandLineToArgvW(
        [MarshalAs(UnmanagedType.LPWStr)] string commandLine,
        out int numArgs);

    [DllImport("kernel32.dll")]
    private static extern IntPtr LocalFree(IntPtr handle);
}
