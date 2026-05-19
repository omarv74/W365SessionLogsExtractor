targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
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

param logAnalyticsName string = ''
param platformResourceGroupName string = 'rg-${environmentName}'

var abbrs = loadJsonContent('../abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, platformResourceGroupName, location))
var tags = { 'azd-env-name': environmentName, SecurityControl: 'Ignore' }

resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: platformResourceGroupName
  location: location
  tags: tags
}

module logAnalytics 'br/public:avm/res/operational-insights/workspace:0.11.1' = {
  name: '${uniqueString(deployment().name, location)}-loganalytics'
  scope: rg
  params: {
    name: !empty(logAnalyticsName) ? logAnalyticsName : '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    location: location
    tags: tags
    dataRetention: 30
  }
}

output lawName string = logAnalytics.outputs.name
output lawResourceGroupName string = rg.name
