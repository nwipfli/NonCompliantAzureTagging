Non Compliant Resource Groups Alert
===================================
Description
-----------
This project can be used to deploy a mechanism on your Azure subscription to send emails each time a Resource Group is created without mandatory tags which you define as per the instructions below.
This mechanism uses an Azure Log Analytic Workspace connected to the Azure Activity Log. With a search query in the Alert rule, a email is triggered once a new resource group is created without those tags.

Variables
---------
- **subscriptionName**: Stores the name of your subscription
- **tagsArray**: An array which stores the key/value pairs for your tags. The keys are used for the Azure Policy and the values are only used for the resources deployed with this script.
- **Location**: Your Azure region.
- **ResourceGroup**: The name of your resource group that needs to be created for the Workspace and Alert Action Group.
- **WorkspaceName**: Name of your new Workspace.
- **emailReceiverName**: Name of the recipient receiving the alerts.
- **emailAddress**: Email address of the recipient receiving the alerts.
- **actionGroupName**: Name for your Alert Action Group.
- **actionGroupShortName**: Action Group shortname (max 12 characters).

Usage
-----
1. Edit the file _deployment.ps1_.
2. Either copy locally all the files from this projet or do a _git clone_.
3. Update the variables with the values you need.
4. Execute the script _./deployment.ps1_.

---

Credits
-------
Thanks to Tao Yang and his [article](https://techcommunity.microsoft.com/t5/itops-talk-blog/how-to-create-azure-monitor-alerts-for-non-compliant-azure/ba-p/713466) which was useful to understand which search query to use for the Workspace.