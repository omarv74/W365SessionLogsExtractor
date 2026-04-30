using System.Diagnostics;
using System.Text;
using Azure;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using Microsoft.Extensions.Logging;
using W365LogsXFer.Application;

namespace W365LogsXfer.Infrastructure;

internal sealed class AzureBlobUploadService : IBlobUploadService
{
    private readonly BlobServiceClient _blobServiceClient;
    private readonly ILogger<AzureBlobUploadService> _logger;

    public AzureBlobUploadService(BlobServiceClient blobServiceClient, ILogger<AzureBlobUploadService> logger)
    {
        _blobServiceClient = blobServiceClient;
        _logger = logger;
        _logger.LogInformation("AzureBlobUploadService initialized with account: {AccountName}", 
            _blobServiceClient.AccountName);
    }

    public async Task UploadAsync(string containerName, string blobName, string content, CancellationToken cancellationToken = default)
    {
        var operationId = Guid.NewGuid().ToString("N")[..8];
        var stopwatch = Stopwatch.StartNew();

        _logger.LogInformation("[{OperationId}] Starting blob upload operation", operationId);
        _logger.LogInformation("[{OperationId}] Container: {ContainerName}, Blob: {BlobName}, Content Length: {ContentLength} bytes", 
            operationId, containerName, blobName, content.Length);

        try
        {
            // Get container client
            _logger.LogDebug("[{OperationId}] Getting container client for: {ContainerName}", operationId, containerName);
            var containerClient = _blobServiceClient.GetBlobContainerClient(containerName);

            // Create container if it doesn't exist
            _logger.LogDebug("[{OperationId}] Ensuring container exists: {ContainerName}", operationId, containerName);
            var createContainerStopwatch = Stopwatch.StartNew();

            Response<BlobContainerInfo>? createResponse = await containerClient.CreateIfNotExistsAsync(
                cancellationToken: cancellationToken);

            createContainerStopwatch.Stop();

            if (createResponse?.Value != null)
            {
                _logger.LogInformation("[{OperationId}] Container '{ContainerName}' created successfully (took {ElapsedMs}ms)", 
                    operationId, containerName, createContainerStopwatch.ElapsedMilliseconds);
            }
            else
            {
                _logger.LogDebug("[{OperationId}] Container '{ContainerName}' already exists (check took {ElapsedMs}ms)", 
                    operationId, containerName, createContainerStopwatch.ElapsedMilliseconds);
            }

            // Get blob client
            _logger.LogDebug("[{OperationId}] Getting blob client for: {BlobName}", operationId, blobName);
            var blobClient = containerClient.GetBlobClient(blobName);
            _logger.LogDebug("[{OperationId}] Blob URI: {BlobUri}", operationId, blobClient.Uri);

            // Upload blob
            _logger.LogDebug("[{OperationId}] Converting content to stream ({ContentLength} bytes)", 
                operationId, content.Length);
            using var stream = new MemoryStream(Encoding.UTF8.GetBytes(content));

            _logger.LogInformation("[{OperationId}] Uploading blob to: {BlobUri}", operationId, blobClient.Uri);
            var uploadStopwatch = Stopwatch.StartNew();

            var uploadResponse = await blobClient.UploadAsync(stream, overwrite: true, cancellationToken: cancellationToken);

            uploadStopwatch.Stop();

            stopwatch.Stop();
            _logger.LogInformation(
                "[{OperationId}] Blob upload completed successfully. Upload time: {UploadMs}ms, Total time: {TotalMs}ms, ETag: {ETag}", 
                operationId, uploadStopwatch.ElapsedMilliseconds, stopwatch.ElapsedMilliseconds, uploadResponse.Value.ETag);
        }
        catch (RequestFailedException ex) when (ex.Status == 403)
        {
            stopwatch.Stop();
            _logger.LogError(ex, 
                "[{OperationId}] Blob upload failed with 403 Forbidden (after {ElapsedMs}ms). This typically indicates authentication or permission issues. " +
                "Ensure the identity has 'Storage Blob Data Contributor' role on the storage account.", 
                operationId, stopwatch.ElapsedMilliseconds);
            throw;
        }
        catch (RequestFailedException ex) when (ex.Status == 404)
        {
            stopwatch.Stop();
            _logger.LogError(ex, 
                "[{OperationId}] Blob upload failed with 404 Not Found (after {ElapsedMs}ms). The storage account may not exist or is not accessible.", 
                operationId, stopwatch.ElapsedMilliseconds);
            throw;
        }
        catch (RequestFailedException ex)
        {
            stopwatch.Stop();
            _logger.LogError(ex, 
                "[{OperationId}] Blob upload failed with Azure Storage error (after {ElapsedMs}ms). Status: {StatusCode}, ErrorCode: {ErrorCode}", 
                operationId, stopwatch.ElapsedMilliseconds, ex.Status, ex.ErrorCode);
            throw;
        }
        catch (OperationCanceledException)
        {
            stopwatch.Stop();
            _logger.LogWarning("[{OperationId}] Blob upload was cancelled (after {ElapsedMs}ms)", 
                operationId, stopwatch.ElapsedMilliseconds);
            throw;
        }
        catch (Exception ex)
        {
            stopwatch.Stop();
            _logger.LogError(ex, 
                "[{OperationId}] Blob upload failed with unexpected error (after {ElapsedMs}ms): {ErrorMessage}", 
                operationId, stopwatch.ElapsedMilliseconds, ex.Message);
            throw;
        }
    }
}
