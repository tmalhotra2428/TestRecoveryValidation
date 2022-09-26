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

#States of test restore jobs
$CLEANUP_COMPLETED = "CleanupCompleted"
$TEST_RESTORE_IN_PROGRESS = "TestRestoreInProgress"
$TEST_RESTORE_TRIGGER_FAILED = "TestRestoreTriggerFailed"

$state = Get-AutomationVariable -Name State
if(($state -ne $CLEANUP_COMPLETED) -and ($state -ne $TEST_RESTORE_TRIGGER_FAILED))
{
	Write-Output "Cleanup is not yet completed. Skipping operation."
	Exit
}

$protectedItem = Get-AutomationVariable -Name protectedItem
$protectedItemSplit = $protectedItem -split "/"


$subscriptionId = $protectedItemSplit[2]

Select-AzSubscription -SubscriptionId $subscriptionId

$sourceResourceGroupName = $protectedItemSplit[4]


$vaultName = $protectedItemSplit[8]

$vault = Get-AzRecoveryServicesVault -ResourceGroupName $sourceResourceGroupName -Name $vaultName 


if($protectedItemSplit[9].Contains("backup"))
{
	Write-Output "In Backup's Restore"
	
	$sourceContainerNameSplit = $protectedItemSplit[12] -split ";"
	$sourceContainerName = $sourceContainerNameSplit[3]
	$sourceContainerList =  Get-AzRecoveryServicesBackupContainer -ContainerType AzureVM -Status Registered -VaultId $vault.ID

	$sourceContainer = $sourceContainerList |  where {$_.FriendlyName.ToLower() -eq $sourceContainerName}

	$backupItem = Get-AzRecoveryServicesBackupItem -Container $sourceContainer[0] -WorkloadType AzureVM -VaultId $vault.ID

	$rpList = Get-AzRecoveryServicesBackupRecoveryPoint -Item $backupItem -VaultId $vault.ID

	$latestRp =  $rpList[0]

	$targetResourceGroupName = $sourceContainerName+"_testResourceGroup_" + (Get-Date).Ticks
	New-AzResourceGroup -Name $targetResourceGroupName -Location $vault.Location
	Set-AutomationVariable -Name targetResourceGroupName -Value $targetResourceGroupName

	$testVnetName = "testVNET"

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
	#$targetVNETName = Get-AutomationVariable -Name targetVNETName
	$job = Restore-AzRecoveryServicesBackupItem -RecoveryPoint $latestRp -TargetResourceGroupName $targetResourceGroupName -StorageAccountName $storageAccountName -StorageAccountResourceGroupName $storageAccountResourceGroup -TargetVMName $targetVMName -TargetVNetName $testVnetName -TargetVNetResourceGroup $targetResourceGroupName -TargetSubnetName "testRestoreSubnet" -VaultId $vault.ID -VaultLocation $vault.Location

	$job | Format-List *

	if($job)
	{
		Set-AutomationVariable -Name JobId -Value $job.JobId
		Set-AutomationVariable -Name ActivityId -Value $job.ActivityId
	}
	else
	{
		Set-AutomationVariable -Name State -Value $TEST_RESTORE_TRIGGER_FAILED
	}

}
else
{
	Write-Output "In ASR's Failover"
	
	Set-AzRecoveryServicesAsrVaultSettings -Vault $vault

	$sourceContainerName = $protectedItemSplit[12]

	$primaryFabricObject = Get-AzRecoveryServicesAsrFabric -Name $protectedItemSplit[10]

	$primaryContainerObject = Get-AzRecoveryServicesAsrProtectionContainer -Fabric $primaryFabricObject -Name $sourceContainerName

	$protectedItemObject = Get-AzRecoveryServicesAsrReplicationProtectedItem -ProtectionContainer $primaryContainerObject -Name $protectedItemSplit[14]

	$recoveryPoints = Get-AzRecoveryServicesAsrRecoveryPoint -ReplicationProtectedItem $protectedItemObject 

	$latestRp =  $recoveryPoints[0]

	$targetResourceGroupName = $sourceContainerName+"_testResourceGroup_" + (Get-Date).Ticks
	New-AzResourceGroup -Name $targetResourceGroupName -Location $vault.Location
	Set-AutomationVariable -Name targetResourceGroupName -Value $targetResourceGroupName
	
	$testVnetName = "testVNET"

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

	
	$job = Start-AzRecoveryServicesAsrTestFailoverJob -ReplicationProtectedItem $protectedItemObject -Direction PrimaryToRecovery -RecoveryPoint $latestRp -AzureVMNetworkId $testVnet.Id
	$job | Format-List *

	if($job)
	{
		Set-AutomationVariable -Name JobId -Value $job.ID
	}
	else
	{
		Set-AutomationVariable -Name State -Value $TEST_RESTORE_TRIGGER_FAILED
	}
	
}

Set-AutomationVariable -Name State -Value $TEST_RESTORE_IN_PROGRESS
exit $LASTEXITCODE


