namespace OpenClaw.Agent.Core;

public static class NamedPipeNames
{
    public static string GetMutexName(CurrentSessionContext context)
    {
        return $"Local\\OpenClaw.Agent.Host.{Sanitize(context.UserSid)}.{context.SessionId}";
    }

    public static string GetPipeName(CurrentSessionContext context)
    {
        return $"OpenClaw.Agent.{Sanitize(context.UserSid)}.{context.SessionId}";
    }

    private static string Sanitize(string value)
    {
        return value.Replace('\\', '_').Replace(':', '_');
    }
}
