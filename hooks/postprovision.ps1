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

# ── Logging helper ─────────────────────────────────────────────────────────────
$script:LogFile = [System.IO.Path]::ChangeExtension($PSCommandPath, '.log')

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "[$timestamp] [$Level] $Message"
    Add-Content -Path $script:LogFile -Value $entry
    switch ($Level) {
        'WARN'  { Write-Warning $Message }
        'ERROR' { Write-Error   $Message }
        default { Write-Host    $Message }
    }
}

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
        Write-Log "The value '$ManagedIdentityPrincipalId' does not look like a valid Azure object ID (expected a GUID)." -Level WARN
        $ManagedIdentityPrincipalId = $null
    }
}

# If we still don't have a valid managed identity object ID, prompt the user to enter it
while ([string]::IsNullOrWhiteSpace($ManagedIdentityPrincipalId) -or -not (Test-AzureObjectId -Value $ManagedIdentityPrincipalId)) {
    $userInput = Read-Host "Enter the managed identity object ID (GUID)"
    if (-not (Test-AzureObjectId -Value $userInput)) {
        Write-Log "'$userInput' is not a valid Azure object ID. Expected format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -Level WARN
    }
    else {
        $ManagedIdentityPrincipalId = $userInput
    }
}

$miSPID = $ManagedIdentityPrincipalId

Write-Log "*** Script started. Managed identity object ID: $miSPID"

try {

    # ── Microsoft Graph constants ──────────────────────────────────────────────────
    # Microsoft Graph service principal app ID (well-known, constant across all tenants)
    $graphAppId = '00000003-0000-0000-c000-000000000000'


    # ── Connect to Microsoft Graph ─────────────────────────────────────────────────
    Write-Log "Connecting to Microsoft Graph..."
    try {
        Connect-MgGraph -NoWelcome -Scopes 'AppRoleAssignment.ReadWrite.All', "Directory.Read.All", "Application.Read.All"
        Write-Log "Successfully connected to Microsoft Graph."
    } catch {
        Write-Log "Failed to connect to Microsoft Graph. Ensure you have the required permissions and that the Microsoft.Graph module is installed. Detail: $_" -Level ERROR
        exit 1
    }

    # ── Pre-flight: verify caller has the required permissions ────────────────────
    Write-Log "Verifying caller permissions..."

    $callerContext = Get-MgContext
    Write-Log "Signed in as: $($callerContext.Account) (AuthType: $($callerContext.AuthType))"

    # Hard check: the token must include AppRoleAssignment.ReadWrite.All
    $requiredScope = 'AppRoleAssignment.ReadWrite.All'
    Write-Log "Checking for required scope '$requiredScope' in the token..."
    if ($callerContext.Scopes -notcontains $requiredScope) {
        Write-Log "Required scope '$requiredScope' missing. Ensure admin consent has been granted for this application. Granted scopes: $($callerContext.Scopes -join ', ')" -Level ERROR
        exit 1
    }
    Write-Log "Required scope '$requiredScope' confirmed in token."

    # Advisory check: verify the caller holds a directory role that permits app role assignments.
    # Role template IDs are well-known and constant across all tenants.
    $permittedRoleTemplateIds = @(
        '62e90394-69f5-4237-9190-012177145e10', # Global Administrator
        'e8611ab8-c189-46e8-94e1-60213ab1f814', # Privileged Role Administrator
        '9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3'  # Application Administrator
    )
    try {
        # Depending on the authentication type, the caller can be a user (delegated auth) or a service principal (application auth). We need to query the appropriate Microsoft Graph endpoint to get their directory roles.
        $callerRoleTemplateIds = if ($callerContext.AuthType -eq 'Delegated') {
            # For delegated auth, the caller is a user. Get their directory roles via /me/memberOf.
            Write-Log "For delegated auth, the caller is a user. Get their directory roles via /me/memberOf."
            $meId = (Get-MgMe -Property Id).Id
            Get-MgUserTransitiveMemberOf -UserId $meId -All |
                Where-Object { $_.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.directoryRole' } |
                ForEach-Object { $_.AdditionalProperties['roleTemplateId'] }
        } else {
            # For application auth, the caller is a service principal. Get their directory roles via /servicePrincipals/{id}/memberOf.
            Write-Log "For application auth, the caller is a service principal. Get their directory roles via /servicePrincipals/{id}/memberOf."
            $callerSp = Get-MgServicePrincipal -Filter "appId eq '$($callerContext.ClientId)'"
            Get-MgServicePrincipalTransitiveMemberOf -ServicePrincipalId $callerSp.Id -All |
                Where-Object { $_.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.directoryRole' } |
                ForEach-Object { $_.AdditionalProperties['roleTemplateId'] }
        }

        # Check if any of the caller's directory role template IDs match the permitted list
        $matchedRoleTemplateId = $callerRoleTemplateIds | Where-Object { $permittedRoleTemplateIds -contains $_ } | Select-Object -First 1
        if ($matchedRoleTemplateId) {
            Write-Log "Caller holds a directory role authorized to assign app roles (templateId: $matchedRoleTemplateId)."
        } else {
            Write-Log "Caller does not appear to hold Global Administrator, Privileged Role Administrator, or Application Administrator. The assignment may fail with 403." -Level WARN
        }
    } catch {
        Write-Log "Could not enumerate caller's directory roles. Proceeding — the assignment will fail if permissions are insufficient. Detail: $_" -Level WARN
    }


    # Get the Microsoft Graph Service Principal (using the well-known appId)
    $GraphSp = Get-MgServicePrincipal -Filter "appId eq '$graphAppId'"
    if ($null -eq $GraphSp) {
        Write-Log "Microsoft Graph service principal (appId: $graphAppId) was not found in this tenant." -Level ERROR
        exit 1
    }
    Write-Log "Microsoft Graph service principal found. AppId: $graphAppId"

    # Get the CloudPC.Read.All app role ID from the Microsoft Graph service principal in the current tenant.
    $CloudPcReadAllRole = $GraphSp.AppRoles | Where-Object { $_.Value -eq "CloudPC.Read.All" -and $_.AllowedMemberTypes -contains "Application" }
    if ($null -eq $CloudPcReadAllRole) {
        Write-Log "The 'CloudPC.Read.All' application role was not found on the Microsoft Graph service principal. Verify the role name and that it is available in this environment." -Level ERROR
        exit 1
    }
    Write-Log "CloudPC.Read.All role found. RoleId: $($CloudPcReadAllRole.Id)"


    # # ── Resolve the Microsoft Graph service principal in this tenant ───────────────
    # Write-Host "Looking up Microsoft Graph service principal..."
    # $graphSp = Get-MgServicePrincipal -Filter "appId eq '$graphAppId'"
    # if ($null -eq $graphSp) {
    #     Write-Error "Microsoft Graph service principal not found in the tenant."
    #     exit 1
    # }

    # ── Check for existing assignment to avoid duplicate ──────────────────────────
    $existing = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $miSPID |
    Where-Object { $_.AppRoleId -eq $CloudPcReadAllRole.Id -and $_.ResourceId -eq $GraphSp.Id }

    if ($null -ne $existing) {
        Write-Log "CloudPC.Read.All is already assigned to the managed identity. No action needed."
        exit 0
    }
    Write-Log "No existing CloudPC.Read.All assignment found. Proceeding with assignment."

    # ── Assign CloudPC.Read.All ────────────────────────────────────────────────────
    Write-Log "Assigning CloudPC.Read.All to managed identity..."

    $assignment = New-MgServicePrincipalAppRoleAssignment `
        -ServicePrincipalId $miSPID `
        -PrincipalId        $miSPID `
        -ResourceId         $GraphSp.Id `
        -AppRoleId          $CloudPcReadAllRole.Id

    Write-Log "CloudPC.Read.All successfully granted to managed identity $miSPID."
    Write-Log "Assignment Id:          $($assignment.Id)"
    Write-Log "Assignment AppRoleId:   $($assignment.AppRoleId)"
    Write-Log "Assignment PrincipalId: $($assignment.PrincipalId)"
    Write-Log "Assignment ResourceId:  $($assignment.ResourceId)"
    Write-Log "Assignment CreatedDateTime: $($assignment.CreatedDateTime)"

}
catch {
    Write-Log "An unexpected error occurred: $_" -Level ERROR
    exit 1
}
