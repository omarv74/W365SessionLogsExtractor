# Setup Guide

This project is configured so that it can be deployed to Azure using the [Azure Developer CLI (`azd`)](https://learn.microsoft.com/azure/developer/azure-developer-cli/overview).

## Important  

Some required permissions cannot be granted through the Azure Portal (not supported at the time of this writing). The `postprovision` hook (`hooks/postprovision.ps1`) runs **automatically** after `azd provision` / `azd up` completes and grants the `CloudPC.Read.All` application role to the Function App's managed identity. Not all developers will have the permissions required to execute this step successfully (see Prerequisites below).

The script is **interactive** — the `Connect-MgGraph` cmdlet triggers an authentication workflow that may not surface correctly inside an embedded terminal (e.g. the Terminal within VS Code). **Run `azd up` from a standalone Windows Terminal (PowerShell 7+)** so that the browser / device-code prompt can appear correctly.

---

## Prerequisites

| Requirement | Notes |
| --- | --- |
| [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd) | `azd` orchestrates provisioning and deployment |
| [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0) | Required to build the Function App |
| [PowerShell 7+](https://learn.microsoft.com/powershell/scripting/install/installing-powershell) | Required for the `postprovision` hook |
| [Microsoft.Graph PowerShell module](https://learn.microsoft.com/powershell/microsoftgraph/installation) | Used by the postprovision hook to assign Graph permissions |
| Azure subscription | The deploying identity needs Contributor access on the target subscription |
| Microsoft Graph permission | `AppRoleAssignment.ReadWrite.All` (or Global Administrator) to grant application roles to managed identities |

Install the Microsoft.Graph module if not already present:

```powershell
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
    Install-Module Microsoft.Graph -Scope CurrentUser
}
```

---

## Infrastructure

All Azure infrastructure is defined in a single layer under `infra/app/`:

| Bicep entry point | Resource group | Contains |
| --- | --- | --- |
| `infra/app/main.bicep` | `rg-{env}` | Function App (Flex Consumption), App Service Plan, two storage accounts (functions backing + W365 logs), Application Insights, user-assigned managed identity, RBAC role assignments, optional VNet with private endpoints |

When using `azd up`, the entry point is `infra/app/main.bicep` (configured by `infra.path: infra/app` in `azure.yaml`).

The `infra/main.bicep` file at the repository root is a lightweight composition wrapper that delegates to `infra/app/main.bicep`. It is intended for direct Azure CLI deployments only and has no effect on the `azd` flow.

---

## Deploy

### Environment variables setup example

```shell
azd env set AZURE_RESOURCE_GROUP="rg-$(azd env get-value AZURE_ENV_NAME)" VNET_ENABLED="true" AZURE_LOCATION="centralus" APP_STORAGE_ACCOUNT_NAME="w365files"
```

Run the following command from the repository root. It provisions all Azure infrastructure and deploys the Function App in a single step:

```shell
azd up
```

This command:

1. Creates (or reuses) an azd environment
2. Runs `azd provision` — applies `infra/app/main.bicep` to create all app-layer resources
3. Runs `azd deploy` — builds and publishes the .NET Function App to the resource group identified by the `AZURE_RESOURCE_GROUP` output
4. Runs the **`postprovision` hook** — grants the `CloudPC.Read.All` application role to the managed identity (interactive; see [Important](#important) above)

To provision infrastructure only (without deploying code):

```shell
azd provision
```

To deploy code to already-provisioned infrastructure:

```shell
azd deploy
```

### Deploying with the Azure CLI

The app layer can also be deployed directly with the Azure CLI, bypassing `azd` entirely:

```powershell
az deployment sub create \
  --location <location> \
  --name app-<envName> \
  --template-file infra/app/main.bicep \
  --parameters infra/app/main.parameters.json
```

Alternatively, use the composition wrapper (`infra/main.bicep`) which delegates to the same app layer:

```powershell
az deployment sub create \
  --location <location> \
  --name <envName> \
  --template-file infra/main.bicep \
  --parameters infra/main.parameters.json
```

---

## azd Hooks

Hooks let azd run scripts at defined points in the lifecycle. They are declared in [`azure.yaml`](./azure.yaml) and the scripts live in the [`hooks/`](./hooks/) folder.

### `postprovision` — Grant Microsoft Graph permissions

**Script**: [`hooks/postprovision.ps1`](./hooks/postprovision.ps1)

**When it runs**: Automatically after `azd provision` (and therefore after `azd up`) completes successfully.

**What it does**:

The Azure Function App calls the [Microsoft Graph beta API](https://learn.microsoft.com/graph/api/cloudpcreports-gettotalaggregatedremoteconnectionreports) to retrieve Windows 365 Cloud PC connection reports. At runtime the Function App authenticates through its **user-assigned managed identity**. Microsoft Graph requires that this managed identity be explicitly granted the `CloudPC.Read.All` application role — this cannot be done through Bicep/ARM today.

The `postprovision.ps1` script automates this step:

1. Reads the managed identity's object ID from the `MANAGED_IDENTITY_PRINCIPAL_ID` azd output (set by `infra/app/main.bicep`)
2. Connects to Microsoft Graph using the caller's credentials (`Connect-MgGraph`)
3. Looks up the Microsoft Graph service principal in the tenant
4. Checks whether `CloudPC.Read.All` is already assigned (idempotent — safe to run multiple times)
5. Calls `New-MgServicePrincipalAppRoleAssignment` to grant the role

The script is **interactive** — it will open a browser window or device-code prompt for `Connect-MgGraph` if the caller is not already authenticated.

---

## Tear Down

To delete all Azure resources created by this project:

```shell
azd down --force --purge
```

`--purge` permanently deletes any soft-delete-enabled resources (e.g. Key Vault) so that the same environment name can be reused immediately.
