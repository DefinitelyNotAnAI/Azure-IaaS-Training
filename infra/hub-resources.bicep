param location string

resource hubVnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: 'hub-vnet'
  location: location
  tags: { purpose: 'hub-network' }
  properties: {
    addressSpace: {
      addressPrefixes: [ '10.0.0.0/16' ]
    }
    subnets: [
      {
        name: 'GatewaySubnet'
        properties: { addressPrefix: '10.0.0.0/24' }
      }
      {
        name: 'AzureBastionSubnet'
        // Bastion requires /26 minimum
        properties: { addressPrefix: '10.0.1.0/26' }
      }
      {
        name: 'shared-services'
        properties: { addressPrefix: '10.0.2.0/24' }
      }
    ]
  }
}

output hubVnetId string = hubVnet.id
output hubVnetName string = hubVnet.name
