// Cloud Costs Module
// Creates storage account and cost export for Azure Cloud Costs integration

@description('Name of the storage account')
param storageAccountName string

@description('Azure region')
param location string

@description('Container name for cost exports')
param containerName string

@description('Name of the cost export')
param costExportName string

@description('Resource group name')
param resourceGroupName string

@description('Subscription ID')
param subscriptionId string

@description('Tags for resources')
param tags object

// Storage Account for Cost Exports
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Hot'
    isHnsEnabled: true // Data Lake Gen2
    allowSharedKeyAccess: true
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
  }
}

// Blob Service
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
}

// Storage Container
resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: containerName
  properties: {
    publicAccess: 'None'
  }
}

// Cost Management Export
resource costExport 'Microsoft.CostManagement/exports@2023-03-01' = {
  name: costExportName
  scope: resourceGroup()
  properties: {
    schedule: {
      recurrence: 'Daily'
      recurrencePeriod: {
        from: utcNow('yyyy-MM-ddT00:00:00Z')
        to: dateTimeAdd(utcNow('yyyy-MM-ddT00:00:00Z'), 'P1Y')
      }
      status: 'Active'
    }
    format: 'Csv'
    deliveryInfo: {
      destination: {
        resourceId: storageAccount.id
        container: containerName
        rootFolderPath: '/subscriptions/${subscriptionId}'
      }
    }
    definition: {
      type: 'ActualCost'
      timeframe: 'MonthToDate'
      dataSet: {
        granularity: 'Daily'
        configuration: {
          columns: []
        }
      }
    }
  }
  dependsOn: [
    container
  ]
}

// Outputs
output storageAccountName string = storageAccount.name
output storageAccountKey string = storageAccount.listKeys().keys[0].value
output containerName string = containerName
output costExportName string = costExport.name
