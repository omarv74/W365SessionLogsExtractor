targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources & Flex Consumption Function App')
@allowed([
  'centralus'
  'southcentralus'
  'northcentralus'
  'westcentralus'
  'eastus'
  'eastus2'
  'canadacentral'
  'eastus2euap'
  'westus'
  'westus2'
  'westus3'
])
@metadata({
  azd: {
    type: 'location'
  }
})
param location string

param vnetEnabled bool
param apiServiceName string = ''
param apiUserAssignedIdentityName string = ''
param appServicePlanName string = ''
param resourceGroupName string = 'rg-${environmentName}'
param storageAccountName string = ''
param vNetName string = ''
@description('Id of the user identity to be used for testing and debugging. This is not required in production. Leave empty if not needed.')
param principalId string = deployer().objectId

// Deploy app layer
module app './app/main.bicep' = {
  name: 'app'
  params: {
    environmentName: environmentName
    location: location
    vnetEnabled: vnetEnabled
    apiServiceName: apiServiceName
    apiUserAssignedIdentityName: apiUserAssignedIdentityName
    appServicePlanName: appServicePlanName
    resourceGroupName: resourceGroupName
    appStorageAccountName: storageAccountName
    vNetName: vNetName
    principalId: principalId
  }
}

// App outputs
output AZURE_LOCATION string = app.outputs.AZURE_LOCATION
output AZURE_TENANT_ID string = app.outputs.AZURE_TENANT_ID
output SERVICE_API_NAME string = app.outputs.SERVICE_API_NAME
output AZURE_FUNCTION_NAME string = app.outputs.AZURE_FUNCTION_NAME
output MANAGED_IDENTITY_CLIENT_ID string = app.outputs.MANAGED_IDENTITY_CLIENT_ID
output MANAGED_IDENTITY_PRINCIPAL_ID string = app.outputs.MANAGED_IDENTITY_PRINCIPAL_ID
