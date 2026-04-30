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

param()

$ErrorActionPreference = 'Stop'

# ── Resolve managed identity object ID ────────────────────────────────────────
$miSPID = (azd env get-value MANAGED_IDENTITY_PRINCIPAL_ID) # $env:MANAGED_IDENTITY_PRINCIPAL_ID
if ([string]::IsNullOrWhiteSpace($miSPID)) {
    Write-Error "MANAGED_IDENTITY_PRINCIPAL_ID is not set. Ensure the Bicep output is defined in main.bicep."
    exit 1
}

Write-Host "Managed identity object ID: $miSPID"

# ── Microsoft Graph constants ──────────────────────────────────────────────────
# Microsoft Graph service principal app ID (well-known, constant across all tenants)
$graphAppId  = '00000003-0000-0000-c000-000000000000'


# ── Connect to Microsoft Graph ─────────────────────────────────────────────────
Write-Host "Connecting to Microsoft Graph..."
Connect-MgGraph -NoWelcome -Scopes 'AppRoleAssignment.ReadWrite.All',"Directory.Read.All","Application.Read.All"


# Get the Microsoft Graph Service Principal (using the well-known appId)
$GraphSp = Get-MgServicePrincipal -Filter "appId eq '$graphAppId'"
# $graphAppId  = $GraphSp.AppId
Write-Host "Microsoft Graph service principal found. AppId: $graphAppId"

# Get the CloudPC.Read.All app role ID from the Microsoft Graph service principal in the current tenant.
$CloudPcReadAllRole   = $GraphSp.AppRoles | Where-Object { $_.Value -eq "CloudPC.Read.All" -and $_.AllowedMemberTypes -contains "Application" }


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
