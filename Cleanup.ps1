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

Properties created in cleanup job
CleanupStartTime
CleanupEndTime
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

<#
- Check all variables in the runbooks.
- Find all restore ids which has the following properties:
	- (Validation completed)
	- (Mannual sign off not needed && time window has passed) || (Mannual sign off is needed and given.)
- for each restore id:
	- Remove locks if any. Trigger the delete of Target Resource group.
	- Update the following properties in the entity:
		- "Test Restore job" status to "Cleanup in progress".
		- "Cleanup Start time" to DateTime.UtcNow.

- Check all variables in the runbooks.
- Find all restore ids which has the following properties:
	- (Cleanup in progress)
	- Check if deletion of resource group is complete?
		- Push the following in the report(LA):
			- Time when we found the deletion is completed.
			- <Any other thing?>
		- Update the "Test Restore job" status to "Cleanup Completed".
		- We are not deleting the variable. 
#>

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
	
	
	Write-Output "$(Get-Date) Validation completion time is $ValidationCompletionTime"
	$ExpectedDeletionTime = $ValidationCompletionTime.AddHours($CleanupTimeWindowInHours)
	Write-Output "$(Get-Date) Expected deletion time is $ExpectedDeletionTime"
	#Write-Output "$(Get-Date) Validation time"

	$rgExists = IfRGExists $targetResourceGroupName
	Write-Output "$(Get-Date) Resource group exists : $rgExists"
	
	if (($State -eq $VALIDATION_COMPLETED ) -And 
		(($MannualSignOff -eq $false -And ($ExpectedDeletionTime -lt $currentTime)) -Or
		 ($MannualSignOff -eq $true -And $MannualSignOffGiven -eq $true))
		)
	{
		Write-Output "$(Get-Date) Deleting the target resource group $targetResourceGroupName"
		$targetRG = Get-AzResource -ResourceGroupName $targetResourceGroupName
		#TODO : remove lock
		Get-AzResourceGroup -Name $targetResourceGroupName | Remove-AzResourceGroup -Force -AsJob
		Write-Output "$(Get-Date) Updating the state to $CLEANUP_IN_PROGRESS"
		Set-AutomationVariable -Name State -Value $CLEANUP_IN_PROGRESS
		Write-Output "$(Get-Date) Updating the cleanup start time to $currentTime"
		Set-AutomationVariable -Name CleanupStartTime -Value $currentTime
	}
	elseif (($State -eq $CLEANUP_IN_PROGRESS ) -And ($rgExists -eq $false))
	{
		#Not accurate
		Write-Output "$(Get-Date) Updating the cleanup end time to $currentTime"
		Set-AutomationVariable -Name CleanupEndTime -Value $currentTime
		#- Log Time when we found the deletion is completed.
		Write-Output "$(Get-Date) Updating the state to $CLEANUP_COMPLETED"
		Set-AutomationVariable -Name State -Value $CLEANUP_COMPLETED
	}
	elseif (($State -eq $CLEANUP_IN_PROGRESS ) -And ($rgExists -eq $true))
	{
		#Not accurate
		Write-Output "$(Get-Date) Cleanup of resource group is in progress"
	}
	else
	{
		Write-Output "$(Get-Date) No action is needed."
	}
	Write-Output "$(Get-Date) Script run is complete."
#}
