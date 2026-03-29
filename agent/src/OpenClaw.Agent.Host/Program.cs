using System.Diagnostics;
using System.Threading;
using OpenClaw.Agent.Core;
using OpenClaw.Agent.Protocol;

namespace OpenClaw.Agent.Host;

internal static class Program
{
    [STAThread]
    private static async Task<int> Main(string[] args)
    {
        var launchSource = args.Contains("--autostart", StringComparer.OrdinalIgnoreCase) ? "autostart" : "manual";
        var session = PathHelpers.GetCurrentSession();
        var paths = PathHelpers.GetDefaultPaths();
        using var mutex = new Mutex(initiallyOwned: true, NamedPipeNames.GetMutexName(session, paths.DataRoot), out var createdNew);
        if (!createdNew)
        {
            return 0;
        }

        PathHelpers.EnsureDataDirectories(paths);
        var bootstrapLogWriter = new AgentLogWriter(paths.AgentLogPath);

        var hostExecutablePath = Path.GetFullPath(Environment.ProcessPath ?? Process.GetCurrentProcess().MainModule?.FileName
            ?? throw new InvalidOperationException("Unable to determine the host executable path."));
        var runtime = new AgentRuntime(paths, session, hostExecutablePath, logWriter: bootstrapLogWriter);
        using var shutdownCts = new CancellationTokenSource();
        var pipeServer = new AgentPipeServer(session, paths.DataRoot, (command, token) => HandleCommandAsync(runtime, command, token));
        var pipeTask = Task.Run(
            async () =>
            {
                try
                {
                    await bootstrapLogWriter.WriteAsync("INFO", "Pipe server starting.", CancellationToken.None);
                    await pipeServer.RunAsync(shutdownCts.Token);
                }
                catch (Exception ex)
                {
                    await bootstrapLogWriter.WriteAsync("ERROR", $"Pipe server failed: {ex}", CancellationToken.None);
                    throw;
                }
            },
            shutdownCts.Token);

        using var sessionPump = new SessionNotificationPump(
            async () =>
            {
                try
                {
                    await runtime.HandleSessionSignOutAsync(CancellationToken.None);
                }
                finally
                {
                    shutdownCts.Cancel();
                }
            });

        try
        {
            sessionPump.Start();
            await runtime.InitializeAsync(launchSource, CancellationToken.None);
            await Task.Delay(Timeout.Infinite, shutdownCts.Token);
            return 0;
        }
        catch (OperationCanceledException)
        {
            return 0;
        }
        catch (Exception ex)
        {
            await bootstrapLogWriter.WriteAsync("ERROR", ex.ToString(), CancellationToken.None);
            return 1;
        }
        finally
        {
            shutdownCts.Cancel();
            try
            {
                await pipeTask.WaitAsync(TimeSpan.FromSeconds(2));
            }
            catch
            {
            }

            await runtime.ShutdownAsync(CancellationToken.None);
            await runtime.DisposeAsync();
        }
    }

    private static Task<AgentResponse> HandleCommandAsync(AgentRuntime runtime, string command, CancellationToken cancellationToken)
    {
        return command.ToLowerInvariant() switch
        {
            "ping" => runtime.GetStatusAsync(cancellationToken),
            "start" => runtime.StartAsync("cli-start", cancellationToken),
            "stop" => runtime.StopAsync(ExitReason.UserStop, "cli-stop", cancellationToken),
            "restart" => runtime.RestartAsync("cli-restart", cancellationToken),
            "status" => runtime.GetStatusAsync(cancellationToken),
            "doctor" => runtime.GetDoctorAsync(cancellationToken),
            _ => Task.FromResult(new AgentResponse
            {
                Success = false,
                HostReachable = true,
                Message = $"Unsupported command '{command}'.",
                StatusSource = "live",
                Issues = [$"Unsupported command '{command}'."]
            })
        };
    }
}
