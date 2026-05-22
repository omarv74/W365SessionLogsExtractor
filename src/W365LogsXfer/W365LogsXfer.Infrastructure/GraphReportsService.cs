using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Azure.Core;
using Microsoft.Graph.Beta.DeviceManagement.VirtualEndpoint.Reports.GetRemoteConnectionHistoricalReports;
using Microsoft.Extensions.Logging;
using W365LogsXFer.Application;

namespace W365LogsXfer.Infrastructure;

internal sealed class GraphReportsService : IGraphReportsService
{
    private static readonly Uri TotalAggregatedReportsEndpoint = new(
        "https://graph.microsoft.com/beta/deviceManagement/virtualEndpoint/reports/getTotalAggregatedRemoteConnectionReports");
    private static readonly Uri HistoricalReportsEndpoint = new(
        "https://graph.microsoft.com/beta/deviceManagement/virtualEndpoint/reports/getRemoteConnectionHistoricalReports");
    private static readonly string[] GraphScopes = ["https://graph.microsoft.com/.default"];
    private static readonly JsonSerializerOptions JsonOptions = new() { PropertyNameCaseInsensitive = true };
    private const int MaxLoggedPayloadLength = 4096;
    private static readonly string[] HistoricalReportSelectColumns =
    [
        "SignInDateTime",
        "CloudPcId",
        "ActivityId",
        "ManagedDeviceName",
        "SignOutDateTime",
        "UsageInHour",
        "RoundTripTimeInMsP50",
        "AvailableBandwidthInMBpsP50",
        "AvailableBandwidthInMbpsP501",
        "RemoteSignInTimeInSec",
        "ConnectionProtocol",
        "ConnectionGateway",
        "ConnectionClientIP",
        "RTTAboveThreshold"
    ];

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
        //var requestPayload = JsonSerializer.Serialize(new
        //{
        //    top = 1000,
        //    skip = 0,
        //    filter = "",
        //    select = Array.Empty<string>(),
        //    orderBy = Array.Empty<string>()
        //});

        // ToDo: Make this an Application Settings configurable parameter *** or implement pagination to retrieve all rows if TotalRowCount exceeds the top value. 
        return await ExecuteReportRequestAsync(TotalAggregatedReportsEndpoint, new
        {
            top = 25,
            skip = 0
        }, cancellationToken);
    }

    public async Task<CloudPcConnectionReport> GetRemoteConnectionHistoricalReportsAsync(string cloudPcId, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(cloudPcId))
            throw new ArgumentException("CloudPcId must be provided.", nameof(cloudPcId));

        var safeCloudPcId = cloudPcId.Replace("'", "''", StringComparison.Ordinal);
        var requestBody = new GetRemoteConnectionHistoricalReportsPostRequestBody
        {
            Filter = $"CloudPcId eq '{safeCloudPcId}'",
            Select =
            [
                "SignInDateTime",
                "CloudPcId",
                "ActivityId",
                "ManagedDeviceName",
                "SignOutDateTime",
                "UsageInHour",
                "RoundTripTimeInMsP50",
                "AvailableBandwidthInMBpsP50",
                "AvailableBandwidthInMbpsP501",
                "RemoteSignInTimeInSec",
                "ConnectionProtocol",
                "ConnectionGateway",
                "ConnectionClientIP",
                "RTTAboveThreshold"
            ],
            Top = 25,
            Skip = 0
        };

        return await ExecuteReportRequestAsync(HistoricalReportsEndpoint, requestBody, cancellationToken);
    }

    private async Task<CloudPcConnectionReport> ExecuteReportRequestAsync(
        Uri endpoint,
        object requestBody,
        CancellationToken cancellationToken)
    {
        _logger.LogInformation("Acquiring token for Microsoft Graph...");
        var tokenResult = await _credential.GetTokenAsync(
            new TokenRequestContext(GraphScopes), cancellationToken);

        var requestPayload = JsonSerializer.Serialize(requestBody);

        using var request = new HttpRequestMessage(HttpMethod.Post, endpoint);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", tokenResult.Token);
        request.Content = new StringContent(requestPayload, Encoding.UTF8, "application/json");

        _logger.LogInformation(
            "Calling Graph API: POST {Endpoint}. Request payload: {RequestPayload}",
            endpoint,
            TruncateForLog(requestPayload));
        _logger.LogInformation("Graph API RequestBody: {RequestBody}", TruncateForLog(requestPayload));
        using var response = await _httpClient.SendAsync(request, cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            var errorContent = await response.Content.ReadAsStringAsync(cancellationToken);
            _logger.LogError(
                "Graph API call failed. Endpoint: {Endpoint}. Status: {StatusCode} ({ReasonPhrase}). Request payload: {RequestPayload}. Response body: {ResponseBody}",
                endpoint,
                (int)response.StatusCode,
                response.ReasonPhrase,
                TruncateForLog(requestPayload),
                TruncateForLog(errorContent));

            throw new HttpRequestException(
                $"Graph API call failed for endpoint '{endpoint}' with status code {(int)response.StatusCode} ({response.ReasonPhrase}). Response body: {TruncateForLog(errorContent)}",
                null,
                response.StatusCode);
        }

        var json = await response.Content.ReadAsStringAsync(cancellationToken);
        var raw = JsonSerializer.Deserialize<RawReport>(json, JsonOptions)
            ?? throw new InvalidOperationException("Graph API returned null response.");

        _logger.LogInformation("Graph API returned {TotalRowCount} total rows for endpoint {Endpoint}.", raw.TotalRowCount, endpoint);

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

    private static string TruncateForLog(string? value)
    {
        if (string.IsNullOrEmpty(value) || value.Length <= MaxLoggedPayloadLength)
            return value ?? string.Empty;

        return string.Concat(value.AsSpan(0, MaxLoggedPayloadLength), "... [truncated]");
    }
}
