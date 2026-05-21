param storageAccountName string
param storageW365LogsAccountName string
param managedIdentityPrincipalId string // Principal ID for the Managed Identity
param userIdentityPrincipalId string = deployer().objectId // Principal ID for the User Identity
param allowUserIdentityPrincipal bool = false // Flag to enable user identity role assignments
param enableBlob bool = true
param enableQueue bool = false
param enableTable bool = false

// Define Role Definition IDs internally
var storageRoleDefinitionId  = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b' //Storage Blob Data Owner role
var storageBlobDataContributorRoleDefinitionId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe' // Storage Blob Data Contributor role
var queueRoleDefinitionId = '974c5e8b-45b9-4653-ba55-5f855dd0fb88' // Storage Queue Data Contributor role
var tableRoleDefinitionId = '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3' // Storage Table Data Contributor role

resource storageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' existing = {
  name: storageAccountName
}

resource storageW365LogsAccount 'Microsoft.Storage/storageAccounts@2022-09-01' existing = {
  name: storageW365LogsAccountName
}

// Role assignment for Storage Account (Blob) - Managed Identity
resource storageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableBlob) {
  name: guid(storageAccount.id, managedIdentityPrincipalId, storageRoleDefinitionId) // Use managed identity ID
  scope: storageAccount
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', storageRoleDefinitionId)
    principalId: managedIdentityPrincipalId // Use managed identity ID
    principalType: 'ServicePrincipal' // Managed Identity is a Service Principal
  }
}

// Role assignment for Storage Account (Blob) - User Identity
resource storageRoleAssignment_User 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableBlob && allowUserIdentityPrincipal && !empty(userIdentityPrincipalId)) {
  name: guid(storageAccount.id, userIdentityPrincipalId, storageRoleDefinitionId)
  scope: storageAccount
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', storageRoleDefinitionId)
    principalId: userIdentityPrincipalId // Use user identity ID
    principalType: 'User' // User Identity is a User Principal
  }
}

// Role assignment for Storage Account (Queue) - Managed Identity
resource queueRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableQueue) {
  name: guid(storageAccount.id, managedIdentityPrincipalId, queueRoleDefinitionId) // Use managed identity ID
  scope: storageAccount
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', queueRoleDefinitionId)
    principalId: managedIdentityPrincipalId // Use managed identity ID
    principalType: 'ServicePrincipal' // Managed Identity is a Service Principal
  }
}

// Role assignment for Storage Account (Queue) - User Identity
resource queueRoleAssignment_User 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableQueue && allowUserIdentityPrincipal && !empty(userIdentityPrincipalId)) {
  name: guid(storageAccount.id, userIdentityPrincipalId, queueRoleDefinitionId)
  scope: storageAccount
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', queueRoleDefinitionId)
    principalId: userIdentityPrincipalId // Use user identity ID
    principalType: 'User' // User Identity is a User Principal
  }
}

// Role assignment for Storage Account (Table) - Managed Identity
resource tableRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableTable) {
  name: guid(storageAccount.id, managedIdentityPrincipalId, tableRoleDefinitionId) // Use managed identity ID
  scope: storageAccount
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', tableRoleDefinitionId)
    principalId: managedIdentityPrincipalId // Use managed identity ID
    principalType: 'ServicePrincipal' // Managed Identity is a Service Principal
  }
}

// Role assignment for Storage Account (Table) - User Identity
resource tableRoleAssignment_User 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableTable && allowUserIdentityPrincipal && !empty(userIdentityPrincipalId)) {
  name: guid(storageAccount.id, userIdentityPrincipalId, tableRoleDefinitionId)
  scope: storageAccount
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', tableRoleDefinitionId)
    principalId: userIdentityPrincipalId // Use user identity ID
    principalType: 'User' // User Identity is a User Principal
  }
}

// Role assignment for W365 Logs Storage Account (Storage Blob Data Contributor) - Managed Identity
resource storageW365LogsBlobDataContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageW365LogsAccount.id, managedIdentityPrincipalId, storageBlobDataContributorRoleDefinitionId)
  scope: storageW365LogsAccount
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleDefinitionId)
    principalId: managedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Role assignment for Storage Account (Blob) - User Identity
resource storageW365LogsAccountRoleAssignment_User 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableBlob && allowUserIdentityPrincipal && !empty(userIdentityPrincipalId)) {
  name: guid(storageW365LogsAccount.id, userIdentityPrincipalId, storageRoleDefinitionId)
  scope: storageW365LogsAccount
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', storageRoleDefinitionId)
    principalId: userIdentityPrincipalId // Use user identity ID
    principalType: 'User' // User Identity is a User Principal
  }
}

