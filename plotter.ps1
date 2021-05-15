$ErrorActionPreference = "Stop"

class PlotterObject {
    [string] toString() {
        return ($this | ConvertTo-Json -depth 100)
    }
}

class Task : PlotterObject {
    [int] $Id
    [string] $JobName
    [string] $Command
    [string] $EventName
    [int] $Gap = 0
    [int] $Loop = 0
    [DateTime] $StartDate
    [System.Management.Automation.Job] $Job
    [System.Management.Automation.PSEventJob] $Event

    Task(
        [int] $Id,
        [string] $JobName,
        [string] $Command,
        [string] $EventName,
        [int] $Gap
    ) {
        $this.Id = $Id
        $this.JobName = $JobName
        $this.Command = $Command
        $this.EventName = $EventName
        $this.Gap = $Gap
    }

    [void] ExecuteCommand() {
        $this.ExecuteCommand($this.Gap)
    }

    [void] ExecuteCommand([int] $gap) {
        $this.Loop++
        $this.StartDate = Get-Date

        $jobNameLoop = "$($this.JobName) - Loop $($this.Loop)"

        $this.job = Start-Job -Name $jobNameLoop -ArgumentList $this -Scriptblock {
            param($task)
            try {
                Write-Host ($task | ConvertTo-Json -depth 1)
                Invoke-Expression $task.Command
                Start-Sleep 5
            }
            catch {
                Write-Output "Job error"
                Write-Output $PSItem
            }
        }

        $eventNameLoop = "$($this.EventName) - Loop $($this.Loop)"

        $this.Event = Register-ObjectEvent $this.job -SourceIdentifier $eventNameLoop StateChanged -MessageData $this -Action {
            try {
                $job = $sender
                [Task] $task = $event.MessageData
                # [Console]::Beep(1000, 500)
                $jobState = $job.State
                Write-Host "Event Job $($job.Name): $($jobState)" -Fore White -Back Red
                if ($jobState -eq "Completed") {
                    Write-Host "$($event.MessageData.JobName) - Loop $($event.MessageData.Loop)"
                    Write-Host ""
                    $ErrorActionPreference = "Continue"
                    Receive-Job $job
                    $ErrorActionPreference = "Stop"
                    Remove-Job $job.Id
                    $eventSubscriber | Unregister-Event
                    $eventSubscriber.Action | Remove-Job
                    $task.ExecuteCommand(0)
                }
            }   catch {
                Write-Output "Event error"
                Write-Output $PSItem
            }
        } | Out-Null

        Write-Host "Started $($this.job.Name): $($this.Command)"
    }

    [string] toString() {
        return ($this | ConvertTo-Json -depth 100)
    }
}


class TaskManager : PlotterObject {
    [int] $Id
    [string] $Prefix
    [int] $Gap
    [string] $_command
    [System.Collections.ArrayList] $_tasks = @()
    [int] $_totalTasks

    TaskManager(
        [int] $Id,
        [string] $Command,
        [string] $Prefix,
        [int] $Gap,
        [int] $TotalTasks
    ) {
        $this.Id = $Id
        $this._command = $Command
        $this.Prefix = $Prefix
        $this.Gap = $Gap
        $this._totalTasks = $TotalTasks
    }

    [void] Add([Task] $Task) {
        $this._tasks.Add($Task)
    }

    [void] LoadTasks() {
        for ($i = 0; $i -lt $this._totalTasks; $i++) {
            $taskId = $i + 1
            $jobName = "$($this.Prefix) $($taskId)"
            $eventName = "$($jobName) Event "
            $gapSec = $this.Gap * 60 * $i
            $task = [Task]::new($taskId, $jobName, $this._command, $eventName, $gapSec)
            $this.Add($task)
        }
        # $tasks
    }

    [void] ExecuteTasks() {
        for ($i = 0; $i -lt $this._totalTasks; $i++) {
            [Task] $task = $this._tasks[$i]
            $task.ExecuteCommand()
        }
        # $tasks
    }
}

function Read-User-Parameters($defaultParameters) {
    if ($defaultParameters.useDefaultParameters) {
        return $defaultParameters
    }

    $hasToKillExistingJobs = $false
    $hasToRemoveTemporalFiles = $false


    # Asks user to kill current jobs
    $jobs = Get-Job
    $jobsCount = @($jobs).count
    if($jobsCount -gt 0) {
        Write-Host ""
        Get-Job

        $userInput = Read-Host -Prompt "kill all jobs? (y/any)"
        $userInput = $userInput.ToLower()
        if ($userInput -eq "y") {
            Write-Host "We will kill the jobs with suffering"
            $hasToKillExistingJobs = $true
        }
    }

    Write-Host ""

    # Asks user to remove temporal files
    $userInput = Read-Host -Prompt "Delete all contents from temporal path? (y/any): $($temporal)"
    $userInput = $userInput.ToLower()
    if ($userInput -eq "y") {
        Write-Host "That little files, will never forget the delete"
        $hasToRemoveTemporalFiles = $true
    }

    return [pscustomobject]@{
        hasToKillExistingJobs = $hasToKillExistingJobs
        hasToRemoveTemporalFiles = $hasToRemoveTemporalFiles
        #Not edited....
        chiaExe = $defaultParameters.chiaExe
        poolKey = $defaultParameters.poolKey
        farmerKey = $defaultParameters.farmerKey
        temporal = $defaultParameters.temporal
        final = $defaultParameters.final
        paralel = $defaultParameters.paralel
        threads = $defaultParameters.threads
        maxMemory = $defaultParameters.maxMemory
        gapMin = $defaultParameters.gapMin
    }
}

function Test-User-Parameters($parameters) {
    if (-not(Test-Path -Path $parameters.chiaExe -PathType Leaf)) {
        Write-Warning "$($parameters.chiaExe)"
        Write-Error "`$chiaExe does not exists"    
    }
    if (-not(Test-Path -Path $parameters.temporal)) {
        Write-Warning "$($parameters.parameters.temporal)"
        Write-Error "`$parameters.temporal does not exists"    
    }
    if (-not(Test-Path -Path $parameters.final)) {
        Write-Warning "$($parameters.final)"
        Write-Error "`$final does not exists"    
    }
}

function Start-User-Parameters($hasToKillExistingJobs, $hasToRemoveTemporalFiles) {

    Write-Host ""
    Write-Host "MUAAJAJAJA..."
    Write-Host ""

    # Executing parameters
    if ($hasToKillExistingJobs) {
        Write-Host "Killing jobs please wait..."
        Get-EventSubscriber | Unregister-Event
        Get-job | Stop-Job
        Get-job | Remove-Job
        
    }
    if ($hasToRemoveTemporalFiles) {
        Write-Host "Removing files please wait..."
        Get-ChildItem -Path $temporal -Include *.tmp -File -Recurse | ForEach-Object { $_.Delete()}
    }

    Write-Host ""

    Start-Sleep 1
    Write-Host "Ok"
    Start-Sleep 1
    Write-Host "Lets fuck this drives"
    Write-Host ""
    Start-Sleep 1
}

function Show-Jobs {
    Write-Host ""
    Write-Host "Running..."
    Write-Host "
    "
    while ($true) {
        $jobs = Get-Job
        $jobs | Foreach-Object {
            $job = $_
            if (-not ($job.State -eq "Completed" -or $job.State -eq "NotStarted")) {
                Write-Host "$($job.Name) $($job.State)" -Fore White -Back Black
                $ErrorActionPreference = "Continue"
                Receive-Job $job
                $ErrorActionPreference = "Stop"
                Start-Sleep 1
            }
        }
    }

}


function Plot-Or-Die {
    # $logParentPath = "."
    $configFile = 'config.json'

    $defaultParameters = Get-Content -Raw $configFile | ConvertFrom-Json
    $parameters = Read-User-Parameters $defaultParameters
    Test-User-Parameters $parameters
    $parameters | ConvertTo-Json -depth 100 | Out-File $configFile
    Start-User-Parameters $parameters.hasToKillExistingJobs $parameters.hasToRemoveTemporalFiles

    if ($parameters.hasToKillExistingJobs -eq $true) {
        $TaskManagerId = 1
        $TaskManagerCommand = "& $($parameters.chiaExe) plots create --tmp_dir $($parameters.temporal) --final_dir $($parameters.final) --num_threads $($parameters.threads) --buffer $($parameters.maxMemory) -p $($parameters.poolKey) -f $($parameters.farmerKey)"
        $TaskManagerPrefix = "Chia"
        $TaskManagerGap = $parameters.gapMin
        $TaskManagerTotalTasks = $parameters.paralel
    
        $taskManager = [TaskManager]::new(
            $TaskManagerId,
            $TaskManagerCommand,
            $TaskManagerPrefix,
            $TaskManagerGap,
            $TaskManagerTotalTasks
        )
    
        $taskManager.LoadTasks()
    
        Write-host $taskManager.toString()
        $taskManager.ExecuteTasks()
    }
    Show-Jobs
}


Plot-Or-Die
