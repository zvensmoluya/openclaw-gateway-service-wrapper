using System.Security.Cryptography;
using System.Text;

namespace OpenClaw.Agent.Core;

public static class NamedPipeNames
{
    public static string GetMutexName(CurrentSessionContext context, string dataRoot)
    {
        return $"Local\\OpenClaw.Agent.Host.{Sanitize(context.UserSid)}.{context.SessionId}.{GetDataRootSuffix(dataRoot)}";
    }

    public static string GetPipeName(CurrentSessionContext context, string dataRoot)
    {
        return $"OpenClaw.Agent.{Sanitize(context.UserSid)}.{context.SessionId}.{GetDataRootSuffix(dataRoot)}";
    }

    public static string GetTrayMutexName(CurrentSessionContext context, string dataRoot)
    {
        return $"Local\\OpenClaw.Agent.Tray.{Sanitize(context.UserSid)}.{context.SessionId}.{GetDataRootSuffix(dataRoot)}";
    }

    private static string GetDataRootSuffix(string dataRoot)
    {
        var normalized = Path.GetFullPath(dataRoot).ToLowerInvariant();
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(normalized));
        return Convert.ToHexString(bytes[..8]);
    }

    private static string Sanitize(string value)
    {
        return value.Replace('\\', '_').Replace(':', '_');
    }
}
