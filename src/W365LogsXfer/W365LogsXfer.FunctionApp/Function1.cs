using System.Diagnostics;
using System.Text;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using W365LogsXFer.Application;

namespace W365LogsXfer.FunctionApp;

public class Function1
{
    private readonly ILogger<Function1> _logger;
    private readonly IBlobUploadService _blobUploadService;
    private readonly IGraphReportsService _graphReportsService;

    public Function1(ILogger<Function1> logger, IBlobUploadService blobUploadService, IGraphReportsService graphReportsService)
    {
        _logger = logger;
        _blobUploadService = blobUploadService;
        _graphReportsService = graphReportsService;
        _logger.LogInformation("Function1 instance created");
    }

    [Function("Function1")]
    public async Task<IActionResult> Run([HttpTrigger(AuthorizationLevel.Anonymous, "get", "post")] HttpRequest req)
    {
        var requestId = Guid.NewGuid().ToString("N")[..8];
        var stopwatch = Stopwatch.StartNew();
        var ct = req.HttpContext.RequestAborted;

        _logger.LogInformation("========================================");
        _logger.LogInformation("[{RequestId}] Function1 triggered", requestId);
        _logger.LogInformation("[{RequestId}]   - Method: {Method}", requestId, req.Method);
        _logger.LogInformation("[{RequestId}]   - Path: {Path}", requestId, req.Path);
        _logger.LogInformation("[{RequestId}]   - Query String: {QueryString}", requestId, req.QueryString);

        try
        {
            const string containerName = "w365logs-inbound";
            var timestamp = DateTime.UtcNow.ToString("yyyy-MM-dd-HH-mm-ss");
            var blobName = $"getTotalAggregatedRemoteConnectionReports_{timestamp}.csv";

            _logger.LogInformation("[{RequestId}] Fetching Cloud PC connection report from Microsoft Graph", requestId);
            var fetchStopwatch = Stopwatch.StartNew();
            var report = await _graphReportsService.GetTotalAggregatedRemoteConnectionReportsAsync(ct);
            fetchStopwatch.Stop();
            _logger.LogInformation("[{RequestId}] Graph API returned {RowCount} rows in {ElapsedMs}ms",
                requestId, report.TotalRowCount, fetchStopwatch.ElapsedMilliseconds);

            var csv = BuildCsv(report);

            _logger.LogInformation("[{RequestId}] Uploading '{BlobName}' to container '{ContainerName}'",
                requestId, blobName, containerName);
            var uploadStopwatch = Stopwatch.StartNew();
            await _blobUploadService.UploadAsync(containerName, blobName, csv, ct);
            uploadStopwatch.Stop();
            _logger.LogInformation("[{RequestId}] Upload completed in {ElapsedMs}ms",
                requestId, uploadStopwatch.ElapsedMilliseconds);

            stopwatch.Stop();
            _logger.LogInformation("[{RequestId}] Function1 completed. Total: {TotalMs}ms",
                requestId, stopwatch.ElapsedMilliseconds);
            _logger.LogInformation("========================================");

            return new OkObjectResult(new
            {
                Message = "Report saved successfully.",
                RequestId = requestId,
                Container = containerName,
                Blob = blobName,
                TotalRowCount = report.TotalRowCount,
                FetchTimeMs = fetchStopwatch.ElapsedMilliseconds,
                UploadTimeMs = uploadStopwatch.ElapsedMilliseconds,
                TotalTimeMs = stopwatch.ElapsedMilliseconds,
                Timestamp = DateTime.UtcNow
            });
        }
        catch (Exception ex)
        {
            stopwatch.Stop();
            _logger.LogError(ex, "[{RequestId}] Function1 failed after {ElapsedMs}ms: {ErrorMessage}",
                requestId, stopwatch.ElapsedMilliseconds, ex.Message);
            if (ex.InnerException != null)
                _logger.LogError("[{RequestId}] Inner exception: {InnerMessage}", requestId, ex.InnerException.Message);
            _logger.LogInformation("========================================");

            return new ObjectResult(new
            {
                Error = "Function execution failed",
                RequestId = requestId,
                Message = ex.Message,
                ExceptionType = ex.GetType().Name,
                Timestamp = DateTime.UtcNow
            })
            { StatusCode = 500 };
        }
    }

    private static string BuildCsv(CloudPcConnectionReport report)
    {
        var sb = new StringBuilder();
        sb.AppendLine(string.Join(",", report.Columns.Select(EscapeCsvField)));
        foreach (var row in report.Rows)
            sb.AppendLine(string.Join(",", row.Select(EscapeCsvField)));
        return sb.ToString();
    }

    private static string EscapeCsvField(string? value)
    {
        if (value is null) return "";
        if (value.Contains(',') || value.Contains('"') || value.Contains('\n'))
            return $"\"{value.Replace("\"", "\"\"")}\"";
        return value;
    }
}