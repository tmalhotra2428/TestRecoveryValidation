<#
    .DESCRIPTION
        An example runbook which gets all the ARM resources using the Managed Identity

    .NOTES
        AUTHOR: Azure Automation Team
        LASTEDIT: Oct 26, 2021
#>

"Please enable appropriate RBAC permissions to the system identity of this automation account. Otherwise, the runbook may fail..."
Import-Module Az.RecoveryServices
try
{
    "Logging in to Azure..."
    Connect-AzAccount -Identity
}
catch {
    Write-Error -Message $_.Exception
    throw $_.Exception
}

<#Get all ARM resources from all resource groups
$ResourceGroups = Get-AzResourceGroup

foreach ($ResourceGroup in $ResourceGroups)
{    
    Write-Output ("Showing resources in resource group " + $ResourceGroup.ResourceGroupName)
    $Resources = Get-AzResource -ResourceGroupName $ResourceGroup.ResourceGroupName
    foreach ($Resource in $Resources)
    {
        Write-Output ($Resource.Name + " of type " +  $Resource.ResourceType)
    }
    Write-Output ("")
}#>

$protectedItem = Get-AutomationVariable -Name protectedItem
$protectedItemSplit = $protectedItem -split "/"

$protectedItemSplit

#$subscriptionId = Get-AutomationVariable -Name subscriptionId
$subscriptionId = $protectedItemSplit[2]
$subscriptionId
Select-AzSubscription -SubscriptionId $subscriptionId

#$sourceResourceGroupName = Get-AutomationVariable -Name sourceResourceGroup
$sourceResourceGroupName = $protectedItemSplit[4]
$sourceResourceGroupName

#$vaultName = Get-AutomationVariable -Name vault
$vaultName = $protectedItemSplit[8]
$vaultName
$vault = Get-AzRecoveryServicesVault -ResourceGroupName $sourceResourceGroupName -Name $vaultName 

if($protectedItemSplit[9].Contains("backup"))
{
	Write-Output "In Backup"
	#$sourceContainerName = Get-AutomationVariable -Name sourceVMName 
	$sourceContainerNameSplit = $protectedItemSplit[12] -split ";"
	$sourceContainerNameSplit
	$sourceContainerName = $sourceContainerNameSplit[3]
	$sourceContainerName
	$sourceContainerList =  Get-AzRecoveryServicesBackupContainer -ContainerType AzureVM -Status Registered -VaultId $vault.ID

	$sourceContainer = $sourceContainerList |  where {$_.FriendlyName.ToLower() -eq $sourceContainerName}

	$backupItem = Get-AzRecoveryServicesBackupItem -Container $sourceContainer[0] -WorkloadType AzureVM -VaultId $vault.ID

	$rpList = Get-AzRecoveryServicesBackupRecoveryPoint -Item $backupItem -VaultId $vault.ID

	$latestRp =  $rpList[0]

	#Create VNET and subnet
	<#$testSubnet = New-AzVirtualNetworkSubnetConfig -Name "testRestoreSubnet" -AddressPrefix "10.0.0.0/24"

	$testVnet = New-AzVirtualNetwork -AddressPrefix 10.33.0.0/16 -Location $vault.Location -Name $testVnetName -ResourceGroupName $targetResourceGroupName -Subnet $testSubnet
	$testVnet | Set-AzVirtualNetwork#>


	$testVnetName = Get-AutomationVariable -Name targetVNETName
	$targetResourceGroupName = $sourceContainerName+"_testResourceGroup_" + (Get-Date).Ticks

	New-AzResourceGroup -Name $targetResourceGroupName -Location $vault.Location

	Set-AutomationVariable -Name targetResourceGroupName -Value $targetResourceGroupName

	$vnet = @{
		Name = $testVnetName
		ResourceGroupName = $targetResourceGroupName
		Location = $vault.Location
		AddressPrefix = '10.0.0.0/16'    
	}
	$testVnet = New-AzVirtualNetwork @vnet

	$subnet = @{
		Name = 'testRestoreSubnet'
		VirtualNetwork = $testVnet
		AddressPrefix = '10.0.0.0/24'
	}
	$subnetConfig = Add-AzVirtualNetworkSubnetConfig @subnet

	$testVnet | Set-AzVirtualNetwork

	$storageAccountId = Get-AutomationVariable -Name storageAccount
	$storageAccountSplit = $storageAccountId -split "/"
	$storageAccountResourceGroup = $storageAccountSplit[4]
	$storageAccountName = $storageAccountSplit[8]

	#$storageAccountResourceGroup = Get-AutomationVariable -Name storageAccountRG
	$targetVMName = Get-AutomationVariable -Name targetVMName
	$targetVNETName = Get-AutomationVariable -Name targetVNETName
	$job = Restore-AzRecoveryServicesBackupItem -RecoveryPoint $latestRp -TargetResourceGroupName $targetResourceGroupName -StorageAccountName $storageAccountName -StorageAccountResourceGroupName $storageAccountResourceGroup -TargetVMName $targetVMName -TargetVNetName $targetVNETName -TargetVNetResourceGroup $targetResourceGroupName -TargetSubnetName "testRestoreSubnet" -VaultId $vault.ID -VaultLocation $vault.Location

	$job | Format-List *

	Set-AutomationVariable -Name JobId -Value $job.JobId
	Set-AutomationVariable -Name ActivityId -Value $job.ActivityId
}






