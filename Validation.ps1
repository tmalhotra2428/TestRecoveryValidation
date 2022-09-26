<#
    .DESCRIPTION
        Validation Script.

    .NOTES
        AUTHOR: Shashank Agarwal
        LASTEDIT: Sep 23, 2022
#>

#States of test restore jobs
$TEST_RESTORE_IN_PROGRESS = "TestRestoreInProgress"
$TEST_RESTORE_COMPLETED = "TestRestoreCompleted"
$VALIDATION_IN_PROGRESS = "ValidationInProgress"
$VALIDATION_COMPLETED = "ValidationCompleted"
$CLEANUP_IN_PROGRESS = "CleanupInProgress"
$CLEANUP_COMPLETED = "CleanupCompleted"

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

function IsValidationCompleted([string] $jobId)
{
	return $true
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
$testRestoreJobId = Get-AutomationVariable -Name JobId
#$restoreIds = GetTestRestoreJobs()
#foreach ($restoreId in $restoreIds)
#{
	#$entityInfo = GetTestRestoreInfo($restoreId)
	Write-Output "$(Get-Date) Current state is $State"
	
	$currentTime = Get-Date
	
	$protectedItem = Get-AutomationVariable -Name protectedItem
	Write-Host "$(Get-Date) protected item : $protectedItem"
	$protectedItemSplit = $protectedItem -split "/"
	$subscriptionId = $protectedItemSplit[2]
	Select-AzSubscription -SubscriptionId $subscriptionId
	$sourceResourceGroupName = $protectedItemSplit[4]
	$vaultName = $protectedItemSplit[8]
	$vault = Get-AzRecoveryServicesVault -ResourceGroupName $sourceResourceGroupName -Name $vaultName
	Set-AzRecoveryServicesVaultContext -Vault $vault
	
	if ($State -eq $TEST_RESTORE_IN_PROGRESS )
	{
		Write-Output "$(Get-Date)"
		#check if test restore is completed or not.

		if ($protectedItemSplit[9].Contains("backup"))
		{
			$currentJob = Get-AzRecoveryServicesBackupJobDetail -jobId $testRestoreJobId
			if(($currentJob.State -eq "InProgress") -or ($currentJob.State -eq "NotStarted"))
			{
				$testRestoreCompleted = $false
			}
			else
			{
				$testRestoreCompleted = $true
			}
		}
		else
		{
			$currentJob = Get-ASRJob -Name $testRestoreJobId
			if (($currentJob.State -eq "InProgress") -or ($currentJob.State -eq "NotStarted"))
			{
				$testRestoreCompleted = $false
			}
			else
			{
				$testRestoreCompleted = $true
			}
		}

		if ($testRestoreCompleted -eq $true)
		{
			Write-Output "$(Get-Date) Updating the state to $TEST_RESTORE_COMPLETED"
			Set-AutomationVariable -Name State -Value $TEST_RESTORE_COMPLETED

			#start validation
			$validationAutomationArmId = Get-AutomationVariable -Name 'ValidationAutomationARMId'
			
			if (($validationAutomationArmId -ne $Null) -and ($validationAutomationArmId -ne ""))
			{
				$validationAutomationArmSplit = $validationAutomationArmId -split "/"
				$validationAutomationRG = $validationAutomationArmSplit[4]
				$validationAutomationAccName = $validationAutomationArmSplit[8]
				$validationRunbookName = $validationAutomationArmSplit[10]
				
				$validationJob = Start-AzAutomationRunbook -AutomationAccountName $validationAutomationAccName -Name $validationRunbookName -ResourceGroupName $validationAutomationRG
				Set-AutomationVariable -Name 'ValidationJobId' -Value $validationJob.JobId

				Write-Output "$(Get-Date) Updating the state to $VALIDATION_IN_PROGRESS"
				Set-AutomationVariable -Name State -Value $VALIDATION_IN_PROGRESS
			}
			else
			{
				Write-Output "$(Get-Date) Updating the state to $VALIDATION_COMPLETED"
				Set-AutomationVariable -Name State -Value $VALIDATION_COMPLETED
			}
		}
		else
		{
			Write-Output "$(Get-Date) Test restore is in progress"	
		}
	}
	elseif ($State -eq $VALIDATION_IN_PROGRESS)
	{
		#check if validation is completed.
		$validationAutomationArmId = Get-AutomationVariable -Name 'ValidationAutomationARMId'

		if (($validationAutomationArmId -ne $Null) -and ($validationAutomationArmId -ne ""))
			{
				$validationAutomationArmSplit = $validationAutomationArmId -split "/"
				$validationAutomationRG = $validationAutomationArmSplit[4]
				$validationAutomationAccName = $validationAutomationArmSplit[8]
				$validationRunbookName = $validationAutomationArmSplit[10]
				
				$validationJobId = Get-AutomationVariable -Name ValidationJobId
				$JobDetails = Get-AzAutomationJob -AutomationAccountName $validationAutomationAccName -Id $validationJobId -ResourceGroupName $validationAutomationRG
				
				if (($JobDetails.status -eq "Completed") -or ($JobDetails.State -eq "Failed"))
				{
					Get-AzAutomationJobOutput -AutomationAccountName $validationAutomationAccName -Id $validationJobId -ResourceGroupName $validationAutomationRG -Stream "Any"
					Write-Output "$(Get-Date) Updating the state to $VALIDATION_COMPLETED"
					Set-AutomationVariable -Name State -Value $VALIDATION_COMPLETED
				}
				else
				{
					Write-Output "$(Get-Date) Validation is in progress."
				}
			}
	}
	elseif ($State -eq $TEST_RESTORE_COMPLETED)
	{
		#not expecting to reach this block.
		#TODO : start validation
		Write-Output "$(Get-Date) Updating the state to $VALIDATION_IN_PROGRESS"
		Set-AutomationVariable -Name State -Value $VALIDATION_IN_PROGRESS
	}
	else
	{
		Write-Output "$(Get-Date) No action is needed."
	}
	Write-Output "$(Get-Date) Script run is complete."
#}
