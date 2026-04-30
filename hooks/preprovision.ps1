#!/usr/bin/env pwsh
# Deploys the platform layer (Log Analytics Workspace) before the app layer is provisioned.
# Outputs (lawName, lawResourceGroupName) are written to the azd environment so that
# infra/app/main.parameters.json can reference them via ${PLATFORM_LAW_NAME} and ${PLATFORM_LAW_RG}.

$ErrorActionPreference = 'Stop'

$envName        = azd env get-value AZURE_ENV_NAME
$location       = azd env get-value AZURE_LOCATION
$subscriptionId = azd env get-value AZURE_SUBSCRIPTION_ID

Write-Host "Deploying platform layer for environment '$envName' in subscription '$subscriptionId'..."

$result = az deployment sub create `
    --subscription $subscriptionId `
    --location     $location `
    --name         "platform-$envName" `
    --template-file "infra/platform/main.bicep" `
    --parameters   environmentName=$envName location=$location `
    --output json | ConvertFrom-Json

if ($LASTEXITCODE -ne 0) {
    Write-Error "Platform layer deployment failed."
    exit 1
}

$lawName = $result.properties.outputs.lawName.value
$lawRg   = $result.properties.outputs.lawResourceGroupName.value

Write-Host "Platform layer deployed. LAW: '$lawName' in resource group: '$lawRg'"

azd env set PLATFORM_LAW_NAME $lawName
azd env set PLATFORM_LAW_RG   $lawRg
