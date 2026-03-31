using System.Net;
using System.Net.Sockets;
using System.Text;

namespace OpenClaw.Agent.FakeOpenClaw;

internal static class Program
{
    private static async Task<int> Main(string[] args)
    {
        if (args.Length < 4 || !string.Equals(args[0], "gateway", StringComparison.OrdinalIgnoreCase) || !string.Equals(args[1], "run", StringComparison.OrdinalIgnoreCase))
        {
            Console.Error.WriteLine("Expected: gateway run --bind loopback --port <port>");
            return 2;
        }

        var portIndex = Array.FindIndex(args, value => string.Equals(value, "--port", StringComparison.OrdinalIgnoreCase));
        if (portIndex < 0 || portIndex == args.Length - 1 || !int.TryParse(args[portIndex + 1], out var port))
        {
            Console.Error.WriteLine("Missing --port argument.");
            return 2;
        }

        var healthMode = Environment.GetEnvironmentVariable("FAKE_OPENCLAW_HEALTH_MODE")?.Trim().ToLowerInvariant() ?? "ok";
        var exitAfterMs = ParseInt(Environment.GetEnvironmentVariable("FAKE_OPENCLAW_EXIT_AFTER_MS"));
        var exitCode = ParseInt(Environment.GetEnvironmentVariable("FAKE_OPENCLAW_EXIT_CODE")) ?? 0;

        using var cts = new CancellationTokenSource();
        Console.CancelKeyPress += (_, eventArgs) =>
        {
            eventArgs.Cancel = true;
            cts.Cancel();
        };
        AppDomain.CurrentDomain.ProcessExit += (_, _) => cts.Cancel();

        using var listener = new TcpListener(IPAddress.Loopback, port);
        listener.Start();

        var serverTask = Task.Run(async () =>
        {
            while (!cts.IsCancellationRequested)
            {
                TcpClient? client = null;
                try
                {
                    client = await listener.AcceptTcpClientAsync(cts.Token);
                }
                catch (OperationCanceledException)
                {
                    break;
                }
                catch (SocketException)
                {
                    break;
                }

                if (client is null)
                {
                    continue;
                }

                _ = Task.Run(async () =>
                {
                    using var tcpClient = client;
                    await using var networkStream = tcpClient.GetStream();
                    using var reader = new StreamReader(networkStream, Encoding.ASCII, leaveOpen: true);
                    await using var writer = new StreamWriter(networkStream, new UTF8Encoding(false), leaveOpen: true)
                    {
                        NewLine = "\r\n",
                        AutoFlush = true
                    };

                    string? requestLine;
                    try
                    {
                        requestLine = await reader.ReadLineAsync(cts.Token);
                    }
                    catch
                    {
                        return;
                    }

                    if (string.IsNullOrWhiteSpace(requestLine))
                    {
                        return;
                    }

                    while (!cts.IsCancellationRequested)
                    {
                        var headerLine = await reader.ReadLineAsync(cts.Token);
                        if (string.IsNullOrEmpty(headerLine))
                        {
                            break;
                        }
                    }

                    var path = requestLine.Split(' ', StringSplitOptions.RemoveEmptyEntries).ElementAtOrDefault(1) ?? "/";
                    if (string.Equals(path, "/health", StringComparison.OrdinalIgnoreCase))
                    {
                        if (healthMode == "failing")
                        {
                            await WriteHttpResponseAsync(writer, 500, "unhealthy");
                        }
                        else
                        {
                            await WriteHttpResponseAsync(writer, 200, "ok");
                        }

                        return;
                    }

                    await WriteHttpResponseAsync(writer, 404, string.Empty);
                }, cts.Token);
            }
        }, cts.Token);

        Task? exitTask = null;
        if (exitAfterMs.HasValue)
        {
            exitTask = Task.Run(async () =>
            {
                await Task.Delay(exitAfterMs.Value, cts.Token);
                Environment.Exit(exitCode);
            }, cts.Token);
        }

        try
        {
            await serverTask;
            return 0;
        }
        finally
        {
            cts.Cancel();
            listener.Stop();

            if (exitTask is not null)
            {
                try
                {
                    await exitTask;
                }
                catch
                {
                }
            }
        }
    }

    private static int? ParseInt(string? value)
    {
        return int.TryParse(value, out var parsed) ? parsed : null;
    }

    private static async Task WriteHttpResponseAsync(StreamWriter writer, int statusCode, string body)
    {
        var reason = statusCode switch
        {
            200 => "OK",
            404 => "Not Found",
            500 => "Internal Server Error",
            _ => "OK"
        };
        var content = body ?? string.Empty;
        var contentLength = Encoding.UTF8.GetByteCount(content);

        await writer.WriteLineAsync($"HTTP/1.1 {statusCode} {reason}");
        await writer.WriteLineAsync("Content-Type: text/plain; charset=utf-8");
        await writer.WriteLineAsync($"Content-Length: {contentLength}");
        await writer.WriteLineAsync("Connection: close");
        await writer.WriteLineAsync(string.Empty);
        if (contentLength > 0)
        {
            await writer.WriteAsync(content);
        }
    }
}
