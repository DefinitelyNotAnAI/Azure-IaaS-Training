param location string
param uniqueSuffix string
param workshopTenantDomain string
param subscriptionId string

var uamiName            = 'workshop-app-mi'
var storageAccountName  = 'wkstore${uniqueSuffix}'
var functionAppName     = 'workshop-api-${uniqueSuffix}'
var hostingPlanName     = 'workshop-plan-${uniqueSuffix}'
var appInsightsName     = 'workshop-insights'
var logWorkspaceName    = 'workshop-logs'
var swaName             = 'workshop-hub'

// ── User-assigned managed identity (stable across azd down/up) ───────────────
resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: uamiName
  location: location
  tags: { purpose: 'app-infra' }
}

// ── Log Analytics + App Insights ─────────────────────────────────────────────
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

// ── Storage account ───────────────────────────────────────────────────────────
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
  tags: { purpose: 'app-infra' }
}

// Pre-create deployments blob container for Flex Consumption
resource blobSvc 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource deploymentsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobSvc
  name: 'deployments'
  properties: { publicAccess: 'None' }
}

// Pre-create workshop tables
resource tableSvc 'Microsoft.Storage/storageAccounts/tableServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource participantsTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-05-01' = {
  parent: tableSvc
  name: 'Participants'
}

resource assignmentsTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-05-01' = {
  parent: tableSvc
  name: 'Assignments'
}

// RBAC: UAMI → Storage Table Data Contributor
resource tableRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, uami.id, '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3')
    principalId: uami.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// RBAC: UAMI → Storage Blob Data Contributor (for deployments container)
resource blobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, uami.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
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

// ── Function App ──────────────────────────────────────────────────────────────
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
        { name: 'AZURE_CLIENT_ID',                        value: uami.properties.clientId }
        { name: 'STORAGE_ACCOUNT_NAME',                   value: storageAccount.name }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING',  value: appInsights.properties.ConnectionString }
        { name: 'SESSION_CODE',                           value: 'CHANGE-ME-PER-DELIVERY' }
        { name: 'ADMIN_ACCESS_CODE',                      value: 'CHANGE-ME-BEFORE-WORKSHOP' }
        { name: 'SESSION_ID',                             value: 'CHANGE-ME-PER-COHORT' }
        { name: 'SUBSCRIPTION_ID',                        value: subscriptionId }
        { name: 'WORKSHOP_TENANT_DOMAIN',                 value: workshopTenantDomain }
        { name: 'HUB_VNET_RG',                           value: 'hub-rg' }
        { name: 'HUB_VNET_NAME',                         value: 'hub-vnet' }
      ]
    }
  }
  tags: { 'azd-service-name': 'api', purpose: 'app-infra' }
  dependsOn: [ tableRole, blobRole, deploymentsContainer ]
}

// ── Static Web App ────────────────────────────────────────────────────────────
resource staticWebApp 'Microsoft.Web/staticSites@2023-12-01' = {
  name: swaName
  location: location
  sku: { name: 'Standard', tier: 'Standard' }
  properties: {}
  tags: { 'azd-service-name': 'web', purpose: 'app-infra' }
}

resource swaBackend 'Microsoft.Web/staticSites/linkedBackends@2023-12-01' = {
  parent: staticWebApp
  name: 'backend'
  properties: {
    backendResourceId: functionApp.id
    region: location
  }
}

output functionAppName string = functionApp.name
output swaDefaultHostname string = staticWebApp.properties.defaultHostname
output storageAccountName string = storageAccount.name
output uamiPrincipalId string = uami.properties.principalId
output uamiClientId string = uami.properties.clientId
