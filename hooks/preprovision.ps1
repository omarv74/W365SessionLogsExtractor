#!/usr/bin/env pwsh
# Creates both resource groups (platform and app) then deploys the platform layer
# (Log Analytics Workspace) before the app layer is provisioned.
# Outputs (lawName, lawResourceGroupName) are written to the azd environment so that
# infra/app/main.parameters.json can reference them via ${PLATFORM_LAW_NAME} and ${PLATFORM_LAW_RG}.

$ErrorActionPreference = 'Stop'

$envName        = azd env get-value AZURE_ENV_NAME
$location       = azd env get-value AZURE_LOCATION
$subscriptionId = azd env get-value AZURE_SUBSCRIPTION_ID

# Determine app resource group name
$appRgName = azd env get-value APP_RG_NAME
if ([string]::IsNullOrWhiteSpace($appRgName)) {
    $appRgName = "rg-app-$envName"
}

# Determine platform resource group name
$platformRgName = azd env get-value PLATFORM_RG_NAME
if ([string]::IsNullOrWhiteSpace($platformRgName)) {
    $platformRgName = "rg-platform-$envName"
}

# Create the platform resource group
Write-Host "Creating platform resource group '$platformRgName' in '$location'..."
az group create `
    --subscription  $subscriptionId `
    --name          $platformRgName `
    --location      $location

if ($LASTEXITCODE -ne 0) {
    Write-Error "Platform resource group creation failed."
    exit 1
}

# Create the app resource group (only if distinct from the platform resource group)
if ($appRgName -ne $platformRgName) {
    Write-Host "Creating app resource group '$appRgName' in '$location'..."
    az group create `
        --subscription  $subscriptionId `
        --name          $appRgName `
        --location      $location

    if ($LASTEXITCODE -ne 0) {
        Write-Error "App resource group creation failed."
        exit 1
    }
} else {
    Write-Host "App and platform resource groups are the same ('$appRgName'); skipping separate app RG creation."
}

# Persist app RG name — APP_RG_NAME is the user-facing variable;
# AZURE_RESOURCE_GROUP is the azd-required variable that controls which RG azd provisions into and tears down.
azd env set APP_RG_NAME        $appRgName
# azd env set AZURE_RESOURCE_GROUP $appRgName

# Deploy the platform layer (Log Analytics Workspace) into the platform resource group
Write-Host "Deploying platform layer for environment '$envName' in subscription '$subscriptionId'..."

$result = az deployment group create `
    --subscription  $subscriptionId `
    --resource-group $platformRgName `
    --name          "platform-$envName" `
    --template-file "infra/platform/main.bicep" `
    --parameters    environmentName=$envName location=$location `
    --output json | ConvertFrom-Json

if ($LASTEXITCODE -ne 0) {
    Write-Error "Platform layer deployment failed."
    exit 1
}

$lawName = $result.properties.outputs.lawName.value
$lawRg   = $result.properties.outputs.lawResourceGroupName.value

Write-Host "Platform layer deployed. LAW: '$lawName' in resource group: '$lawRg'"

azd env set PLATFORM_RG_NAME  $platformRgName
azd env set PLATFORM_LAW_NAME $lawName
azd env set PLATFORM_LAW_RG   $lawRg
