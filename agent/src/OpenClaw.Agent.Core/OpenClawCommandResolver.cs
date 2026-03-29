namespace OpenClaw.Agent.Core;

public sealed class OpenClawCommandResolver
{
    public ResolvedLaunchCommand Resolve(AgentConfig config)
    {
        var executable = config.OpenClaw.Executable;
        var resolvedExecutable = ResolveExecutable(executable);
        var (effectiveExecutable, preArguments, kind) = ResolveLaunchExecutable(resolvedExecutable);
        var workingDirectory = ResolveWorkingDirectory(config, resolvedExecutable);
        var effectiveArguments = new List<string>();
        effectiveArguments.AddRange(preArguments);
        effectiveArguments.AddRange(config.OpenClaw.Arguments);
        effectiveArguments.AddRange(
        [
            "gateway",
            "run",
            "--bind",
            AgentConstants.DefaultBind,
            "--port",
            config.Network.Port.ToString()
        ]);

        return new ResolvedLaunchCommand
        {
            ResolvedExecutablePath = effectiveExecutable,
            WorkingDirectory = workingDirectory,
            CommandKind = kind,
            EffectiveArguments = effectiveArguments,
            DisplayExecutable = executable,
            HealthUrl = $"http://127.0.0.1:{config.Network.Port}{AgentConstants.HealthPath}",
            OpenClawConfigPath = config.OpenClaw.ConfigPath
        };
    }

    private static string ResolveExecutable(string executable)
    {
        if (string.IsNullOrWhiteSpace(executable))
        {
            throw new InvalidOperationException("openclaw.executable must not be empty.");
        }

        var expanded = Environment.ExpandEnvironmentVariables(executable.Trim());
        var containsDirectorySeparator = expanded.Contains(Path.DirectorySeparatorChar) || expanded.Contains(Path.AltDirectorySeparatorChar);
        if (Path.IsPathRooted(expanded) || containsDirectorySeparator)
        {
            var rootedCandidate = Path.GetFullPath(expanded);
            var rootedResolved = ResolveWithExtensions(rootedCandidate);
            if (rootedResolved is not null)
            {
                return rootedResolved;
            }

            throw new FileNotFoundException($"Configured OpenClaw executable not found: {rootedCandidate}", rootedCandidate);
        }

        var pathDirectories = (Environment.GetEnvironmentVariable("PATH") ?? string.Empty)
            .Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

        foreach (var directory in pathDirectories)
        {
            var candidate = Path.Combine(directory, expanded);
            var resolved = ResolveWithExtensions(candidate);
            if (resolved is not null)
            {
                return resolved;
            }
        }

        throw new FileNotFoundException($"OpenClaw executable '{expanded}' could not be found in PATH.");
    }

    private static string? ResolveWithExtensions(string candidate)
    {
        if (File.Exists(candidate))
        {
            return Path.GetFullPath(candidate);
        }

        if (!string.IsNullOrEmpty(Path.GetExtension(candidate)))
        {
            return null;
        }

        foreach (var extension in GetPathExtensions())
        {
            var withExtension = candidate + extension;
            if (File.Exists(withExtension))
            {
                return Path.GetFullPath(withExtension);
            }
        }

        return null;
    }

    private static IReadOnlyList<string> GetPathExtensions()
    {
        var raw = Environment.GetEnvironmentVariable("PATHEXT");
        if (string.IsNullOrWhiteSpace(raw))
        {
            return [".exe", ".cmd", ".bat", ".com"];
        }

        return raw.Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(value => value.StartsWith('.') ? value : "." + value)
            .ToArray();
    }

    private static bool IsCmdShim(string path)
    {
        var extension = Path.GetExtension(path);
        return string.Equals(extension, ".cmd", StringComparison.OrdinalIgnoreCase)
            || string.Equals(extension, ".bat", StringComparison.OrdinalIgnoreCase);
    }

    private static (string Executable, IReadOnlyList<string> PreArguments, ResolvedCommandKind Kind) ResolveLaunchExecutable(string resolvedExecutable)
    {
        if (!IsCmdShim(resolvedExecutable))
        {
            return (resolvedExecutable, Array.Empty<string>(), ResolvedCommandKind.Executable);
        }

        var commandDirectory = Path.GetDirectoryName(resolvedExecutable)
            ?? throw new InvalidOperationException($"Unable to resolve the parent directory for '{resolvedExecutable}'.");
        var nodeExecutablePath = Path.Combine(commandDirectory, "node.exe");
        var entryScriptPath = Path.Combine(commandDirectory, "node_modules", "openclaw", "openclaw.mjs");
        if (File.Exists(nodeExecutablePath) && File.Exists(entryScriptPath))
        {
            return (nodeExecutablePath, [entryScriptPath], ResolvedCommandKind.Executable);
        }

        return (resolvedExecutable, Array.Empty<string>(), ResolvedCommandKind.CmdShim);
    }

    private static string ResolveWorkingDirectory(AgentConfig config, string resolvedExecutable)
    {
        if (!string.IsNullOrWhiteSpace(config.OpenClaw.WorkingDirectory))
        {
            return config.OpenClaw.WorkingDirectory;
        }

        var executableDirectory = Path.GetDirectoryName(resolvedExecutable);
        if (!string.IsNullOrWhiteSpace(executableDirectory))
        {
            return executableDirectory;
        }

        return AppContext.BaseDirectory;
    }
}
