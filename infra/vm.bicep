// vm.bicep — Resource-group-scoped template for a participant's workload VM.
//
// Primary use case: recovery/reference template when a participant could not
// complete the Module 3 portal lab. The facilitator runs this to deploy the
// VM and install the legacy support app in one step.
//
// The template assumes the spoke VNet (vnet-{slotId}) and its 'workload' subnet
// already exist — i.e. the participant completed Module 1.
//
// Deploy with:
//   az deployment group create \
//     --resource-group user01-rg \
//     --template-file infra/vm.bicep \
//     --parameters slotId=user01 \
//                  adminPassword='<password>' \
//                  appBinaryUrl='<https://...>' \
//                  installScriptUrl='<https://...>' \
//                  ingestionEndpoint='<https://...>' \
//                  ingestionKey='<key>'

@description('Participant slot identifier, e.g. user01')
param slotId string

@description('Azure region — must match the resource group region')
param location string = resourceGroup().location

@description('VM local administrator username')
param adminUsername string = 'workshopadmin'

@description('VM local administrator password')
@secure()
param adminPassword string

@description('HTTPS URL to the legacy-system single-file .NET executable (app/legacy-system/publish/legacy-system.exe)')
param appBinaryUrl string

@description('HTTPS URL to the VM install script (app/legacy-system/install/install.ps1 stored in blob or raw GitHub)')
param installScriptUrl string

@description('Ingestion API base URL, e.g. https://workshop-ingest-XXXX.azurewebsites.net')
param ingestionEndpoint string

@description('Per-slot ingestion key (x-team-key header). Stored in CSE protected settings — never logged.')
@secure()
param ingestionKey string

// ── Derived names ──────────────────────────────────────────────────────────────
var vmName        = 'vm-${slotId}'
var nicName       = 'nic-${slotId}'
var nsgName       = 'nsg-vm-${slotId}'
var vnetName      = 'vnet-${slotId}'
var subnetName    = 'workload'

// ── NSG — allow outbound HTTPS only; deny all inbound ────────────────────────
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowOutboundHTTPS'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'Internet'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// ── NIC — workload subnet, no public IP ───────────────────────────────────────
resource nic 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: nicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, subnetName)
          }
        }
      }
    ]
    networkSecurityGroup: {
      id: nsg.id
    }
  }
}

// ── Windows Server 2022 VM ────────────────────────────────────────────────────
resource vm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_D2ads_v5'
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-datacenter-azure-edition'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
        deleteOption: 'Delete'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
          properties: {
            deleteOption: 'Delete'
          }
        }
      ]
    }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

// ── Custom Script Extension — installs and starts the legacy-system app ───────
// fileUris downloads the install script and app binary.
// commandToExecute is in protectedSettings so the ingestion key is never logged.
resource vmExtension 'Microsoft.Compute/virtualMachines/extensions@2024-03-01' = {
  parent: vm
  name: 'InstallLegacyApp'
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    settings: {
      // Download URLs are not sensitive — kept in plain settings for diagnostics visibility
      fileUris: [installScriptUrl, appBinaryUrl]
    }
    protectedSettings: {
      // commandToExecute is encrypted at rest — safe for secrets
      commandToExecute: 'powershell -ExecutionPolicy Unrestricted -File install.ps1 -SlotId ${slotId} -IngestionEndpoint ${ingestionEndpoint} -IngestionKey ${ingestionKey}'
    }
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────
output vmName string = vm.name
output privateIpAddress string = nic.properties.ipConfigurations[0].properties.privateIPAddress
