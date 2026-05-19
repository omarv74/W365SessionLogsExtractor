# Setup Guide

This project is configured so that it can be deployed to Azure using the [Azure Developer CLI (`azd`)](https://learn.microsoft.com/azure/developer/azure-developer-cli/overview).

## Important  

Some required permissions cannot be granted through the Azure Portal (not supported at the time of this writing). The post-deployment script (`hooks/postprovision.ps1`) that grants Microsoft Graph permissions to the Function App's managed identity contains all the necessary logic to assign the required application roles. However, it is currently commented out in the azure.yaml hooks configuration due to the fact that not all developers may have the required permissions to execute it successfully. So post-provision steps must be executed manually *and* must be executed from a standalone Windows Terminal (PowerShell 7+), as one of the steps (the `Connect-MgGraph` cmdlet) will trigger an authetication workflow (in addition to the `az login` workflow) and, if executed from within an embedded Terminal, as in from the VS Code integrated terminal, the authentication prompt may not surface correctly.  

Only the postprovision script needs to be executed from a standalone Windows Terminal. Everything before that, can be deployed by running `azd-up` from the VS Code integrated terminal, or from any terminal of choice.

---

## Prerequisites

| Requirement | Notes |
|---|---|
| [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd) | `azd` orchestrates provisioning and deployment |
| [Azure CLI (`az`)](https://learn.microsoft.com/cli/azure/install-azure-cli) | Used by the `preprovision` hook to deploy the platform layer |
| [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0) | Required to build the Function App |
| [PowerShell 7+](https://learn.microsoft.com/powershell/scripting/install/installing-powershell) | Required for provisioning hooks |
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

## Infrastructure Layers

The Azure infrastructure is split into two independently deployable layers, each with its own resource group:

| Layer | Bicep entry point | Resource group | Contains |
|---|---|---|---|
| **Platform** | `infra/platform/main.bicep` | `rg-{env}-platform` | Log Analytics Workspace |
| **App** | `infra/app/main.bicep` | `rg-{env}` | Function App, storage accounts, App Insights, managed identity, RBAC, optional VNet |

The platform layer is designed to hold shared infrastructure that may already exist in a tenant. When deployed via `azd up`, the `preprovision` hook always deploys the platform layer idempotently — re-running it updates in place rather than creating a duplicate.

The app layer receives the Log Analytics Workspace details via the `existingLAWName` and `existingLAWResourceGroup` parameters (both optional, defaulting to empty string):

- When using `azd up`, these are populated automatically by the `preprovision` hook via the `PLATFORM_LAW_NAME` and `PLATFORM_LAW_RG` environment variables.
- When using the composition template (`infra/main.bicep`) directly, they are driven by the `deployPlatformLayer` parameter:
  - `deployPlatformLayer = true` — the template deploys the platform layer itself and automatically wires its Log Analytics Workspace outputs to the app layer.
  - `deployPlatformLayer = false` *(default)* — the platform layer is skipped; supply the existing LAW details via `existingLAWName` and `existingLAWResourceGroup` (or the corresponding `PLATFORM_LAW_NAME`/`PLATFORM_LAW_RG` env vars referenced in `infra/main.parameters.json`).

> **Note**: `infra/main.bicep` is a composition template for direct CLI deployments only. When using `azd up`, the entry point is `infra/app/main.bicep` (configured by `infra.path: infra/app` in `azure.yaml`); the `deployPlatformLayer` parameter has no effect on the `azd` flow.

---

## Deploy

Run the following command from the repository root. It provisions all Azure infrastructure and deploys the Function App in a single step:

```shell
azd up
```

This command:

1. Creates (or reuses) an azd environment
2. Runs the **`preprovision` hook** — deploys the platform layer (Log Analytics Workspace) via `az deployment sub create` and writes `PLATFORM_LAW_NAME` and `PLATFORM_LAW_RG` to the azd environment
3. Runs `azd provision` — applies `infra/app/main.bicep` using those env vars to create all app-layer resources
4. Runs `azd deploy` — builds and publishes the .NET Function App to the resource group identified by the `AZURE_RESOURCE_GROUP` output
5. Runs any remaining registered **azd hooks** (see below)

To provision infrastructure only (without deploying code):

```shell
azd provision
```

To deploy code to already-provisioned infrastructure:

```shell
azd deploy
```

### Deploying layers independently

Each layer can also be deployed directly with the Azure CLI, bypassing `azd` entirely:

```powershell
# Platform layer only

  az deployment sub create --location "westus" --name platform-01 --template-file platform/main.bicep --parameters platform/main.parameters.json --parameters platformResourceGroupName="rg-itss-w365-audit-logs-dev"

# App layer only (requires LAW to already exist)
az deployment sub create \
  --location <location> \
  --name app-<envName> \
  --template-file infra/app/main.bicep \
  --parameters infra/app/main.parameters.json \
    existingLAWName=<lawName> \
    existingLAWResourceGroup=<lawResourceGroup>
```

Alternatively, use the composition template (`infra/main.bicep`) to deploy both layers together in a single subscription-scoped deployment. Set `deployPlatformLayer=true` for a new environment, or `false` to reuse an existing platform layer:

```powershell
# Composition template — platform + app together (new environment)
az deployment sub create \
  --location <location> \
  --name <envName> \
  --template-file infra/main.bicep \
  --parameters infra/main.parameters.json \
    deployPlatformLayer=true

# Composition template — app only, reusing an existing platform layer
az deployment sub create \
  --location <location> \
  --name <envName> \
  --template-file infra/main.bicep \
  --parameters infra/main.parameters.json \
    deployPlatformLayer=false \
    existingLAWName=<lawName> \
    existingLAWResourceGroup=<lawResourceGroup>
```

---

## azd Hooks

Hooks let azd run scripts at defined points in the lifecycle. They are declared in [`azure.yaml`](./azure.yaml) and the scripts live in the [`hooks/`](./hooks/) folder.

### `preprovision` — Deploy the platform layer

**Script**: [`hooks/preprovision.ps1`](./hooks/preprovision.ps1)

**When it runs**: Automatically before `azd provision` (and therefore before `azd up`) starts.

**What it does**:

1. Reads `AZURE_ENV_NAME`, `AZURE_LOCATION`, and `AZURE_SUBSCRIPTION_ID` from the azd environment
2. Runs `az deployment sub create` targeting `infra/platform/main.bicep` — idempotent; a stable deployment name (`platform-{env}`) means re-runs update in place
3. Reads `lawName` and `lawResourceGroupName` from the deployment outputs
4. Writes them back into the azd environment as `PLATFORM_LAW_NAME` and `PLATFORM_LAW_RG`, ready for `infra/app/main.parameters.json` to consume

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

> **Note**: `azd down` only removes resources in the app-layer resource group (`rg-{env}`), because that is the group tracked by `azd`. The platform-layer resource group (`rg-{env}-platform`) must be deleted separately if no longer needed:
>
> ```powershell
> az group delete --name rg-<envName>-platform --yes
> ```
