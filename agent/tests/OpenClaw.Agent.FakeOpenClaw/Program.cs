using System.Net;

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

        using var listener = new HttpListener();
        listener.Prefixes.Add($"http://127.0.0.1:{port}/");
        listener.Start();

        var serverTask = Task.Run(async () =>
        {
            while (!cts.IsCancellationRequested)
            {
                HttpListenerContext? context = null;
                try
                {
                    context = await listener.GetContextAsync().WaitAsync(cts.Token);
                }
                catch (OperationCanceledException)
                {
                    break;
                }
                catch (HttpListenerException)
                {
                    break;
                }

                if (context is null)
                {
                    continue;
                }

                using var response = context.Response;
                if (string.Equals(context.Request.Url?.AbsolutePath, "/health", StringComparison.OrdinalIgnoreCase))
                {
                    if (healthMode == "failing")
                    {
                        response.StatusCode = 500;
                        await using var writer = new StreamWriter(response.OutputStream);
                        await writer.WriteAsync("unhealthy");
                    }
                    else
                    {
                        response.StatusCode = 200;
                        await using var writer = new StreamWriter(response.OutputStream);
                        await writer.WriteAsync("ok");
                    }

                    continue;
                }

                response.StatusCode = 404;
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
            if (listener.IsListening)
            {
                listener.Stop();
            }

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
}
