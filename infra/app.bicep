targetScope = 'subscription'

@description('Azure region. Must support Flex Consumption and Standard Static Web Apps.')
param location string = 'eastus2'

@description('Unique 3-8 char suffix for globally-scoped resource names')
@minLength(3)
@maxLength(8)
param uniqueSuffix string = substring(uniqueString(subscription().id), 0, 6)

@description('Workshop tenant domain for portal deep-links')
param workshopTenantDomain string = 'MngEnvMCAP475636.onmicrosoft.com'

var appRgName = 'workshop-app-rg'

resource appRg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: appRgName
  location: location
  tags: { purpose: 'app-infra' }
}

module appResources 'app-resources.bicep' = {
  name: 'app-resources'
  scope: appRg
  params: {
    location: location
    uniqueSuffix: uniqueSuffix
    workshopTenantDomain: workshopTenantDomain
    subscriptionId: subscription().subscriptionId
  }
}

output functionAppName string = appResources.outputs.functionAppName
output swaDefaultHostname string = appResources.outputs.swaDefaultHostname
output storageAccountName string = appResources.outputs.storageAccountName
output uamiPrincipalId string = appResources.outputs.uamiPrincipalId
output uamiClientId string = appResources.outputs.uamiClientId
