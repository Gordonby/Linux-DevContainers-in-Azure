@minLength(3)
@maxLength(20)
@description('Used to name all resources')
param resourceName string
param location string = resourceGroup().location
param nsgId string

resource vnet 'Microsoft.Network/virtualNetworks@2022-11-01' = {
  name: 'vnet-${resourceName}'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.2.0.0/25'
      ]
    }
    subnets: [
      {
        name: 'backend'
        properties: {
          addressPrefix: '10.2.0.32/27'
          networkSecurityGroup: {
            id: nsgId
          }
        }
      }
    ]
  }
}

output backendSubnetId string = vnet.properties.subnets[0].id
