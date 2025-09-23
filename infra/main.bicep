// === PARAMETERS ===
param projectName string = 'bankproj'
param location string = 'northeurope'
param imageTag string = 'v1' // Dynamic tag for container images
@secure()
param sqlAdminLogin string // NEW - For SQL Server admin
@secure()
param sqlAdminPassword string // NEW - For SQL Server admin

// === VARIABLES ===
var acrName = 'bankproj'
var serviceBusNamespaceName = '${projectName}-servicebus'
var apimName = 'bankproj-apim'
var containerAppEnvName = 'BankingAppEnv'
var logAnalyticsWorkspaceName = '${projectName}-logs'
var sqlServerName = '${projectName}-sqlserver-${uniqueString(resourceGroup().id)}' // NEW
var sqlDatabaseName = 'BankingDB' // NEW
var keyVaultName ='${projectName}kv${uniqueString(resourceGroup().id)}' // NEW

// --- Azure Container Registry ---
resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' = {
  name: acrName
  location: location
  sku: { name: 'Basic' }
  properties: { adminUserEnabled: true }
}

// --- Azure Service Bus ---
resource serviceBus 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: serviceBusNamespaceName
  location: location
  sku: { name: 'Basic', tier: 'Basic' }
}

// --- Service Bus Queue ---
resource transactionsQueue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  name: 'transactions'
  parent: serviceBus
}

// --- API Management ---
resource apim 'Microsoft.ApiManagement/service@2022-08-01' = {
  name: apimName
  location: location
  sku: { name: 'Consumption', capacity: 0 }
  properties: { publisherEmail: 'sriniwork5693@gmail.com', publisherName: 'Banking Project' }
}

// --- Log Analytics Workspace ---
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

// --- Container Apps Environment ---
resource containerAppEnv 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: containerAppEnvName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
  }
}

// --- ACR Credentials (used by Container Apps) ---
var acrCredentials = acr.listCredentials()
var acrSecret = {
  name: 'acr-password'
  value: acrCredentials.passwords[0].value
}

// --- Container App: account-service ---
resource accountServiceApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: 'account-service'
  location: location
  identity: { type: 'SystemAssigned' }
  properties: {
    managedEnvironmentId: containerAppEnv.id
    configuration: {
      ingress: { external: true, targetPort: 8000 }
      registries: [{ server: acr.properties.loginServer, username: acrCredentials.username, passwordSecretRef: acrSecret.name }]
      secrets: [acrSecret]
    }
    template: {
      containers: [
        {
          name: 'account-service'
          image: '${acr.properties.loginServer}/account-service:${imageTag}'
          resources: { cpu: json('0.25'), memory: '0.5Gi' }
        }
      ]
      scale: { minReplicas: 1 }
    }
  }
}

// --- Container App: transaction-service ---
resource transactionServiceApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: 'transaction-service'
  location: location
  identity: { type: 'SystemAssigned' }
  properties: {
    managedEnvironmentId: containerAppEnv.id
    configuration: {
      ingress: { external: false, targetPort: 8000, transport: 'auto' }
      registries: [{ server: acr.properties.loginServer, username: acrCredentials.username, passwordSecretRef: acrSecret.name }]
      secrets: [acrSecret]
    }
    template: {
      containers: [
        {
          name: 'transaction-service'
          image: '${acr.properties.loginServer}/transaction-service:${imageTag}'
          env: [{ name: 'SERVICE_BUS_HOSTNAME', value: serviceBus.name }]
          resources: { cpu: json('0.25'), memory: '0.5Gi' }
        }
      ]
      scale: { minReplicas: 1 }
    }
  }
}

// --- Container App: transaction-worker ---
resource transactionWorkerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: 'transaction-worker'
  location: location
  identity: { type: 'SystemAssigned' }
  properties: {
    managedEnvironmentId: containerAppEnv.id
    configuration: {
      registries: [{ server: acr.properties.loginServer, username: acrCredentials.username, passwordSecretRef: acrSecret.name }]
      secrets: [acrSecret]
    }
    template: {
      containers: [
        {
          name: 'transaction-worker'
          image: '${acr.properties.loginServer}/transaction-worker:${imageTag}'
          env: [{ name: 'SERVICE_BUS_HOSTNAME', value: serviceBus.name }]
          resources: { cpu: json('0.25'), memory: '0.5Gi' }
        }
      ]
      scale: { minReplicas: 1 }
    }
  }
}
// --- Role Assignment for TransactionService (Sender) ---
resource transactionServiceSenderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBus.id, transactionServiceApp.id, '69a216fc-b8fb-44d8-bc22-1f3c2cd27a39')
  scope: serviceBus
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '69a216fc-b8fb-44d8-824e-898b4def0749')
    principalId: transactionServiceApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// --- Role Assignment for TransactionWorker (Receiver) ---
resource transactionWorkerReceiverRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBus.id, transactionWorkerApp.id, '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0')
  scope: serviceBus
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0')
    principalId: transactionWorkerApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}
// --- Azure SQL Server (NEW) ---
resource sqlServer 'Microsoft.Sql/servers@2022-08-01-preview' = {
  name: sqlServerName
  location: location
  properties: {
    administratorLogin: sqlAdminLogin
    administratorLoginPassword: sqlAdminPassword
    publicNetworkAccess: 'Disabled' // Disables public access for security
  }
}

// --- Azure SQL Database (NEW) ---
resource sqlDatabase 'Microsoft.Sql/servers/databases@2022-08-01-preview' = {
  name: sqlDatabaseName
  parent: sqlServer
  location: location
  sku: {
    name: 'S0'
    tier: 'Standard'
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    sampleName: 'AdventureWorksLT' // Starts with a sample database
  }
}

// --- Azure Key Vault (NEW) ---
resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    accessPolicies: [
      {
        // Policy to allow the account-service to GET secrets
        tenantId: accountServiceApp.identity.tenantId
        objectId: accountServiceApp.identity.principalId
        permissions: {
          secrets: [
            'get'
            'list'
          ]
        }
      }
    ]
  }
}
