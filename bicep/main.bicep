// OpenCost on AKS - Main Bicep Template
// This template deploys OpenCost on Azure Kubernetes Service with full Azure Cloud Costs integration

targetScope = 'subscription'

// Parameters
@description('Name of the resource group')
param resourceGroupName string = 'rg-opencost-demo'

@description('Azure region for resources')
param location string = 'swedencentral'

@description('Name of the AKS cluster')
param clusterName string = 'aks-opencost-demo'

@description('Number of nodes in the default node pool')
@minValue(1)
@maxValue(100)
param nodeCount int = 2

@description('Size of the VMs in the default node pool')
param nodeVmSize string = 'Standard_D2s_v5'

@description('Kubernetes version for the AKS cluster (null = latest)')
param kubernetesVersion string = ''

@description('Network plugin for AKS')
@allowed([
  'azure'
  'kubenet'
])
param networkPlugin string = 'azure'

@description('Network policy for AKS')
@allowed([
  'azure'
  'calico'
  'cilium'
])
param networkPolicy string = 'azure'

@description('Enable auto-scaling for the default node pool')
param enableAutoScaling bool = false

@description('Minimum number of nodes when auto-scaling is enabled')
param minNodeCount int = 2

@description('Maximum number of nodes when auto-scaling is enabled')
param maxNodeCount int = 5

@description('Enable Azure Cloud Costs integration')
param enableCloudCosts bool = true

@description('Prefix for the storage account name')
param storageAccountNamePrefix string = 'opencostexport'

@description('Name of the cost export')
param costExportName string = 'opencost-daily'

@description('Name of the storage container for cost exports')
param costExportContainerName string = 'cost-exports'

@description('Tags to apply to all resources')
param tags object = {
  Environment: 'Demo'
  ManagedBy: 'Bicep'
  Purpose: 'OpenCost'
}

// Variables
var uniqueSuffix = substring(uniqueString(subscription().subscriptionId, resourceGroupName), 0, 4)
var storageAccountName = '${storageAccountNamePrefix}${uniqueSuffix}'

// Resource Group
resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// AKS Cluster Module
module aks 'modules/aks.bicep' = {
  scope: rg
  name: 'aks-deployment'
  params: {
    clusterName: clusterName
    location: location
    nodeCount: nodeCount
    nodeVmSize: nodeVmSize
    kubernetesVersion: kubernetesVersion
    networkPlugin: networkPlugin
    networkPolicy: networkPolicy
    enableAutoScaling: enableAutoScaling
    minNodeCount: minNodeCount
    maxNodeCount: maxNodeCount
    tags: tags
  }
}

// Custom Role Definition for OpenCost
module openCostRole 'modules/opencost-role.bicep' = {
  scope: subscription()
  name: 'opencost-role-deployment'
  params: {
    roleName: 'OpenCostRole-${uniqueSuffix}'
    subscriptionId: subscription().subscriptionId
  }
}

// Service Principal Module
module servicePrincipal 'modules/service-principal.bicep' = {
  scope: subscription()
  name: 'service-principal-deployment'
  params: {
    displayName: 'OpenCostAccess-${uniqueSuffix}'
    roleDefinitionId: openCostRole.outputs.roleDefinitionId
    subscriptionId: subscription().subscriptionId
  }
  dependsOn: [
    openCostRole
  ]
}

// Storage Account and Cost Export Module (if enabled)
module cloudCosts 'modules/cloud-costs.bicep' = if (enableCloudCosts) {
  scope: rg
  name: 'cloud-costs-deployment'
  params: {
    storageAccountName: storageAccountName
    location: location
    containerName: costExportContainerName
    costExportName: costExportName
    resourceGroupName: resourceGroupName
    subscriptionId: subscription().subscriptionId
    tags: union(tags, {
      SecurityControl: 'ignore'
    })
  }
}

// Outputs
output resourceGroupName string = rg.name
output aksClusterName string = aks.outputs.clusterName
output aksClusterId string = aks.outputs.clusterId
output servicePrincipalAppId string = servicePrincipal.outputs.appId
output servicePrincipalPassword string = servicePrincipal.outputs.password
output tenantId string = subscription().tenantId
output subscriptionId string = subscription().subscriptionId
output storageAccountName string = enableCloudCosts ? cloudCosts.outputs.storageAccountName : ''
output storageAccountKey string = enableCloudCosts ? cloudCosts.outputs.storageAccountKey : ''
output costExportContainerName string = enableCloudCosts ? costExportContainerName : ''
