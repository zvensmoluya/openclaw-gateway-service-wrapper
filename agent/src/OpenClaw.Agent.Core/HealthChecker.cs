using System.Net.Http;

namespace OpenClaw.Agent.Core;

public sealed class HealthChecker
{
    private readonly HttpClient _httpClient;

    public HealthChecker(HttpClient? httpClient = null)
    {
        _httpClient = httpClient ?? new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(8)
        };
    }

    public async Task<HealthSnapshot> CheckAsync(string url, CancellationToken cancellationToken)
    {
        try
        {
            using var response = await _httpClient.GetAsync(url, cancellationToken);
            var body = await response.Content.ReadAsStringAsync(cancellationToken);
            return new HealthSnapshot
            {
                Ok = response.IsSuccessStatusCode,
                StatusCode = (int)response.StatusCode,
                Body = body,
                Error = response.IsSuccessStatusCode ? null : $"HTTP {(int)response.StatusCode}",
                ObservedAt = DateTimeOffset.UtcNow
            };
        }
        catch (Exception ex)
        {
            return new HealthSnapshot
            {
                Ok = false,
                Error = ex.Message,
                ObservedAt = DateTimeOffset.UtcNow
            };
        }
    }
}
