// Service Principal Module
// Note: Bicep cannot create Azure AD applications/service principals directly
// This is a placeholder that documents the required resources
// Use the deployment script (deploy.sh or deploy.ps1) to create the service principal

targetScope = 'subscription'

@description('Display name for the service principal')
param displayName string

@description('Role definition ID to assign')
param roleDefinitionId string

@description('Subscription ID')
param subscriptionId string

// Note: This module is a placeholder
// Service principals must be created using Azure CLI or PowerShell
// See deploy.ps1 or deploy.sh for implementation

// The deployment script will:
// 1. Create an Azure AD application with displayName
// 2. Create a service principal for the application
// 3. Generate a password/secret
// 4. Assign the custom role to the service principal

// Outputs (will be populated by deployment script)
output appId string = ''
output password string = ''
output message string = 'Service principal must be created using deployment script (Azure CLI/PowerShell)'
