using OpenClaw.Agent.Cli;
using OpenClaw.Agent.Core;
using OpenClaw.Agent.Protocol;

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

    [Fact]
    public void WrapperConfigMigrator_CreatesAgentConfig_AndReportsRetiredFields()
    {
        var dataRoot = TestSupport.CreateTempDataRoot();
        var wrapperPath = Path.Combine(dataRoot, "service-config.json");
        var outputPath = Path.Combine(dataRoot, "config", "agent.json");
        Directory.CreateDirectory(Path.Combine(dataRoot, "config"));
        File.WriteAllText(
            wrapperPath,
            """
            {
              "serviceName": "OpenClawService",
              "displayName": "OpenClaw Local",
              "bind": "loopback",
              "port": 18888,
              "configPath": "%USERPROFILE%\\.openclaw\\openclaw.json",
              "openclawCommand": "\"C:\\Program Files\\OpenClaw\\openclaw.cmd\" --channel local",
              "winswVersion": "2.12.0",
              "httpProxy": "http://127.0.0.1:8080",
              "tray": {
                "title": "OpenClaw Local",
                "notifications": "errorsOnly"
              }
            }
            """);

        try
        {
            var migrator = new WrapperConfigMigrator();
            var result = migrator.InitializeConfig(wrapperPath, outputPath, overwrite: false);
            var paths = TestSupport.GetPaths(dataRoot);
            paths = new AgentPaths
            {
                DataRoot = paths.DataRoot,
                ConfigDirectory = paths.ConfigDirectory,
                StateDirectory = paths.StateDirectory,
                LogsDirectory = paths.LogsDirectory,
                ConfigPath = outputPath,
                HostStatePath = paths.HostStatePath,
                RunStatePath = paths.RunStatePath,
                AgentLogPath = paths.AgentLogPath,
                StdOutLogPath = paths.StdOutLogPath,
                StdErrLogPath = paths.StdErrLogPath
            };
            var loader = new AgentConfigLoader();
            var config = loader.Load(paths);

            Assert.True(result.Success);
            Assert.Contains("serviceName", result.RetiredFields);
            Assert.Contains("winswVersion", result.RetiredFields);
            Assert.Equal(18888, config.Network.Port);
            Assert.Equal("C:\\Program Files\\OpenClaw\\openclaw.cmd", config.OpenClaw.Executable);
            Assert.Equal(["--channel", "local"], config.OpenClaw.Arguments);
            Assert.Equal("OpenClaw Local", config.Tray.Title);
            Assert.Equal("errorsOnly", config.Tray.Notifications);
            Assert.Equal("http://127.0.0.1:8080", config.Proxy.HttpProxy);
        }
        finally
        {
            Directory.Delete(dataRoot, recursive: true);
        }
    }

    [Fact]
    public void WrapperConfigMigrator_RejectsNonLoopbackBind()
    {
        var dataRoot = TestSupport.CreateTempDataRoot();
        var wrapperPath = Path.Combine(dataRoot, "service-config.json");
        File.WriteAllText(
            wrapperPath,
            """
            {
              "bind": "0.0.0.0"
            }
            """);

        try
        {
            var migrator = new WrapperConfigMigrator();
            var error = Assert.Throws<InvalidOperationException>(() =>
                migrator.InitializeConfig(wrapperPath, Path.Combine(dataRoot, "config", "agent.json"), overwrite: false));

            Assert.Contains("loopback", error.Message, StringComparison.OrdinalIgnoreCase);
        }
        finally
        {
            Directory.Delete(dataRoot, recursive: true);
        }
    }

    [Fact]
    public async Task Cli_InitConfig_WritesAgentConfig_FromWrapperConfig()
    {
        var dataRoot = TestSupport.CreateTempDataRoot();
        var wrapperPath = Path.Combine(dataRoot, "service-config.json");
        File.WriteAllText(
            wrapperPath,
            """
            {
              "serviceName": "OpenClawService",
              "bind": "loopback",
              "port": 18801,
              "configPath": "%USERPROFILE%\\.openclaw\\openclaw.json",
              "openclawCommand": "openclaw.cmd --profile local",
              "tray": {
                "title": "OpenClaw Local"
              }
            }
            """);

        try
        {
            using var dataRootScope = new EnvironmentVariableScope(AgentConstants.DataRootOverrideEnvironmentVariable, dataRoot);
            using var hostPathScope = new EnvironmentVariableScope(AgentConstants.HostPathOverrideEnvironmentVariable, TestSupport.HostExecutablePath);
            var output = new StringWriter();
            var error = new StringWriter();
            var cli = new CliApplication(output, error);

            var exitCode = await cli.RunAsync(["init-config", "--from-wrapper", wrapperPath, "--json"], CancellationToken.None);
            var payload = AgentJson.Deserialize<InitConfigPayload>(output.ToString())!;

            Assert.Equal(0, exitCode);
            Assert.True(payload.Success);
            Assert.Contains("serviceName", payload.RetiredFields);
            Assert.True(File.Exists(Path.Combine(dataRoot, "config", AgentConstants.DefaultConfigFileName)));
        }
        finally
        {
            Directory.Delete(dataRoot, recursive: true);
        }
    }
}
