<#
    .DESCRIPTION
        Auto cleanup script.

    .NOTES
        AUTHOR: Shashank Agarwal
        LASTEDIT: Sep 20, 2022
#>

#States of test restore jobs
$CLEANUP_IN_PROGRESS = "CleanupInProgress"
$CLEANUP_COMPLETED = "CleanupCompleted"
$VALIDATION_IN_PROGRESS = "ValidationInProgress"
$VALIDATION_COMPLETED = "ValidationCompleted"

<# properties expecting in Cleanup job for every entity
State
MannualSignOff = Default value should be false.
MannualSignOffGiven
ValidationCompletionTime
CleanupTimeWindowHours
targetResourceGroupName
RestoreId

CleanupStartTime
CleanupEndTime

protectedItem
ASRCleanupJobId
#>
function GetTestRestoreJobs()
{
	$restoreJobIds = Get-AutomationVariable -Name "jobIds"
	#deserialize restoreJobIds
	return $restoreJobIds
}

function GetTestRestoreInfo([string] $id)
{
	$entityInfo = New-Object System.Collections.Generic.Dictionary"[String,String]"
	#$entityInfo.Add("State", Get-AutomationVariable -Name "State")
	#$entityInfo.Add("MannualSignOff", Get-AutomationVariable -Name "MannualSignOff")
	#$entityInfo.Add("MannualSignOffGiven", Get-AutomationVariable -Name "MannualSignOffGiven")
	#$entityInfo.Add("ValidationCompletionTime", Get-AutomationVariable -Name "ValidationCompletionTime")
	#$entityInfo.Add("State", Get-AutomationVariable -Name "State")
	return $testJobInfo
}

function IfRGExists([string] $rgName)
{
	$rg = Get-AzResourceGroup `
			-Name $rgName `
			-ErrorVariable notPresent `
			-ErrorAction SilentlyContinue
	
	if ($notPresent)
	{
		return $false
	}
	else
	{
		return $true
	}
}

function TriggerCleanup([string] $targetResourceGroupName)
{
	$protectedItem = Get-AutomationVariable -Name protectedItem
	$protectedItemSplit = $protectedItem -split "/"
	$subscriptionId = $protectedItemSplit[2]
	Select-AzSubscription -SubscriptionId $subscriptionId
	$sourceResourceGroupName = $protectedItemSplit[4]
	$vaultName = $protectedItemSplit[8]
	$vault = Get-AzRecoveryServicesVault -ResourceGroupName $sourceResourceGroupName -Name $vaultName 
	
	if($protectedItemSplit[9].Contains("backup"))
	{
		Write-Output "$(Get-Date) Backup: Deleting the target resource group $targetResourceGroupName"
		$targetRG = Get-AzResource -ResourceGroupName $targetResourceGroupName
		#TODO : remove lock
		Get-AzResourceGroup -Name $targetResourceGroupName | Remove-AzResourceGroup -Force -AsJob
	}
	else
	{			
		Set-AzRecoveryServicesAsrVaultSettings -Vault $vault
		$sourceContainerName = $protectedItemSplit[12]
		$primaryFabricObject = Get-AzRecoveryServicesAsrFabric -Name $protectedItemSplit[10]
		$primaryContainerObject = Get-AzRecoveryServicesAsrProtectionContainer -Fabric $primaryFabricObject -Name $sourceContainerName
		$protectedItemObject = Get-AzRecoveryServicesAsrReplicationProtectedItem -ProtectionContainer $primaryContainerObject -Name $protectedItemSplit[14]
		Write-Output "$(Get-Date) ASR: Triggerig the TFO cleanup for protected item : $protectedItem"
		$currentJob = Start-AzRecoveryServicesAsrTestFailoverCleanupJob -ReplicationProtectedItem $protectedItemObject -Comment "TFO cleanup"
		Set-AutomationVariable -Name ASRCleanupJobId -Value $currentJob.Id
	}
}

function IsCleanupCompleted([string] $targetResourceGroupName)
{
	Write-Output "$(Get-Date) Checking if cleanup is completed."
	$protectedItem = Get-AutomationVariable -Name protectedItem
	$protectedItemSplit = $protectedItem -split "/"
	$subscriptionId = $protectedItemSplit[2]
	Select-AzSubscription -SubscriptionId $subscriptionId
	$sourceResourceGroupName = $protectedItemSplit[4]
	$vaultName = $protectedItemSplit[8]
	$vault = Get-AzRecoveryServicesVault -ResourceGroupName $sourceResourceGroupName -Name $vaultName 
	
	if($protectedItemSplit[9].Contains("backup"))
	{
		Write-Output "$(Get-Date) Backup: checking if RG exists $targetResourceGroupName"
		$rgExists = IfRGExists $targetResourceGroupName
	}
	else
	{			
		Set-AzRecoveryServicesAsrVaultSettings -Vault $vault
		Write-Output "$(Get-Date) ASR: Checking TFO cleanup status for job id : "
		$jobId = Get-AutomationVariable -Name ASRCleanupJobId
		$currentJob = Get-ASRJob -Name $jobId
		if (($currentJob.State -eq "InProgress") -or ($currentJob.State -eq "NotStarted"))
		{
			return $false
		}
		else
		{
			return $true
		}
	}
}

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

$State =  Get-AutomationVariable -Name State
$MannualSignOff = Get-AutomationVariable -Name MannualSignOff
$ValidationCompletionTime = Get-AutomationVariable -Name ValidationCompletionTime
$MannualSignOffGiven = Get-AutomationVariable -Name MannualSignOffGiven
$CleanupTimeWindowInHours = Get-AutomationVariable -Name CleanupTimeWindowHours
$targetResourceGroupName = Get-AutomationVariable -Name targetResourceGroup1
#$restoreIds = GetTestRestoreJobs()
#foreach ($restoreId in $restoreIds)
#{
	#$entityInfo = GetTestRestoreInfo($restoreId)
	Write-Output "$(Get-Date) Current state is $State"
	
	$currentTime = Get-Date

	Write-Output "$(Get-Date) Expected Validation completion time is $ValidationCompletionTime"
	$ExpectedDeletionTime = $ValidationCompletionTime.AddHours($CleanupTimeWindowInHours)
	Write-Output "$(Get-Date) Expected deletion time is $ExpectedDeletionTime"
	#Write-Output "$(Get-Date) Validation time"

	if (($State -eq $VALIDATION_COMPLETED ) -And 
		(($MannualSignOff -eq $false -And ($ExpectedDeletionTime -lt $currentTime)) -Or
		 ($MannualSignOff -eq $true -And $MannualSignOffGiven -eq $true))
		)
	{
		TriggerCleanup $targetResourceGroupName
		
		Write-Output "$(Get-Date) Updating the state to $CLEANUP_IN_PROGRESS"
		Set-AutomationVariable -Name State -Value $CLEANUP_IN_PROGRESS
		Write-Output "$(Get-Date) Updating the cleanup start time to $currentTime"
		Set-AutomationVariable -Name CleanupStartTime -Value $currentTime
	}
	elseif ($State -eq $CLEANUP_IN_PROGRESS)
	{
		
		$isCleanupCompleted = IsCleanupCompleted $targetResourceGroupName
		Write-Output "$(Get-Date) Cleanup complete status : $isCleanupCompleted"

		if ($isCleanupCompleted -eq $true)
		{
			#Not accurate
			Write-Output "$(Get-Date) Updating the cleanup end time to $currentTime"
			Set-AutomationVariable -Name CleanupEndTime -Value $currentTime
			#- Log Time when we found the deletion is completed.
			Write-Output "$(Get-Date) Updating the state to $CLEANUP_COMPLETED"
			Set-AutomationVariable -Name State -Value $CLEANUP_COMPLETED
		}
		else
		{
			Write-Output "$(Get-Date) Cleanup is in progress"
		}
	}
	else
	{
		Write-Output "$(Get-Date) No action is needed."
	}
	Write-Output "$(Get-Date) Script run is complete."
#}
