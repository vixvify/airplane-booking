[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$TotalRequests,

    [Parameter(Mandatory = $true, Position = 1)]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$Concurrency,

    [Parameter(Mandatory = $true, Position = 2)]
    [ValidateSet("STATUS", "RESERVE", "CANCEL")]
    [string]$Operation,

    [Parameter(Position = 3)]
    [ValidateRange(1, 20)]
    [Nullable[int]]$SeatId,

    [string]$ContainerName,
    [string]$ResultsDirectory
)

$ErrorActionPreference = "Stop"
$Operation = $Operation.ToUpperInvariant()
if ([string]::IsNullOrWhiteSpace($ContainerName)) {
    $ContainerName = if ([string]::IsNullOrWhiteSpace($env:AIRPLANE_CONTAINER_NAME)) {
        "airplane-reservation"
    } else {
        $env:AIRPLANE_CONTAINER_NAME
    }
}
if ([string]::IsNullOrWhiteSpace($ResultsDirectory)) {
    $ResultsDirectory = Join-Path $PSScriptRoot "..\results"
}
$ResultsDirectory = [System.IO.Path]::GetFullPath($ResultsDirectory)
New-Item -ItemType Directory -Force -Path $ResultsDirectory | Out-Null
$loadTestsDirectory = Join-Path $ResultsDirectory "load-tests"
New-Item -ItemType Directory -Force -Path $loadTestsDirectory | Out-Null

$timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd_HH-mm-ss-fff") + "Z"
$runDirectory = Join-Path $loadTestsDirectory $timestamp
$suffix = 2
while (Test-Path -LiteralPath $runDirectory) {
    $runDirectory = Join-Path $loadTestsDirectory "$timestamp-$suffix"
    $suffix++
}
New-Item -ItemType Directory -Path $runDirectory | Out-Null

$resultFile = Join-Path $runDirectory "output.log"
$serverLogFile = Join-Path $runDirectory "server.log"
$summaryFile = Join-Path $runDirectory "summary.txt"
$startedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffffffZ")
$loadExitCode = 1
$serverLogExitCode = 1
$failure = $null
$detectedExperiment = "unknown"
$detectedWorkerCount = "unknown"
$detectedLogMode = "unknown"
$docker = $null

try {
    $dockerExecutable = if ($env:DOCKER) { $env:DOCKER } else { "docker" }
    $dockerCommand = Get-Command $dockerExecutable -ErrorAction Stop
    $docker = $dockerCommand.Source
    $running = & $docker inspect --format '{{.State.Running}}' $ContainerName 2>&1
    if (($LASTEXITCODE -ne 0) -or ($running -ne "true")) {
        $running | Set-Content -Path $resultFile -Encoding UTF8
        $failure = "Server container '$ContainerName' is not running. Start the desired experiment first."
    }
    else {
        $serverDetails = & $docker inspect $ContainerName | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0) {
            throw "Cannot inspect server container '$ContainerName'."
        }
        $serverCommand = @($serverDetails[0].Config.Cmd)
        $workerCount = 0
        if ($serverCommand.Count -ne 3 -or
            $serverCommand[0] -ne "./server" -or
            $serverCommand[1] -notin @("sync", "nosync") -or
            -not [int]::TryParse([string]$serverCommand[2], [ref]$workerCount) -or
            $workerCount -lt 1 -or $workerCount -gt 64) {
            throw "Cannot detect server configuration from '$($serverCommand -join ' ')'. Expected ./server sync|nosync with 1-64 workers."
        }
        $detectedExperiment = if ($serverCommand[1] -eq "sync" -and $workerCount -eq 1) {
            "sequential"
        } else {
            $serverCommand[1]
        }
        $detectedWorkerCount = $workerCount
        Write-Host "Detected running experiment: $detectedExperiment"
        Write-Host "Detected worker count: $detectedWorkerCount"
        $logModeEntry = @($serverDetails[0].Config.Env) |
            Where-Object { $_ -like "AIRPLANE_LOG_MODE=*" } |
            Select-Object -Last 1
        $detectedLogMode = if ($logModeEntry) {
            $logModeEntry.Substring("AIRPLANE_LOG_MODE=".Length)
        } else {
            "verbose"
        }
        Write-Host "Detected server logging: $detectedLogMode"

        $arguments = @(
            "exec", $ContainerName, "./load_test",
            $TotalRequests.ToString(),
            $Concurrency.ToString(),
            $Operation
        )

        if ($null -ne $SeatId) {
            $arguments += $SeatId.ToString()
        }

        Write-Host "Saving load-test evidence to: $runDirectory"
        & $docker @arguments 2>&1 |
            Tee-Object -FilePath $resultFile
        $loadExitCode = $LASTEXITCODE

        if ($loadExitCode -ne 0) {
            $failure = "load_test exited with code $loadExitCode."
        }
    }
}
catch {
    $_ | Out-String | Set-Content -Path $resultFile -Encoding UTF8
    $failure = $_.Exception.Message
}
finally {
    try {
        if ($null -ne $docker) {
            & $docker logs --since $startedAt --timestamps $ContainerName 2>&1 |
                Set-Content -Path $serverLogFile -Encoding UTF8
            $serverLogExitCode = $LASTEXITCODE
        }
        else {
            "Docker was not found." |
                Set-Content -Path $serverLogFile -Encoding UTF8
        }
    }
    catch {
        $_ | Out-String |
            Set-Content -Path $serverLogFile -Encoding UTF8
    }

    $seatDescription =
        if ($null -eq $SeatId) { "round-robin 1-20" } else { $SeatId }

    @(
        "started_at=$startedAt"
        "finished_at=$((Get-Date).ToUniversalTime().ToString('o'))"
        "experiment=$detectedExperiment"
        "workers=$detectedWorkerCount"
        "log_mode=$detectedLogMode"
        "container_name=$ContainerName"
        "total_requests=$TotalRequests"
        "concurrency=$Concurrency"
        "operation=$Operation"
        "seat_id=$seatDescription"
        "load_output=output.log"
        "server_log=server.log"
        "load_exit_code=$loadExitCode"
        "server_log_exit_code=$serverLogExitCode"
    ) | Set-Content -Path $summaryFile -Encoding UTF8
}

if ($null -ne $failure) {
    Write-Error "$failure Evidence: $runDirectory" -ErrorAction Continue
    exit $loadExitCode
}

if ($serverLogExitCode -ne 0) {
    Write-Error "Load test passed, but server logs could not be saved. Evidence: $runDirectory" -ErrorAction Continue
    exit $serverLogExitCode
}

Write-Host "Load test finished. Results: $runDirectory"
