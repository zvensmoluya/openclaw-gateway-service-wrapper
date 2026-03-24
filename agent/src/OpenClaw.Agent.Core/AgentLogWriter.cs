namespace OpenClaw.Agent.Core;

public sealed class AgentLogWriter
{
    private readonly string _path;
    private readonly SemaphoreSlim _lock = new(1, 1);

    public AgentLogWriter(string path)
    {
        _path = path;
    }

    public async Task WriteAsync(string level, string message, CancellationToken cancellationToken = default)
    {
        var line = $"{DateTimeOffset.UtcNow:O} [{level}] {message}{Environment.NewLine}";
        await _lock.WaitAsync(cancellationToken);
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(_path) ?? throw new InvalidOperationException($"No parent directory for '{_path}'."));
            await using var stream = new FileStream(_path, FileMode.Append, FileAccess.Write, FileShare.ReadWrite);
            await using var writer = new StreamWriter(stream);
            await writer.WriteAsync(line);
            await writer.FlushAsync(cancellationToken);
        }
        finally
        {
            _lock.Release();
        }
    }
}
