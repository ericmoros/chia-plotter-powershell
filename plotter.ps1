$ErrorActionPreference = "Stop"

class PlotterObject {
    [string] toString() {
        return ($this | ConvertTo-Json -depth 100)
    }
}

class LogManager : PlotterObject {
    
    [string] $Path    

    LogManager(
        [string] $Path
    ) {
        $this.Path = $Path       
    }
    
    [void] Write([String] $Message) {
        $Message >> $this.Path
    }
}

$LogDirPath = "log"
New-Item -ItemType Directory -Force -Path $LogDirPath | Out-Null

$global:Log = [LogManager]::new("$($LogDirPath)\\Plotter-$(Get-Date -Format "yyyyMMdd_hhmmss").log")

class Task : PlotterObject {
    [int] $Id
    [string] $JobName
    [string] $Command
    [string] $EventName
    [System.Collections.ArrayList] $Messages = @()
    [int] $Gap = 0
    [int] $Loop = 0
    [DateTime] $StartDate
    [System.Management.Automation.Job] $Job
    [System.Management.Automation.Job] $JobMessages
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

    [int] GetPercentage() {
        return $this.Messages.Count / 2626 * 100
    }

    [void] AddMessages([string] $message) {
        $this.AddMessage($message)
    }
        
    [void] AddMessages([object[]] $messages) {
        $messages | Foreach-Object {
            $message = [string]$_
            $this.AddMessage($message)
        }
    }
    
    [void] AddMessage([string] $message) {
        $this.Messages.Add("$message")        
    }

    [void] CleanMessages() {
        $this.Messages = @()
    }
    
    [void] ExecuteCommand() {
        $this.ExecuteCommand($this.Gap)
    }

    [void] ExecuteCommand([int] $gap) {
        $this.Loop++

        $jobNameLoop = "$($this.JobName) - Loop $($this.Loop)"
        $this.job = Start-Job -Name $jobNameLoop -ArgumentList $this, $gap -Scriptblock {
            param($task, $gap)
            try {
                Start-Sleep $gap
                $task.StartDate = Get-Date
                #  Write-Host ($task | ConvertTo-Json -depth 1)
                Invoke-Expression $task.Command
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
                Write-Host $task.GetStatus() -Fore White -Back Red
                if ($jobState -eq "Completed") {
                    $task.CleanMessages()
                    Write-Host ""
                    $ErrorActionPreference = "Continue"
                    $receiveMessages = Receive-Job $job
                    $ErrorActionPreference = "Stop"

                    if (-not($null -eq $receiveMessages)) {
                        $task.AddMessages($receiveMessages)
                    }

                    $status = $task.GetStatus()

                    $global:Log.Write($status)
                    Write-Host $status -Fore White -Back DarkBlue

                    $global:Log.Write($receiveMessages)
                    Write-Host $receiveMessages
                    
                    Remove-Job $job.Id
                    $eventSubscriber | Unregister-Event
                    $eventSubscriber.Action | Remove-Job
                    $task.ExecuteCommand(0)
                }
            }
            catch {
                Write-Output "Event error"
                Write-Output $PSItem
            }
        } | Out-Null

        Write-Host "Programed Job $($this.job.Name) with Gap $($this.Gap): $($this.Command)"
    }

    [string] GetStatus() {
        return "$($this.job.Name) $($this.job.State) - $(Get-Date -Format "dd/MM/yyyy HH:mm:ss") - $($this.GetPercentage())%"
    }

    [void] Monitorice() {
        if (-not ($this.job.State -eq "Completed" -or $this.job.State -eq "NotStarted")) {
            $ErrorActionPreference = "Continue"
            $receiveMessages = Receive-Job $this.job
            $ErrorActionPreference = "Stop"

            if (-not($null -eq $receiveMessages)) {
                $this.AddMessages($receiveMessages)
            }

            $status = $this.GetStatus()

            $global:Log.Write($status)
            Write-Host $status -Fore White -Back DarkBlue

            $global:Log.Write($receiveMessages)
            Write-Host $receiveMessages
        }
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
            $task.ExecuteCommand($task.Gap)
        }
        # $tasks
    }

    [void] Monitorice() {
        Start-Sleep 1
        $tasks = $this._tasks
        if ($null -eq $tasks) {
            return
        }
        $tasks | Foreach-Object {
            $task = [Task]$_
            $task.Monitorice()
            Start-Sleep 1
        }
    }
}

function Read-Config-Parameters($configFile) {
    $defaultParameters = Get-Content -Raw $configFile | ConvertFrom-Json
    foreach ($globalProperty in $defaultParameters.globalOptions | Get-Member -MemberType NoteProperty) {
        $globalKey = $globalProperty.Name
        $globalValue = $defaultParameters.globalOptions | Select-Object -ExpandProperty $globalKey
        foreach ($plot in $defaultParameters.plots) {
            $hasPlotKey = (($plot | Get-Member -MemberType NoteProperty) | Select -ExpandProperty Name) -contains $globalKey
            if (-not $hasPlotKey) {
                $plot | Add-Member -Name $globalKey -Type NoteProperty -Value $globalValue
            }
        }
    }
    $defaultParameters.plots = $defaultParameters.plots | Where-Object { $_.enabled }

    # $parameters | ConvertTo-Json -depth 100 | Out-File $configFile
    return $defaultParameters
}

function Read-User-Parameters($defaultParameters) {
    foreach ($plot in $defaultParameters.plots) {
        if ($plot.useDefaultParameters) {
            continue    
        }
        
        $parameters = $plot
        
        $hasToKillExistingJobs = $false
        $hasToRemoveTemporalFiles = $false
        
        
        # Asks user to kill current jobs
        $jobs = Get-Job
        $jobsCount = @($jobs).count
        if ($jobsCount -gt 0) {
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
        
        $parameters.hasToKillExistingJobs = $hasToKillExistingJobs
        $parameters.hasToRemoveTemporalFiles = $hasToRemoveTemporalFiles
    }

    return $defaultParameters
}

function Test-User-Parameters($parameters) {
    foreach ($plot in $parameters.plots) {
        if (-not(Test-Path -Path $plot.chiaExe -PathType Leaf)) {
            Write-Warning "$($plot.chiaExe)"
            Write-Error "`$chiaExe does not exists"    
        }

        if (-not(Test-Path -Path $plot.temporal)) {
            Write-Warning "$($plot.temporal)"
            $userInput = Read-Host -Prompt "Create temporal directory? (y/any)"
            $userInput = $userInput.ToLower()
            if ($userInput -eq "y") {
                New-Item -ItemType directory -Path $plot.temporal
                Write-Host "`$plot.temporal created!"
            }
            else {
                Write-Error "`$plot.temporal does not exists"
            }
        }

        if (-not(Test-Path -Path $plot.final)) {
            Write-Warning "$($plot.final)"
            $userInput = Read-Host -Prompt "kill all jobs? (y/any)"
            $userInput = $userInput.ToLower()
            if ($userInput -eq "y") {
                New-Item -ItemType directory -Path $plot.temporal
                Write-Host "`$plot.final created!"
            }
            else {
                Write-Error "`$plot.final does not exists"
            }
        }
    }
}

function Start-User-Parameters($parameters) {

    Write-Host ""
    Write-Host "MUAAJAJAJA..."
    Write-Host ""

    # Executing parameters
    if ($parameters.hasToKillExistingJobs) {
        Get-EventSubscriber | Unregister-Event
        $jobs = Get-job
        if (-not $jobs -eq $null) {
            Write-Host "Killing jobs please wait..."
            $jobs | Stop-Job
            $jobs | Remove-Job
        }
        
    }
    foreach ($plot in $parameters.plots) {
        if ($plot.hasToRemoveTemporalFiles) {
            $files = Get-ChildItem -Path $plot.temporal -Include *.tmp -File -Recurse
            if ($files.Count -gt 0) {
                Write-Host "Removing $($files.Count) files from $($plot.temporal) please wait..."
                $files | ForEach-Object { $_.Delete() }
            }
        }
    }

    Write-Host ""

    Start-Sleep 1
    Write-Host "Ok"
    Start-Sleep 1
    Write-Host "Lets fuck this drives"
    Write-Host ""
    Start-Sleep 1
}

function Plot-Or-Die {
    $configFile = 'config.json'
    $defaultParameters = Read-Config-Parameters $configFile
    $parameters = Read-User-Parameters $defaultParameters
    Test-User-Parameters $parameters
    Start-User-Parameters $parameters
    [System.Collections.ArrayList] $taskManagers = @()


    for ($i = 0; $i -lt $parameters.plots.Count; $i++) {
        $plot = $parameters.plots[$i]
        $TaskManagerId = $i + 1
        $TaskManagerCommand = "& $($plot.chiaExe) plots create --tmp_dir $($plot.temporal) --final_dir $($plot.final) --num_threads $($plot.threads) --buffer $($plot.maxMemory) -p $($plot.poolKey) -f $($plot.farmerKey)"
        $TaskManagerPrefix = "Task $($TaskManagerId) - $($plot.prefix)"
        $TaskManagerGap = $plot.gapMin
        $TaskManagerTotalTasks = $plot.paralel
    
        $taskManager = [TaskManager]::new(
            $TaskManagerId,
            $TaskManagerCommand,
            $TaskManagerPrefix,
            $TaskManagerGap,
            $TaskManagerTotalTasks
        )

        $taskManagers.Add($taskManager)
    
        $taskManager.LoadTasks()
    
        Write-host $taskManager.toString()
        $taskManager.ExecuteTasks()
    }

    while ($true) {
        foreach ($taskManager in $taskManagers) {
            $taskManager.Monitorice()
        }
    }
}


Plot-Or-Die
