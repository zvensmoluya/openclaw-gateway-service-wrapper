using OpenClaw.Agent.Protocol;

namespace OpenClaw.Agent.Core;

public sealed class FileStateStore
{
    public T? Read<T>(string path)
    {
        if (!File.Exists(path))
        {
            return default;
        }

        try
        {
            var raw = File.ReadAllText(path).Trim('\0', ' ', '\t', '\r', '\n');
            if (string.IsNullOrWhiteSpace(raw))
            {
                return default;
            }

            return AgentJson.Deserialize<T>(raw);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or System.Text.Json.JsonException)
        {
            return default;
        }
    }

    public void Write<T>(string path, T value)
    {
        var directory = Path.GetDirectoryName(path) ?? throw new InvalidOperationException($"No parent directory for '{path}'.");
        Directory.CreateDirectory(directory);

        var tempPath = Path.Combine(directory, $"{Path.GetFileName(path)}.{Guid.NewGuid():N}.tmp");
        File.WriteAllText(tempPath, AgentJson.Serialize(value));

        try
        {
            if (File.Exists(path))
            {
                File.Replace(tempPath, path, null, ignoreMetadataErrors: true);
            }
            else
            {
                File.Move(tempPath, path);
            }
        }
        finally
        {
            if (File.Exists(tempPath))
            {
                File.Delete(tempPath);
            }
        }
    }
}
