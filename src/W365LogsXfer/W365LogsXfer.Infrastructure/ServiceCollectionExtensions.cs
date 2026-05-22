using Azure.Core;
using Azure.Identity;
using Azure.Storage.Blobs;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using W365LogsXFer.Application;

namespace W365LogsXfer.Infrastructure;

public static class ServiceCollectionExtensions
{
    public static IServiceCollection AddW365LogsInfrastructure(
        this IServiceCollection services,
        string storageAccountName,
        string? managedIdentityClientId)
    {
        var logger = LoggerFactory.Create(config => config.AddConsole())
            .CreateLogger("InfrastructureRegistration");

        logger.LogInformation("Registering W365 Logs Infrastructure services...");
        logger.LogInformation("Storage Account: {StorageAccountName}", storageAccountName);

        try
        {
            TokenCredential credential;
            if (!string.IsNullOrEmpty(managedIdentityClientId))
            {
                logger.LogInformation("Using ManagedIdentityCredential with Client ID: {ClientId}", 
                    managedIdentityClientId);
                credential = new ManagedIdentityCredential(managedIdentityClientId);
            }
            else
            {
                logger.LogInformation("Using DefaultAzureCredential (no Managed Identity Client ID specified)");
                logger.LogInformation("Authentication will attempt in order: Environment, Workload Identity, Managed Identity, Visual Studio, Azure CLI, Azure PowerShell, Interactive Browser");
                credential = new DefaultAzureCredential();
            }

            var blobServiceUri = new Uri($"https://{storageAccountName}.blob.core.windows.net");
            logger.LogInformation("Blob Service URI: {BlobServiceUri}", blobServiceUri);

            services.AddSingleton(new BlobServiceClient(blobServiceUri, credential));
            logger.LogInformation("BlobServiceClient registered successfully");

            services.AddSingleton<IBlobUploadService, AzureBlobUploadService>();
            logger.LogInformation("IBlobUploadService registered as AzureBlobUploadService");

            services.AddSingleton<TokenCredential>(credential);
            services.AddSingleton<IGraphReportsService, GraphReportsService>();
            logger.LogInformation("IGraphReportsService registered as GraphReportsService");

            logger.LogInformation("W365 Logs Infrastructure services registered successfully");
            return services;
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to register W365 Logs Infrastructure services: {ErrorMessage}", ex.Message);
            throw;
        }
    }
}
