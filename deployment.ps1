##
## Variables to modify
##
$subscriptionName = "Personal Subscription"   # Provide the name of your subscription
$tag1Name = "creator"
$tag1Value = "n.wipfli@abissa.ch"
$tag2Name = "environment"
$tag2Value = "prod"
$Location = "switzerlandnorth"
$ResourceGroup = "rg-taggingcompliance-prod-" + $Location  # Resource group for the Log Analytic workspace
$WorkspaceName = "log-azureactivity-prod-" + $Location #+ (Get-Random -Maximum 99)
$emailReceiverName = "Nicolas Wipfli"
$emailAddress = "n.wipfli@abissa.ch"
$actionGroupName = "Non Compliant Tagging"
$actionGroupShortName = "TagNOK"
##

##
## Constants
##
$tag = New-Object "System.Collections.Generic.Dictionary``2[System.String,System.String]"
$tag.Add($tag1Name,$tag1Value)
$tag.Add($tag2Name,$tag2Value)
$subscription = Get-AzSubscription -SubscriptionName $subscriptionName
##

# Create the policy definition for missing specific tags in resource groups
Write-Output "Creating the policy definition 'Audit resource groups missing tags'"
$definition = New-AzPolicyDefinition `
-Name "audit-resourceGroup-tags" `
-DisplayName "Audit resource groups missing tags" `
-description "Audit resource groups that doesn't have particular tag" `
-Policy 'https://raw.githubusercontent.com/Azure/azure-policy/master/samples/ResourceGroup/audit-resourceGroup-tags/azurepolicy.rules.json' `
-Parameter 'https://raw.githubusercontent.com/Azure/azure-policy/master/samples/ResourceGroup/audit-resourceGroup-tags/azurepolicy.parameters.json' `
-Mode All `
-Metadata '{"category":"Tags"}'

# Assign the policy definition with the tags
Write-Output "Creating the policy assignment for the tag '$tag1Name'"
New-AzPolicyAssignment `
-Name "Audit Missing $tag1Name Tag" `
-DisplayName "Audit resource groups missing $tag1Name tag" `
-PolicyDefinition $definition `
-tagName $tag1Name `
-Scope "/subscriptions/$($Subscription.Id)"

Write-Output "Creating the policy assignment for the tag '$tag2Name'"
New-AzPolicyAssignment `
-Name "Audit Missing $tag2Name Tag" `
-DisplayName "Audit resource groups missing $tag2Name tag" `
-PolicyDefinition $definition `
-tagName $tag2Name `
-Scope "/subscriptions/$($Subscription.Id)"

# Assign the "Append a tag and its value from the resource group" policy for specific tags
Write-Output "Assigning the definition 'Append a tag and its value from the resource group' for tags '$tag1Name', '$tag2Name'"
$definition = Get-AzPolicyDefinition | Where-Object { $_.Properties.DisplayName -eq "Append a tag and its value from the resource group" }

New-AzPolicyAssignment `
-Name "Append $tag1Name and its value from the resource group" `
-DisplayName "Append $tag1Name and its value from the resource group" `
-PolicyDefinition $definition `
-tagName $tag1Name `
-Scope "/subscriptions/$($Subscription.Id)"

New-AzPolicyAssignment `
-Name "Append $tag2Name and its value from the resource group" `
-DisplayName "Append $tag2Name and its value from the resource group" `
-PolicyDefinition $definition `
-tagName $tag2Name `
-Scope "/subscriptions/$($Subscription.Id)"

# Create the resource group if needed
try {

    $RG = Get-AzResourceGroup -Name $ResourceGroup -ErrorAction Stop
    $ExistingLocation = $RG.Location
    Write-Output "Resource group $ResourceGroup in region $ExistingLocation already exists."
    Write-Output "No further action required, script quitting."

}
catch {

    Write-Output "Creating the resource group '$ResourceGroup'"
    New-AzResourceGroup -Name $ResourceGroup -Location $Location -Tag $tag

}

# Create a new Log Analytics workspace if needed
try {

    $Workspace = Get-AzOperationalInsightsWorkspace -Name $WorkspaceName -ResourceGroupName $ResourceGroup  -ErrorAction Stop
    $ExistingLocation = $Workspace.Location
    Write-Output "Workspace named $WorkspaceName in region $ExistingLocation already exists."
    Write-Output "No further action required, script quitting."

} catch {

    Write-Output "Creating new workspace named $WorkspaceName in region $Location..."
    # Create the new workspace for the given name, region, and resource group
    $Workspace = New-AzOperationalInsightsWorkspace -Location $Location -Name $WorkspaceName -Sku Standard -ResourceGroupName $ResourceGroup

}

# Connect the Activity Log to the workspace
Write-Output "Connecting the Activity Logs to the workspace"
New-AzOperationalInsightsAzureActivityLogDataSource -ResourceGroupName $ResourceGroup -Name "Activity Log" -WorkspaceName $WorkspaceName -SubscriptionId ($subscription).Id

##
## Creating the Azure Monitor action group
##

# Create a new Action Group Email receiver
$emailReceiver = New-AzActionGroupReceiver -Name $emailReceiverName -EmailReceiver -EmailAddress $emailAddress

# Create a new Action Group
$actionGroup = Set-AzActionGroup -Name $actionGroupName -ResourceGroup $ResourceGroup -ShortName $actionGroupShortName -Receiver $emailReceiver -Tag $tag




$source = New-AzScheduledQueryRuleSource -Query "AzureActivity | where Category == 'Policy' and Level != 'Informational' | extend p=todynamic(Properties) | extend policies=todynamic(tostring(p.policies)) | mvexpand policy = policies | where p.isComplianceCheck == 'False'" -DataSourceId "$Workspace.ResourceId"

$schedule = New-AzScheduledQueryRuleSchedule -FrequencyInMinutes 5 -TimeWindowInMinutes 5

$metricTrigger = New-AzScheduledQueryRuleLogMetricTrigger -ThresholdOperator "GreaterThan" -Threshold 0 -MetricTriggerType "Consecutive" -MetricColumn "_ResourceId"

$triggerCondition = New-AzScheduledQueryRuleTriggerCondition -ThresholdOperator "GreaterThan" -Threshold 0 -MetricTrigger $metricTrigger

$aznsActionGroup = New-AzScheduledQueryRuleAznsActionGroup -ActionGroup "$actionGroup.Id" -EmailSubject "New Resource Group with missing tags" -CustomWebhookPayload "{ `"alert`":`"#alertrulename`", `"IncludeSearchResults`":true }"

$alertingAction = New-AzScheduledQueryRuleAlertingAction -AznsAction $aznsActionGroup -Severity "3" -Trigger $triggerCondition

New-AzScheduledQueryRule -ResourceGroupName $ResourceGroup -Location $Location -Action $alertingAction -Enabled $true -Description "Alert description" -Schedule $schedule -Source $source -Name "Alert Name"

