using Microsoft.Win32;

namespace OpenClaw.Agent.Core;

public interface IRegistryAccessor
{
    string? GetValue(string keyPath, string valueName);
    void SetValue(string keyPath, string valueName, string value);
    void DeleteValue(string keyPath, string valueName);
}

public sealed class RegistryAccessor : IRegistryAccessor
{
    public string? GetValue(string keyPath, string valueName)
    {
        using var key = Registry.CurrentUser.OpenSubKey(keyPath, writable: false);
        return key?.GetValue(valueName)?.ToString();
    }

    public void SetValue(string keyPath, string valueName, string value)
    {
        using var key = Registry.CurrentUser.CreateSubKey(keyPath);
        key.SetValue(valueName, value);
    }

    public void DeleteValue(string keyPath, string valueName)
    {
        using var key = Registry.CurrentUser.OpenSubKey(keyPath, writable: true);
        key?.DeleteValue(valueName, throwOnMissingValue: false);
    }
}

public sealed class AutostartManager
{
    private readonly IRegistryAccessor _registryAccessor;

    public AutostartManager(IRegistryAccessor? registryAccessor = null)
    {
        _registryAccessor = registryAccessor ?? new RegistryAccessor();
    }

    public AutostartStatus GetStatus(string expectedHostPath)
    {
        var registryValue = _registryAccessor.GetValue(AgentConstants.AutostartRegistryKeyPath, AgentConstants.AutostartRegistryValueName);
        var expectedValue = BuildRegistryValue(expectedHostPath);
        return new AutostartStatus
        {
            Enabled = !string.IsNullOrWhiteSpace(registryValue),
            PathMatches = string.Equals(registryValue, expectedValue, StringComparison.OrdinalIgnoreCase),
            RegistryValue = registryValue,
            ExpectedValue = expectedValue
        };
    }

    public AutostartStatus Enable(string expectedHostPath)
    {
        ValidateStablePublishPath(expectedHostPath);
        var expectedValue = BuildRegistryValue(expectedHostPath);
        _registryAccessor.SetValue(AgentConstants.AutostartRegistryKeyPath, AgentConstants.AutostartRegistryValueName, expectedValue);
        return GetStatus(expectedHostPath);
    }

    public void Disable()
    {
        _registryAccessor.DeleteValue(AgentConstants.AutostartRegistryKeyPath, AgentConstants.AutostartRegistryValueName);
    }

    public static string BuildRegistryValue(string hostPath)
    {
        return $"\"{hostPath}\" --autostart";
    }

    private static void ValidateStablePublishPath(string hostPath)
    {
        if (!File.Exists(hostPath))
        {
            throw new FileNotFoundException($"Host executable not found: {hostPath}", hostPath);
        }

        var directory = Path.GetDirectoryName(hostPath) ?? throw new InvalidOperationException($"No parent directory for '{hostPath}'.");
        if (!PathHelpers.IsStablePublishDirectory(directory))
        {
            throw new InvalidOperationException(
                $"Autostart can only be enabled from the stable publish layout ending in '{Path.Combine(AgentConstants.StablePublishTail)}'. Current directory: {directory}");
        }
    }
}
