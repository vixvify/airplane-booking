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

    [string]$ClientService = "client-1",
    [string]$ResultsDirectory
)

$ErrorActionPreference = "Stop"
$Operation = $Operation.ToUpperInvariant()
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
$detectedLogMode = "unknown"
$docker = $null
$composeArgs = @()

try {
    $dockerCommand = Get-Command docker -ErrorAction Stop
    $docker = $dockerCommand.Source
    $projectDirectory = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    $composeDirectory = Join-Path $projectDirectory "compose"
    $projectName = if ([string]::IsNullOrWhiteSpace($env:COMPOSE_PROJECT_NAME)) {
        Split-Path -Leaf $projectDirectory
    } else {
        $env:COMPOSE_PROJECT_NAME
    }
    $composeArgs = @(
        "compose", "--project-directory", $composeDirectory,
        "--project-name", $projectName,
        "-f", (Join-Path $composeDirectory "compose.yaml")
    )
    $services = & $docker @composeArgs ps --status running --services 2>&1
    if (($LASTEXITCODE -ne 0) -or ($services -notcontains "server")) {
        $services | Set-Content -Path $resultFile -Encoding UTF8
        $failure = "Compose server is not running for project '$projectName'. Start the desired experiment first."
    }
    else {
        $serverContainerId = & $docker @composeArgs ps --quiet server
        if (($LASTEXITCODE -ne 0) -or [string]::IsNullOrWhiteSpace($serverContainerId)) {
            throw "Cannot find the running Compose server container."
        }

        $serverDetails = & $docker inspect $serverContainerId | ConvertFrom-Json
        $serverCommand = @($serverDetails[0].Config.Cmd)
        $serverConfiguration = if ($serverCommand.Count -ge 3) {
            "$($serverCommand[1]) $($serverCommand[2])"
        } else {
            ""
        }
        $experimentByConfiguration = @{
            "sync 1" = "sequential"
            "nosync 3" = "nosync"
            "sync 3" = "sync"
        }
        if (-not $experimentByConfiguration.ContainsKey($serverConfiguration)) {
            throw "Cannot detect experiment from running server command '$($serverCommand -join ' ')'. Expected sync 1, nosync 3, or sync 3."
        }
        $detectedExperiment = $experimentByConfiguration[$serverConfiguration]
        Write-Host "Detected running experiment: $detectedExperiment"
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
            "exec", "-T", $ClientService, "./load_test",
            $TotalRequests.ToString(),
            $Concurrency.ToString(),
            $Operation
        )

        if ($null -ne $SeatId) {
            $arguments += $SeatId.ToString()
        }

        Write-Host "Saving load-test evidence to: $runDirectory"
        & $docker @composeArgs @arguments 2>&1 |
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
            & $docker @composeArgs logs --since $startedAt --timestamps server 2>&1 |
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
        "log_mode=$detectedLogMode"
        "client_service=$ClientService"
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
