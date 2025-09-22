// === PARAMETERS ===
// These are the inputs to our template.
param projectName string = 'bankproj'
param location string = 'northeurope'

// === VARIABLES ===
// These are values we'll reuse throughout the file.
var acrName = '${projectName}acr${uniqueString(resourceGroup().id)}'
var serviceBusNamespaceName = '${projectName}-servicebus'
var apimName = '${projectName}-apim-${uniqueString(resourceGroup().id)}'
var containerAppEnvName = 'BankingAppEnv'
// --- Azure Container Registry ---
resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' = {
  name: acrName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: true
  }
}
// --- Azure Service Bus ---
resource serviceBus 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: serviceBusNamespaceName
  location: location
  sku: {
    name: 'Basic'
  }
}

// --- Service Bus Queue ---
// This resource depends on the Service Bus namespace above
resource transactionsQueue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  name: 'transactions'
  parent: serviceBus // This links it to the namespace
}

// --- API Management ---
resource apim 'Microsoft.ApiManagement/service@2022-08-01' = {
  name: apimName
  location: location
  sku: {
    name: 'Consumption'
    capacity:0
  }
  properties: {
    publisherEmail: 'youremail@example.com' // Update with your email
    publisherName: 'Banking Project'
  }
}
// --- Container Apps Environment ---
resource containerAppEnv 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: containerAppEnvName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
    }
  }
}

// --- Container App: account-service ---
resource accountServiceApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: 'account-service'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: containerAppEnv.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8000
      }
      registries: [
        {
          server: acr.properties.loginServer
          username: acr.name
          passwordSecretRef: 'acr-password'
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'account-service'
          image: '${acr.properties.loginServer}/account-service:v1'
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
        }
      ]
      scale: {
        minReplicas: 1
      }
    }
  }
}

// --- Container App: transaction-service ---
resource transactionServiceApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: 'transaction-service'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: containerAppEnv.id
    configuration: {
      ingress: {
        external: false // Internal only
        targetPort: 8000
        transport: 'auto'
      }
      registries: [
        {
          server: acr.properties.loginServer
          username: acr.name
          passwordSecretRef: 'acr-password'
        }
      ]
      secrets: [
        {
          name: 'acr-password'
          value: acr.listKeys().passwords[0].value
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'transaction-service'
          image: '${acr.properties.loginServer}/transaction-service:v1'
          env: [
            {
              name: 'SERVICE_BUS_HOSTNAME'
              value: serviceBus.properties.metricId
            }
          ]
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
        }
      ]
      scale: {
        minReplicas: 1
      }
    }
  }
}

// --- Container App: transaction-worker ---
resource transactionWorkerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: 'transaction-worker'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: containerAppEnv.id
    configuration: {
      registries: [
        {
          server: acr.properties.loginServer
          username: acr.name
          passwordSecretRef: 'acr-password'
        }
      ]
      secrets: [
        {
          name: 'acr-password'
          value: acr.listKeys().passwords[0].value
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'transaction-worker'
          image: '${acr.properties.loginServer}/transaction-worker:v1'
          env: [
            {
              name: 'SERVICE_BUS_HOSTNAME'
              value: serviceBus.properties.metricId
            }
          ]
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
        }
      ]
      scale: {
        minReplicas: 1
      }
    }
  }
}
