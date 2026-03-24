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

        return AgentJson.Deserialize<T>(File.ReadAllText(path));
    }

    public void Write<T>(string path, T value)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path) ?? throw new InvalidOperationException($"No parent directory for '{path}'."));
        File.WriteAllText(path, AgentJson.Serialize(value));
    }
}
