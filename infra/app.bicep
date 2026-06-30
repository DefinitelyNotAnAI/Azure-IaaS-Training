targetScope = 'subscription'

@description('Azure region. Must support Flex Consumption and Standard Static Web Apps.')
param location string = 'eastus2'

@description('Unique 3-8 char suffix for globally-scoped resource names')
@minLength(3)
@maxLength(8)
param uniqueSuffix string = substring(uniqueString(subscription().id), 0, 6)

@description('Workshop tenant domain for portal deep-links')
param workshopTenantDomain string = 'contoso.onmicrosoft.com'

@description('Table Storage PartitionKey for this cohort')
param sessionId string = 'CHANGE-ME-PER-COHORT'

@description('Shared join code sent by participants')
param sessionCode string = 'CHANGE-ME-PER-DELIVERY'

@description('Admin dashboard access code')
param adminAccessCode string = 'CHANGE-ME-BEFORE-WORKSHOP'

var appRgName  = 'workshop-app-rg'
var dataRgName = 'workshop-data-rg'

resource appRg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: appRgName
  location: location
  tags: { purpose: 'app-infra' }
}

resource dataRg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: dataRgName
  location: location
  tags: { purpose: 'data-layer' }
}

module appResources 'app-resources.bicep' = {
  name: 'app-resources'
  scope: appRg
  params: {
    location: location
    uniqueSuffix: uniqueSuffix
    workshopTenantDomain: workshopTenantDomain
    subscriptionId: subscription().subscriptionId
    sessionId: sessionId
    sessionCode: sessionCode
    adminAccessCode: adminAccessCode
  }
}

module dataResources 'data-layer/data-layer-resources.bicep' = {
  name: 'data-layer-resources'
  scope: dataRg
  params: {
    location: location
    uniqueSuffix: uniqueSuffix
  }
}

output functionAppName string = appResources.outputs.functionAppName
output swaDefaultHostname string = appResources.outputs.swaDefaultHostname
output storageAccountName string = appResources.outputs.storageAccountName
output uamiPrincipalId string = appResources.outputs.uamiPrincipalId
output uamiClientId string = appResources.outputs.uamiClientId

// Data-layer outputs (consumed by setup-fabric.ps1 postprovision hook)
output ingestFunctionAppName string = dataResources.outputs.ingestFunctionAppName
output ingestFunctionAppUrl string = dataResources.outputs.ingestFunctionAppUrl
output ingestEventHubNamespace string = dataResources.outputs.eventHubNamespaceHostname
