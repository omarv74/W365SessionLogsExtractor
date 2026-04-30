namespace W365LogsXFer.Application;

public interface IBlobUploadService
{
    Task UploadAsync(string containerName, string blobName, string content, CancellationToken cancellationToken = default);
}
