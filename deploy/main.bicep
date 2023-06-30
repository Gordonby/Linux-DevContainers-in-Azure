@minLength(3)
@maxLength(20)
@description('Used to name all resources')
param resourceName string

param vmName string = 'vm-${resourceName}-${toLower(deployingUserName)}'

param location string = resourceGroup().location

param deployingUserPrincipalId string

@description('Used to name the Virtual Machine, and denote exclusivity. For users that need multiple VMs in the same environment, vary this parameter accordingly')
param deployingUserName string

@allowed([
  'PublicIpOnVm'
  'Bastion' //Awaiting resolution on https://github.com/microsoft/vscode-remote-release/issues/7179
  'PointToSiteVpnWithDns'
  'PointToSiteVpnWithoutDns'
  'LandingZone'
])
param exposureModel string = 'PublicIpOnVm'

@allowed(['dnsResolver', 'aci', 'none'])
param p2sDns string = 'none'

@description('When exposureModel is publicIpOnVm, this is the IP address that will be allowed to SSH to the VM. If not specified, any IP address will be allowed which is not good practice.')
param clientOutboundIpAddress string = ''

module vnet '../modules/vnet.bicep' = {
  name: '${deployment().name}-vnet'
  params: {
    resourceName: resourceName
    location: location
    customdns: []
  }
}

module keyvault '../modules/keyvaultssh/keyvault.bicep' = {
  name: '${deployment().name}-keyvault'
  params: {
    resourceName: resourceName
    location: location
    createRbacForDeployingUser: true
    deployingUserPrincipalId: deployingUserPrincipalId
    logAnalyticsWorkspaceId: '' //No logging right now.
  }
}

module kvSshSecret '../modules/keyvaultssh/ssh.bicep' = {
  name: '${deployment().name}-kvsshsecret'
  params: {
    akvName: keyvault.outputs.keyVaultName
    location: location
    sshKeyName: 'vmSsh'
  }
}

@description('Key Vault reference to the SSH public key secret. Used to pass the public key to the VM module.')
resource kvRef 'Microsoft.KeyVault/vaults@2022-11-01' existing = {
  name: keyvault.outputs.keyVaultName
}

@description('''
Creates the VM - this module is not idempotent, so it will fail if the VM already exists. To update the VM, delete it first.
eg. "Changing property 'linuxConfiguration.ssh.publicKeys' is not allowed."
''')
module vm '../modules/vm.bicep' = {
  name: '${deployment().name}-vm'
  params: {
    resourceName: resourceName
    vmName: vmName
    location: location
    publicIpAddress: exposureModel=='PublicIpOnVm'
    sshkey: kvRef.getSecret(kvSshSecret.outputs.publicKeySecretName)
    subnetId: vnet.outputs.backendSubnetId
    tags: {
      'created-by': deployingUserName
    }
  }
}

module nsg '../modules/nsg.bicep' = if(exposureModel=='PublicIpOnVm') {
  name: '${deployment().name}-nsg'
  params: {
    resourceName: resourceName
    location: location
    workspaceRegion: location
    ruleInAllowSsh: true
    internetSourceIpAddress: clientOutboundIpAddress
  }
}

output keyVaultName string = keyvault.outputs.keyVaultName
output publicIpDnsFqdn string = vm.outputs.publicIpDnsFqdn
output vmName string = vm.outputs.name
