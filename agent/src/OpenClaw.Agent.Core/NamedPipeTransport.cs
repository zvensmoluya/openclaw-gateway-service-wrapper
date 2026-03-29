using System.IO.Pipes;
using System.Text;
using OpenClaw.Agent.Protocol;

namespace OpenClaw.Agent.Core;

public sealed class AgentPipeServer
{
    private readonly CurrentSessionContext _session;
    private readonly string _dataRoot;
    private readonly Func<string, CancellationToken, Task<AgentResponse>> _handler;

    public AgentPipeServer(CurrentSessionContext session, string dataRoot, Func<string, CancellationToken, Task<AgentResponse>> handler)
    {
        _session = session;
        _dataRoot = dataRoot;
        _handler = handler;
    }

    public async Task RunAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            using var stream = CreateServerStream();
            try
            {
                await stream.WaitForConnectionAsync(cancellationToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }

            using var reader = new StreamReader(stream, Encoding.UTF8, leaveOpen: true);
            using var writer = new StreamWriter(stream, new UTF8Encoding(false), leaveOpen: true)
            {
                AutoFlush = true
            };

            var line = await reader.ReadLineAsync(cancellationToken);
            if (string.IsNullOrWhiteSpace(line))
            {
                continue;
            }

            var request = AgentJson.Deserialize<AgentRequest>(line) ?? new AgentRequest();
            var response = await _handler(request.Command, cancellationToken);
            await writer.WriteLineAsync(AgentJson.Serialize(response));
        }
    }

    private NamedPipeServerStream CreateServerStream()
    {
        return new NamedPipeServerStream(
            NamedPipeNames.GetPipeName(_session, _dataRoot),
            PipeDirection.InOut,
            1,
            PipeTransmissionMode.Byte,
            PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly,
            4096,
            4096);
    }
}

public sealed class AgentPipeClient
{
    private readonly CurrentSessionContext _session;
    private readonly string _dataRoot;

    public AgentPipeClient(CurrentSessionContext session, string dataRoot)
    {
        _session = session;
        _dataRoot = dataRoot;
    }

    public async Task<AgentResponse?> TrySendAsync(string command, CancellationToken cancellationToken)
    {
        using var stream = new NamedPipeClientStream(".", NamedPipeNames.GetPipeName(_session, _dataRoot), PipeDirection.InOut, PipeOptions.Asynchronous);
        try
        {
            await stream.ConnectAsync(500, cancellationToken);
        }
        catch
        {
            return null;
        }

        using var reader = new StreamReader(stream, Encoding.UTF8, leaveOpen: true);
        using var writer = new StreamWriter(stream, new UTF8Encoding(false), leaveOpen: true)
        {
            AutoFlush = true
        };

        await writer.WriteLineAsync(AgentJson.Serialize(new AgentRequest { Command = command }));
        var responseLine = await reader.ReadLineAsync(cancellationToken);
        return string.IsNullOrWhiteSpace(responseLine) ? null : AgentJson.Deserialize<AgentResponse>(responseLine);
    }
}
