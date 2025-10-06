// === PARAMETERS ===
param projectName string = 'bankproj'
param location string = 'northeurope'
param imageTag string = 'latest' // Can be overridden by CI/CD
@secure()
param sqlAdminLogin string // Secure input for SQL admin username
@secure()
param sqlAdminPassword string // Secure input for SQL admin password

// === VARIABLES ===
var acrName = 'bankproj'
var serviceBusNamespaceName = '${projectName}-servicebus'
var apimName = 'bankproj-apim'
var containerAppEnvName = 'BankingAppEnv'
var logAnalyticsWorkspaceName = '${projectName}-logs'
var sqlServerName = '${projectName}-sqlserver-${uniqueString(resourceGroup().id)}'
var sqlDatabaseName = 'BankingDB'
var keyVaultName = '${projectName}kv${uniqueString(resourceGroup().id)}' // Shortened for compliance
var privateDnsZoneName = 'privatelink.database.windows.net' // Standard DNS zone for SQL
var sqlPrivateEndpointName = '${projectName}-sql-pe' 
var virtualNetworkName='${projectName}-vnet'
var containerAppsSubnet = 'containerapps-subnet'
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

// --- ACR Credentials ---
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

// --- Azure SQL Server ---
resource sqlServer 'Microsoft.Sql/servers@2022-08-01-preview' = {
  name: sqlServerName
  location: location
  properties: {
    administratorLogin: sqlAdminLogin
    administratorLoginPassword: sqlAdminPassword
    publicNetworkAccess: 'Disabled' // Secure by default
  }
}

// --- Azure SQL Database ---
resource sqlDatabase 'Microsoft.Sql/servers/databases@2022-08-01-preview' = {
  name: sqlDatabaseName
  parent: sqlServer
  location: location
  sku: {
    name: 'S0'
    tier: 'Standard'
  }
  properties: {
    // We'll start with a sample database which includes some tables and data.
    sampleName: 'AdventureWorksLT'
  }
}

// --- Azure Key Vault ---
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
        // Automatically give the account-service identity permission to GET secrets.
        tenantId: accountServiceApp.identity.tenantId
        objectId: accountServiceApp.identity.principalId
        permissions: {
          secrets: [
            'get', 'list'
          ]
        }
      }
    ]
  }
}

// --- Role Assignments for Service Bus ---
resource transactionServiceSenderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBus.id, transactionServiceApp.id, '69a216fc-b8fb-44d8-bc22-1f3c2cd27a39')
  scope: serviceBus
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '69a216fc-b8fb-44d8-bc22-1f3c2cd27a39')
    principalId: transactionServiceApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource transactionWorkerReceiverRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBus.id, transactionWorkerApp.id, '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0')
  scope: serviceBus
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0')
    principalId: transactionWorkerApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}
// --- Secure Private Networking for SQL (NEW) ---

// 1. Create a Private DNS Zone for Azure SQL
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateDnsZoneName
  location: 'global'
}


// 2. Create a Virtual Network for private networking
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: virtualNetworkName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: containerAppsSubnet
        properties: {
          addressPrefix: '10.0.0.0/23'
          delegations: [
            {
              name: 'Microsoft.App.environments'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
    ]
  }
}

// 2. Link the DNS Zone to our new, explicitly created VNet
resource vnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: '${privateDnsZoneName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
}

// 3. Create the Private Endpoint for the SQL Server in our new Subnet
resource sqlPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-05-01' = {
  name: sqlPrivateEndpointName
  location: location
  properties: {
    subnet: {
      id: virtualNetwork.properties.subnets[0].id
    }
    privateLinkServiceConnections: [
      {
        name: '${sqlPrivateEndpointName}-conn'
        properties: {
          privateLinkServiceId: sqlServer.id
          groupIds: [
            'sqlServer'
          ]
        }
      }
    ]
  }
}

// 4. Create the DNS record for the Private Endpoint
resource sqlPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-05-01' = {
  parent: sqlPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'sql-dns-config'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}
