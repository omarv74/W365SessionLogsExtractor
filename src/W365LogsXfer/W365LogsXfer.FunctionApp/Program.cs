using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using W365LogsXfer.Infrastructure;

var builder = FunctionsApplication.CreateBuilder(args);

// Configure logging
builder.Logging.AddConsole();
builder.Logging.SetMinimumLevel(LogLevel.Information);

var startupLogger = LoggerFactory.Create(config => config.AddConsole())
    .CreateLogger("Startup");

startupLogger.LogInformation("=== Starting W365LogsXfer Function App ===");
startupLogger.LogInformation("Environment: {Environment}", builder.Environment.EnvironmentName);

try
{
    builder.ConfigureFunctionsWebApplication();
    startupLogger.LogInformation("Functions web application configured successfully");

    builder.Services
        .AddApplicationInsightsTelemetryWorkerService()
        .ConfigureFunctionsApplicationInsights();
    startupLogger.LogInformation("Application Insights telemetry configured successfully");

    var storageAccountName = builder.Configuration["W365_LOGS_STORAGE_ACCOUNT_NAME"];
    var managedIdentityClientId = builder.Configuration["MANAGED_IDENTITY_CLIENT_ID"];

    startupLogger.LogInformation("Configuration values retrieved:");
    startupLogger.LogInformation("  - Storage Account Name: {StorageAccountName}", 
        string.IsNullOrEmpty(storageAccountName) ? "<NOT SET>" : storageAccountName);
    startupLogger.LogInformation("  - Managed Identity Client ID: {ManagedIdentityClientId}", 
        string.IsNullOrEmpty(managedIdentityClientId) ? "<NOT SET - Will use DefaultAzureCredential>" : "<SET>");

    if (string.IsNullOrEmpty(storageAccountName))
    {
        startupLogger.LogWarning("W365_LOGS_STORAGE_ACCOUNT_NAME is not configured. Blob operations may fail.");
    }

    builder.Services.AddW365LogsInfrastructure(
        storageAccountName: storageAccountName!,
        managedIdentityClientId: managedIdentityClientId);
    startupLogger.LogInformation("W365 Logs Infrastructure registered successfully");

    var app = builder.Build();
    startupLogger.LogInformation("Application built successfully. Starting host...");

    app.Run();
}
catch (Exception ex)
{
    startupLogger.LogCritical(ex, "Application startup failed with critical error: {ErrorMessage}", ex.Message);
    throw;
}
