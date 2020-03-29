###########################################################################
###
### Description: PowerShell script performing the following actions:
###
###     - Creating an Azure policy definition to audit when resource 
###     groups (RG) are deployed with missing tags
###     - Assigning this Azure policy definition for two required tags 
###     defined by the user
###     - Assigning the Azure policy definition "Append a tag and its 
###     value from the resource group" for the two user defined tags
###     - Creating a resource group
###     - Creating a Log Analytic Workspace to connect with the 
###     Azure Activity Logs
###     - Creating an Alert Action Group and an Alert Rule to send emails 
###     when RG are not compliant
###
### Author: Nicolas Wipfli
### Date: Sunday Mar 29, 2020
###
###########################################################################


##
## Variables to update with your values
##
$subscriptionName = "you_subscription_name"   # Provide the name of your subscription (ie: MySubscription)
$tagsArray = @(                # Define your tag's key-values
    @("creator","nwipfli"),
    @("environment","test")
)
$Location = "azure_region"  # Azure region (ie: switzerlandnorth)
$ResourceGroup = "resource_group_name" + $Location  # Resource group for the Log Analytic workspace
$WorkspaceName = "workspace_name" + $Location
$emailReceiverName = "my_name"
$emailAddress = "my_email@test.com"
$actionGroupName = "action_group_name"
$actionGroupShortName = "action_group_shortname"

##
## Constants
##
$tag = New-Object "System.Collections.Generic.Dictionary``2[System.String,System.String]"
$tagCount = $tagsArray.Length
$count = 0
while ($count -ne $tagCount) {
    $tag.Add($tagsArray[$count][0],$tagsArray[$count][1])
    $count++
}
$subscription = Get-AzSubscription -SubscriptionName $subscriptionName

##
## Create and assign the policy definition(s) for missing specific tags
##

# Policy for the resource groups
Write-Host "Creating the policy definition 'Audit resource groups missing tags'..." -foregroundcolor Red
$resourceGroupDefinition = New-AzPolicyDefinition `
-Name "audit-resourceGroup-tags" `
-DisplayName "Audit resource groups missing tags" `
-description "Audit resource groups that doesn't have particular tag" `
-Policy 'https://raw.githubusercontent.com/Azure/azure-policy/master/samples/ResourceGroup/audit-resourceGroup-tags/azurepolicy.rules.json' `
-Parameter 'https://raw.githubusercontent.com/Azure/azure-policy/master/samples/ResourceGroup/audit-resourceGroup-tags/azurepolicy.parameters.json' `
-Mode All `
-Metadata '{"category":"Tags"}'

# Policy for the resources (section currently disabled)

<#Write-Host "Creating the policy definition 'Audit resources missing tags'..." -foregroundcolor Red
$resourceDefinition = New-AzPolicyDefinition `
-Name "audit-resource-tags" `
-DisplayName "Audit resources missing tags" `
-description "Audit resources that doesn't have particular tag" `
-Policy './auditResourceTag.rules.json' `
-Parameter './auditResourceTag.parameters.json' `
-Mode All `
-Metadata '{"category":"Tags"}'#>

# Assign the policy definitions with the tags
$count = 0
while ($count -ne $tagCount) {
    $tagKey = $tagsArray[$count][0]
    Write-Host "Assigning the policy definition(s) for the tag $tagKey..." -foregroundcolor Red

    New-AzPolicyAssignment `
    -Name "Audit Missing $tagKey Tag on resource groups" `
    -DisplayName "Audit resource groups missing $tagKey tag" `
    -PolicyDefinition $resourceGroupDefinition `
    -tagName $tagKey `
    -Scope "/subscriptions/$($Subscription.Id)"

    # Section currently disabled

    <#New-AzPolicyAssignment `
    -Name "Audit Missing $tagKey Tag on resources" `
    -DisplayName "Audit resources missing $tagKey tag" `
    -PolicyDefinition $resourceDefinition `
    -tagName $tagKey `
    -Scope "/subscriptions/$($Subscription.Id)"#>

    $count++
}

##
## Assigning the built-in "Append a tag and its value from the resource group" policy definition for the tags
##

$definition = Get-AzPolicyDefinition | Where-Object { $_.Properties.DisplayName -eq "Append a tag and its value from the resource group" }

$count = 0
while ($count -ne $tagCount) {
    $tagKey = $tagsArray[$count][0]
    Write-Host "Assigning the definition 'Append a tag and its value from the resource group' for the tag $tagKey..." -foregroundcolor Red

    New-AzPolicyAssignment `
    -Name "Append tag $tagKey and its value from the resource group" `
    -DisplayName "Append tag $tagKey and its value from the resource group" `
    -PolicyDefinition $definition `
    -tagName $tagKey `
    -Scope "/subscriptions/$($Subscription.Id)"

    $count++
}

##
## Create the resource group if needed
##

try {

    $RG = Get-AzResourceGroup -Name $ResourceGroup -ErrorAction Stop
    $ExistingLocation = $RG.Location
    Write-Host "Resource group $ResourceGroup in region $ExistingLocation already exists." -foregroundcolor Red

}
catch {

    Write-Host "Creating the resource group '$ResourceGroup'" -foregroundcolor Red
    New-AzResourceGroup -Name $ResourceGroup -Location $Location -Tag $tag

}

##
## Create the Log Analytics workspace
## The connection with the Activity Log is performed at the end of this script
##

try {

    $Workspace = Get-AzOperationalInsightsWorkspace -Name $WorkspaceName -ResourceGroupName $ResourceGroup  -ErrorAction Stop
    $ExistingLocation = $Workspace.Location
    Write-Host "Workspace named $WorkspaceName in region $ExistingLocation already exists." -foregroundcolor Red

} catch {

    Write-Host "Creating new workspace named $WorkspaceName in region $Location..." -foregroundcolor Red
    # Create the new workspace for the given name, region, and resource group
    $Workspace = New-AzOperationalInsightsWorkspace -Location $Location -Name $WorkspaceName -Sku Standard -ResourceGroupName $ResourceGroup -Tag $tag

}

##
## Create the Action Group and Alert Rule
##

# Create a new Action Group Email receiver and Action Group
Write-Host "Creating the Alert Action Group..." -foregroundcolor Red
$emailReceiver = New-AzActionGroupReceiver -Name $emailReceiverName -EmailReceiver -EmailAddress $emailAddress
$actionGroup = Set-AzActionGroup -Name $actionGroupName -ResourceGroup $ResourceGroup -ShortName $actionGroupShortName -Receiver $emailReceiver -Tag $tag

# Launching an Azure deployment template to create the Alert Rule based on a Log search query
new-azdeployment -Name sampeTest -Location $Location -TemplateFile ./azurealertdeploy.json -logAnalyticsWorkspaceResourceId $Workspace.ResourceId -resourceGroupName $ResourceGroup -actionGroupId $actionGroup.Id

# Connect the Activity Log to the workspace
Write-Host "Connecting the Activity Logs to the workspace $WorkspaceName..." -foregroundcolor Red
New-AzOperationalInsightsAzureActivityLogDataSource -ResourceGroupName $ResourceGroup -Name "Activity Log" -WorkspaceName $WorkspaceName -SubscriptionId ($subscription).Id
