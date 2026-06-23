targetScope = 'subscription'

@description('Azure region. Verify Flex Consumption availability: az functionapp list-flexconsumption-locations')
param location string = 'eastus2'

@description('Name of the hub resource group')
param hubRgName string = 'hub-rg'

resource hubRg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: hubRgName
  location: location
  tags: {
    purpose: 'hub-network'
  }
}

module hubResources 'hub-resources.bicep' = {
  name: 'hub-resources'
  scope: hubRg
  params: {
    location: location
  }
}

output hubVnetId string = hubResources.outputs.hubVnetId
output hubVnetName string = hubResources.outputs.hubVnetName
output hubRgName string = hubRg.name
