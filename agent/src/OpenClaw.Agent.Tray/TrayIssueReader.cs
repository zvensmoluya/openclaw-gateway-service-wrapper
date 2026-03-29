using OpenClaw.Agent.Core;
using OpenClaw.Agent.Protocol;

namespace OpenClaw.Agent.Tray;

internal sealed class TrayIssueReader
{
    private static readonly string[] ImportantPatterns =
    [
        "device token mismatch",
        "too many failed authentication attempts",
        "gateway already running locally",
        "unauthorized",
        "health probe is failing",
        "host reported a failed state"
    ];

    public string? GetRecentIssue(AgentPaths paths, AgentResponse response)
    {
        var directIssue = response.Issues.Concat(response.Warnings)
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .FirstOrDefault();
        if (!string.IsNullOrWhiteSpace(directIssue))
        {
            return directIssue;
        }

        return FindInterestingLogLine(paths.StdErrLogPath)
            ?? FindInterestingLogLine(paths.AgentLogPath);
    }

    private static string? FindInterestingLogLine(string path)
    {
        if (!File.Exists(path))
        {
            return null;
        }

        try
        {
            return File.ReadLines(path)
                .Reverse()
                .FirstOrDefault(IsInterestingLine);
        }
        catch
        {
            return null;
        }
    }

    private static bool IsInterestingLine(string line)
    {
        return ImportantPatterns.Any(pattern => line.Contains(pattern, StringComparison.OrdinalIgnoreCase));
    }
}
