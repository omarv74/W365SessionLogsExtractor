#!/usr/bin/env pwsh
# Post-provisioning hook: grants the CloudPC.Read.All application role to the managed identity.
#
# This script runs automatically after `azd provision` / `azd up` completes.
# It uses the caller's credentials (the identity running `azd`) to assign the
# Microsoft Graph `CloudPC.Read.All` application role to the user-assigned managed
# identity that the Azure Function App uses at runtime.
#
# Prerequisites (caller must have):
#   - Microsoft Graph permission: AppRoleAssignment.ReadWrite.All (or Global Administrator)
#   - Microsoft.Graph PowerShell module installed
#
# Environment variables injected by azd from Bicep outputs:
#   MANAGED_IDENTITY_PRINCIPAL_ID  – object ID of the user-assigned managed identity

param(
    [Parameter(Mandatory = $false)]
    [string]$ManagedIdentityPrincipalId
)

$ErrorActionPreference = 'Stop'

# ── Validation helper ──────────────────────────────────────────────────────────
function Test-AzureObjectId {
    param([string]$Value)
    return $Value -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
}

# ── Resolve managed identity object ID ────────────────────────────────────────
# Attempt to resolve the managed identity object ID from environment variables if not provided as a parameter
if ([string]::IsNullOrWhiteSpace($ManagedIdentityPrincipalId)) {
    $ManagedIdentityPrincipalId = (azd env get-value MANAGED_IDENTITY_PRINCIPAL_ID 2>$null)
    if ([string]::IsNullOrWhiteSpace($ManagedIdentityPrincipalId)) {
        $ManagedIdentityPrincipalId = $env:MANAGED_IDENTITY_PRINCIPAL_ID
    }
}

# Validate the managed identity object ID format if we have a value at this point
if (-not [string]::IsNullOrWhiteSpace($ManagedIdentityPrincipalId)) {
    if (-not (Test-AzureObjectId -Value $ManagedIdentityPrincipalId)) {
        Write-Warning "The value '$ManagedIdentityPrincipalId' does not look like a valid Azure object ID (expected a GUID)."
        $ManagedIdentityPrincipalId = $null
    }
}

# If we still don't have a valid managed identity object ID, prompt the user to enter it
while ([string]::IsNullOrWhiteSpace($ManagedIdentityPrincipalId) -or -not (Test-AzureObjectId -Value $ManagedIdentityPrincipalId)) {
    $input = Read-Host "Enter the managed identity object ID (GUID)"
    if (-not (Test-AzureObjectId -Value $input)) {
        Write-Warning "'$input' is not a valid Azure object ID. Expected format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    }
    else {
        $ManagedIdentityPrincipalId = $input
    }
}

$miSPID = $ManagedIdentityPrincipalId

Write-Host "Managed identity object ID: $miSPID"

try {

    # ── Microsoft Graph constants ──────────────────────────────────────────────────
    # Microsoft Graph service principal app ID (well-known, constant across all tenants)
    $graphAppId = '00000003-0000-0000-c000-000000000000'


    # ── Connect to Microsoft Graph ─────────────────────────────────────────────────
    Write-Host "Connecting to Microsoft Graph..."
    try {
        Connect-MgGraph -NoWelcome -Scopes 'AppRoleAssignment.ReadWrite.All', "Directory.Read.All", "Application.Read.All"
    } catch {
        Write-Error "Failed to connect to Microsoft Graph. Ensure you have the required permissions and that the Microsoft.Graph module is installed.`nDetail: $_"
        exit 1
    }


    # Get the Microsoft Graph Service Principal (using the well-known appId)
    $GraphSp = Get-MgServicePrincipal -Filter "appId eq '$graphAppId'"
    if ($null -eq $GraphSp) {
        Write-Error "Microsoft Graph service principal (appId: $graphAppId) was not found in this tenant."
        exit 1
    }
    Write-Host "Microsoft Graph service principal found. AppId: $graphAppId"

    # Get the CloudPC.Read.All app role ID from the Microsoft Graph service principal in the current tenant.
    $CloudPcReadAllRole = $GraphSp.AppRoles | Where-Object { $_.Value -eq "CloudPC.Read.All" -and $_.AllowedMemberTypes -contains "Application" }
    if ($null -eq $CloudPcReadAllRole) {
        Write-Error "The 'CloudPC.Read.All' application role was not found on the Microsoft Graph service principal. Verify the role name and that it is available in this environment."
        exit 1
    }


    # # ── Resolve the Microsoft Graph service principal in this tenant ───────────────
    # Write-Host "Looking up Microsoft Graph service principal..."
    # $graphSp = Get-MgServicePrincipal -Filter "appId eq '$graphAppId'"
    # if ($null -eq $graphSp) {
    #     Write-Error "Microsoft Graph service principal not found in the tenant."
    #     exit 1
    # }

    # ── Check for existing assignment to avoid duplicate ──────────────────────────
    $existing = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $miSPID |
    Where-Object { $_.AppRoleId -eq $CloudPcReadAllRole -and $_.ResourceId -eq $GraphSp.Id }

    if ($null -ne $existing) {
        Write-Host "CloudPC.Read.All is already assigned to the managed identity. No action needed."
        exit 0
    }

    # ── Assign CloudPC.Read.All ────────────────────────────────────────────────────
    Write-Host "Assigning CloudPC.Read.All to managed identity..."

    New-MgServicePrincipalAppRoleAssignment `
        -ServicePrincipalId $miSPID `
        -PrincipalId        $miSPID `
        -ResourceId         $GraphSp.Id `
        -AppRoleId          $CloudPcReadAllRole.Id

    Write-Host "CloudPC.Read.All successfully granted to managed identity $miSPID."

}
catch {
    Write-Error "An unexpected error occurred: $_"
    exit 1
}
