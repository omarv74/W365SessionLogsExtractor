# Windows 365 CloudPC Session Logs Extractor

This repository contains an Azure Functions application that extracts Windows 365 Cloud PC session logs from the Microsoft Graph API and writes them to Azure Blob Storage for analysis. The infrastructure is defined in Bicep and can be provisioned and deployed using the Azure Developer CLI (`azd`).

The Function App leverages a Beta version of a Microsoft Graph API that surfaces Windows 365 Cloud PC session logs: `GET /beta/deviceManagement/virtualEndpoint/reports/getTotalAggregatedRemoteConnectionReports`.  

## Prerequisites for development

**Note**: This repository leveraged the <https://github.com/Azure-Samples/functions-quickstart-dotnet-azd> AZD sample. Review the README file in that repository for related prerequisites and details.

- [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0)
- [Azurite](https://learn.microsoft.com/azure/storage/common/storage-use-azurite) (for local Azure Storage emulation during development)
- [Azure Functions Core Tools](https://learn.microsoft.com/azure/azure-functions/functions-run-local?pivots=programming-language-csharp#install-the-azure-functions-core-tools)
- [Azure Developer CLI (`azd`)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd) (for provisioning and deploying to Azure)
- [Azure CLI (`az`)](https://learn.microsoft.com/cli/azure/install-azure-cli) (required by the `preprovision` hook, which deploys the platform layer — a shared Log Analytics Workspace — as a separate subscription-scoped deployment before the app layer is provisioned)
- An active **Azure subscription** with permissions to create resource groups and deploy resources
- A **Microsoft Entra ID identity** (your developer account or a managed identity) with the following permissions granted:
  - `CloudPC.Read.All` (Microsoft Graph application permission) — required to call the Windows 365 Graph API endpoint `GET /beta/deviceManagement/virtualEndpoint/reports/getTotalAggregatedRemoteConnectionReports`
  - `Storage Blob Data Contributor` on the provisioned storage account — required to write report data to Azure Blob Storage
  - See [src/EntraIDSetup/README.md](src/EntraIDSetup/README.md) for guidance on granting Microsoft Graph access to a managed identity
- To use **Visual Studio Code** to run and debug locally:
  - [Visual Studio Code](https://code.visualstudio.com/)
  - [Azure Functions extension](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-azurefunctions)
- To use **Visual Studio** to run and debug locally:
  - [Visual Studio 2022](https://visualstudio.microsoft.com/vs/) with the **Azure development** workload installed

## Prerequisites for deployment

- An active **Azure subscription** with Contributor access to the target subscription where the resources will be provisioned
- The **Azure Developer CLI (`azd`)** installed and configured to authenticate to the target subscription
- The **Azure CLI (`az`)** installed and authenticated to the target subscription (used by the `preprovision` hook to deploy the platform layer)
- The **Microsoft Graph permission** `AppRoleAssignment.ReadWrite.All` (or Global Administrator) to allow the postprovision hook to assign application roles to managed identities

**Note**: For additional requirements and deployment instructions, see [SETUP.md](SETUP.md).  

## IMPORTANT: Graph API Request Filter is Hardcoded

The request payload sent to the Microsoft Graph API is currently hardcoded in [`GraphReportsService.cs`](src/W365LogsXfer/W365LogsXfer.Infrastructure/GraphReportsService.cs):

```csharp
var requestPayload = JsonSerializer.Serialize(new
{
    top = 25,
    skip = 0
});
```

The `top` value limits results to 25 rows and there is no `filter` applied. Update this payload as needed for your environment.

**References**:
- OData **filter** syntax: <https://learn.microsoft.com/en-us/graph/filter-query-parameter?tabs=http>
- OData **query** syntax: <https://learn.microsoft.com/en-us/odata/concepts/queryoptions-overview>

## IMPORTANT: `vnetEnabled` Controls Public vs. Private Endpoint Deployment

The `vnetEnabled` parameter determines whether the deployment is publicly accessible or locked down using Azure Private Endpoints. It is set per azd environment in `.azure/<env>/config.json`.

| `vnetEnabled` | Networking behavior |
|---|---|
| `true` | A Virtual Network is provisioned. The Function App is integrated with the VNet via its `app` subnet. Private endpoints are created for both storage accounts (functions backing storage and W365 logs storage), routing all storage traffic over the private network. |
| `false` | No VNet is provisioned. The Function App and both storage accounts are publicly accessible. |

When `vnetEnabled = true`, the Bicep provisions:

- A VNet (`10.0.0.0/16`) with two subnets:
  - `private-endpoints-subnet` (`10.0.1.0/24`) — hosts the private endpoints for both storage accounts
  - `app` (`10.0.2.0/24`) — used for Function App VNet integration
- Private endpoints for the **functions backing storage account** (Blob)
- Private endpoints for the **W365 logs storage account** (Blob)

> **Note**: The current Bicep contains open TODOs to also set `publicNetworkAccess: 'Disabled'` and `defaultAction: 'Deny'` on both storage accounts when `vnetEnabled = true`. Until those TODOs are resolved, the storage accounts remain publicly reachable even in VNet-enabled deployments. Review [`infra/app/main.bicep`](infra/app/main.bicep) before deploying to a production environment.



AZURE_ENV_NAME="W365Logs-SingleRG03"
AZURE_RESOURCE_GROUP="rg-BAD-$(azd env get-value AZURE_ENV_NAME)"

azd env set AZURE_RESOURCE_GROUP="rg-app-$(azd env get-value AZURE_ENV_NAME)" VNET_ENABLED="true" AZURE_REGION="centralus" AZURE_LOCATION="centralus" PLATFORM_RG_NAME="rg-app-$(azd env get-value AZURE_ENV_NAME)" APP_RG_NAME="rg-app-$(azd env get-value AZURE_ENV_NAME)" AZURE_SUBSCRIPTION_ID="748e6349-00e9-4051-9f9f-6de25d8cc477" APP_STORAGE_ACCOUNT_NAME="w365files"