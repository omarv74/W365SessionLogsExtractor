using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Azure.Core;
using Microsoft.Extensions.Logging;
using W365LogsXFer.Application;

namespace W365LogsXfer.Infrastructure;

internal sealed class GraphReportsService : IGraphReportsService
{
    private static readonly Uri ReportsEndpoint = new(
        "https://graph.microsoft.com/beta/deviceManagement/virtualEndpoint/reports/getTotalAggregatedRemoteConnectionReports");
    private static readonly string[] GraphScopes = ["https://graph.microsoft.com/.default"];
    private static readonly JsonSerializerOptions JsonOptions = new() { PropertyNameCaseInsensitive = true };

    private readonly HttpClient _httpClient = new();
    private readonly TokenCredential _credential;
    private readonly ILogger<GraphReportsService> _logger;

    public GraphReportsService(TokenCredential credential, ILogger<GraphReportsService> logger)
    {
        _credential = credential;
        _logger = logger;
    }

    public async Task<CloudPcConnectionReport> GetTotalAggregatedRemoteConnectionReportsAsync(CancellationToken cancellationToken = default)
    {
        _logger.LogInformation("Acquiring token for Microsoft Graph...");
        var tokenResult = await _credential.GetTokenAsync(
            new TokenRequestContext(GraphScopes), cancellationToken);

        //var requestPayload = JsonSerializer.Serialize(new
        //{
        //    top = 1000,
        //    skip = 0,
        //    filter = "",
        //    select = Array.Empty<string>(),
        //    orderBy = Array.Empty<string>()
        //});

        // ToDo: Make this an Application Settings configurable parameter *** or implement pagination to retrieve all rows if TotalRowCount exceeds the top value. 
        var requestPayload = JsonSerializer.Serialize(new
        {
            top = 25,
            skip = 0
        });

        using var request = new HttpRequestMessage(HttpMethod.Post, ReportsEndpoint);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", tokenResult.Token);
        request.Content = new StringContent(requestPayload, Encoding.UTF8, "application/json");

        _logger.LogInformation("Calling Graph API: POST {Endpoint}", ReportsEndpoint);
        using var response = await _httpClient.SendAsync(request, cancellationToken);
        response.EnsureSuccessStatusCode();

        var json = await response.Content.ReadAsStringAsync(cancellationToken);
        var raw = JsonSerializer.Deserialize<RawReport>(json, JsonOptions)
            ?? throw new InvalidOperationException("Graph API returned null response.");

        _logger.LogInformation("Graph API returned {TotalRowCount} total rows.", raw.TotalRowCount);

        var columns = raw.Schema.Select(s => s.Column).ToList();
        var rows = raw.Values
            .Select(row => (IReadOnlyList<string?>)row
                .Select(cell => cell.ValueKind == JsonValueKind.Null ? null : cell.ToString())
                .ToList())
            .ToList();

        return new CloudPcConnectionReport
        {
            TotalRowCount = raw.TotalRowCount,
            Columns = columns.AsReadOnly(),
            Rows = rows.AsReadOnly()
        };
    }

    private sealed record RawReport(int TotalRowCount, List<ColumnSchema> Schema, List<List<JsonElement>> Values);
    private sealed record ColumnSchema(string Column, string PropertyType);
}
