using OpenClaw.Agent.Core;

namespace OpenClaw.Agent.Tests;

public sealed class ConfigAndCommandTests
{
    [Fact]
    public void LoadConfig_ExpandsEnvironmentValues()
    {
        var dataRoot = TestSupport.CreateTempDataRoot();
        try
        {
            var paths = TestSupport.GetPaths(dataRoot);
            PathHelpers.EnsureDataDirectories(paths);
            File.WriteAllText(
                paths.ConfigPath,
                """
                {
                  "openclaw": {
                    "executable": "openclaw.cmd",
                    "arguments": ["--flag"],
                    "workingDirectory": "%TEMP%",
                    "configPath": "%USERPROFILE%\\.openclaw\\openclaw.json"
                  },
                  "network": {
                    "bind": "loopback",
                    "port": 19001
                  }
                }
                """);

            var loader = new AgentConfigLoader();
            var config = loader.Load(paths);

            Assert.Equal("openclaw.cmd", config.OpenClaw.Executable);
            Assert.Equal(Environment.ExpandEnvironmentVariables("%USERPROFILE%\\.openclaw\\openclaw.json"), config.OpenClaw.ConfigPath);
            Assert.Equal("loopback", config.Network.Bind);
            Assert.Equal(19001, config.Network.Port);
        }
        finally
        {
            Directory.Delete(dataRoot, recursive: true);
        }
    }

    [Fact]
    public void CommandResolver_ResolvesCmdShimFromPath()
    {
        var tempDirectory = Path.Combine(Path.GetTempPath(), "OpenClaw.Agent.Tests", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(tempDirectory);
        var shimPath = Path.Combine(tempDirectory, "openclaw.cmd");
        File.WriteAllText(shimPath, "@echo off");

        using var pathScope = new EnvironmentVariableScope("PATH", tempDirectory + Path.PathSeparator + Environment.GetEnvironmentVariable("PATH"));

        var resolver = new OpenClawCommandResolver();
        var config = new AgentConfig
        {
            OpenClaw = new OpenClawLaunchConfig
            {
                Executable = "openclaw",
                Arguments = ["--alpha"]
            },
            Network = new NetworkConfig
            {
                Bind = "loopback",
                Port = 18080
            }
        };

        var resolved = resolver.Resolve(config);

        Assert.Equal(ResolvedCommandKind.CmdShim, resolved.CommandKind);
        Assert.EndsWith("openclaw.cmd", resolved.ResolvedExecutablePath, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("--alpha", resolved.EffectiveArguments);
        Assert.Contains("gateway", resolved.EffectiveArguments);
        Assert.Contains("run", resolved.EffectiveArguments);

        Directory.Delete(tempDirectory, recursive: true);
    }
}
