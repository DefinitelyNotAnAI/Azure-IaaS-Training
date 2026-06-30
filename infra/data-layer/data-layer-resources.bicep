// data-layer-resources.bicep — Resource-group-scoped data layer resources.
// Called from infra/app.bicep scoped to workshop-data-rg.
// Creates the shared Event Hub namespace and the Ingestion API Functions app.
// Fabric items (Eventhouse, Lakehouse, Eventstream) are provisioned separately
// by infra/data-layer/setup-fabric.ps1 (azd postprovision hook).

param location string
param uniqueSuffix string

// ── Resource names ─────────────────────────────────────────────────────────────
var uamiName          = 'workshop-ingest-mi'
var storageAccountName = 'wkingest${uniqueSuffix}'
var ehNamespaceName   = 'workshop-eh-${uniqueSuffix}'
var functionAppName   = 'workshop-ingest-${uniqueSuffix}'
var hostingPlanName   = 'workshop-ingest-plan-${uniqueSuffix}'
var appInsightsName   = 'workshop-ingest-insights'
var logWorkspaceName  = 'workshop-ingest-logs'

// ── User-assigned managed identity ────────────────────────────────────────────
resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: uamiName
  location: location
  tags: { purpose: 'data-layer' }
}

// ── Log Analytics + App Insights ──────────────────────────────────────────────
resource logWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logWorkspaceName
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logWorkspace.id
  }
}

// ── Storage account (Flex Consumption host + IngestActivity table) ─────────────
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
  }
  tags: { purpose: 'data-layer' }
}

resource blobSvc 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource deploymentsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobSvc
  name: 'deployments'
  properties: { publicAccess: 'None' }
}

resource tableSvc 'Microsoft.Storage/storageAccounts/tableServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource ingestActivityTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-05-01' = {
  parent: tableSvc
  name: 'IngestActivity'
}

// ── RBAC: UAMI → Storage Blob Data Contributor ────────────────────────────────
resource blobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, uami.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: uami.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ── RBAC: UAMI → Storage Table Data Contributor ───────────────────────────────
resource tableRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, uami.id, '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3')
    principalId: uami.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ── Event Hub namespace ────────────────────────────────────────────────────────
resource ehNamespace 'Microsoft.EventHub/namespaces@2024-01-01' = {
  name: ehNamespaceName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Standard'
    capacity: 2
  }
  properties: {
    isAutoInflateEnabled: true
    maximumThroughputUnits: 16
  }
  tags: { purpose: 'data-layer' }
}

// Event Hub: telemetry — high-frequency per-operation metrics from VMs
resource ehTelemetry 'Microsoft.EventHub/namespaces/eventhubs@2024-01-01' = {
  parent: ehNamespace
  name: 'telemetry'
  properties: {
    partitionCount: 4
    messageRetentionInDays: 1
  }
}

// Event Hub: support — simulated support tickets from VMs
resource ehSupport 'Microsoft.EventHub/namespaces/eventhubs@2024-01-01' = {
  parent: ehNamespace
  name: 'support'
  properties: {
    partitionCount: 2
    messageRetentionInDays: 1
  }
}

// Consumer groups for Fabric Eventstream ingestion
resource ehTelemetryEventstream 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2024-01-01' = {
  parent: ehTelemetry
  name: 'eventstream'
}

resource ehSupportEventstream 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2024-01-01' = {
  parent: ehSupport
  name: 'eventstream'
}

// ── RBAC: UAMI → Azure Event Hubs Data Sender (namespace scope) ───────────────
resource ehSenderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(ehNamespace.id, uami.id, '2b629674-e913-4545-959b-5a4f5cf93484')
  scope: ehNamespace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '2b629674-e913-4545-959b-5a4f5cf93484')
    principalId: uami.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ── Flex Consumption hosting plan ─────────────────────────────────────────────
resource hostingPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: hostingPlanName
  location: location
  sku: {
    tier: 'FlexConsumption'
    name: 'FC1'
  }
  kind: 'functionapp'
  properties: { reserved: true }
}

// ── Ingestion API Functions app ────────────────────────────────────────────────
// Separate from the participant-tracking API to isolate scale + blast radius.
// 30 VMs emitting at high frequency must not impact the participant tracking API.
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${uami.id}': {} }
  }
  properties: {
    serverFarmId: hostingPlan.id
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storageAccount.properties.primaryEndpoints.blob}deployments'
          authentication: {
            type: 'UserAssignedIdentity'
            userAssignedIdentityResourceId: uami.id
          }
        }
      }
      scaleAndConcurrency: {
        maximumInstanceCount: 40
        instanceMemoryMB: 2048
      }
      runtime: {
        name: 'node'
        version: '20'
      }
    }
    siteConfig: {
      appSettings: [
        { name: 'AZURE_CLIENT_ID',                       value: uami.properties.clientId }
        { name: 'STORAGE_ACCOUNT_NAME',                  value: storageAccount.name }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsights.properties.ConnectionString }
        { name: 'EVENT_HUB_NAMESPACE',                   value: '${ehNamespace.name}.servicebus.windows.net' }
        { name: 'EVENT_HUB_TELEMETRY_NAME',              value: 'telemetry' }
        { name: 'EVENT_HUB_SUPPORT_NAME',                value: 'support' }
        // INGEST_KEYS_JSON and SESSION_CODE populated by seed-cohort.ps1 after provisioning
        { name: 'INGEST_KEYS_JSON',                      value: '{}' }
        { name: 'SESSION_CODE',                          value: '' }
      ]
    }
  }
  tags: { 'azd-service-name': 'ingest-api', purpose: 'data-layer' }
  dependsOn: [ blobRole, tableRole, ehSenderRole, deploymentsContainer ]
}

// ── Outputs (consumed by app.bicep and azd postprovision hook) ─────────────────
output ingestFunctionAppName string = functionApp.name
output ingestFunctionAppUrl string = 'https://${functionApp.properties.defaultHostName}'
output eventHubNamespaceHostname string = '${ehNamespace.name}.servicebus.windows.net'
output storageAccountName string = storageAccount.name
output uamiClientId string = uami.properties.clientId
