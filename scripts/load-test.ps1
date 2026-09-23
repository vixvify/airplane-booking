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

    [string]$PodName = "airplane-reservation",
    [string]$ContainerName = "client-1",
    [string]$ResultsDirectory
)

$ErrorActionPreference = "Stop"
$Operation = $Operation.ToUpperInvariant()
if ([string]::IsNullOrWhiteSpace($ResultsDirectory)) {
    $ResultsDirectory = Join-Path $PSScriptRoot "..\results"
}
$ResultsDirectory = [System.IO.Path]::GetFullPath($ResultsDirectory)
New-Item -ItemType Directory -Force -Path $ResultsDirectory | Out-Null

$timestamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$runId = [Guid]::NewGuid().ToString("N").Substring(0, 8)
$runDirectory = Join-Path $ResultsDirectory "load-$timestamp-$runId"
New-Item -ItemType Directory -Path $runDirectory | Out-Null

$resultFile = Join-Path $runDirectory "load-test.txt"
$serverLogFile = Join-Path $runDirectory "server-log.txt"
$summaryFile = Join-Path $runDirectory "summary.txt"
$startedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffffffZ")
$loadExitCode = 1
$serverLogExitCode = 1
$failure = $null
$kubectl = $null

try {
    $kubectlCommand = Get-Command kubectl -ErrorAction Stop
    $kubectl = $kubectlCommand.Source

    $podStatus = & $kubectl get pod $PodName 2>&1
    if ($LASTEXITCODE -ne 0) {
        $podStatus | Set-Content -Path $resultFile -Encoding UTF8
        $failure = "Cannot access pod '$PodName'."
    }
    else {
        $arguments = @(
            "exec", $PodName,
            "-c", $ContainerName,
            "--", "./load_test",
            $TotalRequests.ToString(),
            $Concurrency.ToString(),
            $Operation
        )

        if ($null -ne $SeatId) {
            $arguments += $SeatId.ToString()
        }

        Write-Host "Saving load-test evidence to: $runDirectory"
        & $kubectl @arguments 2>&1 |
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
        if ($null -ne $kubectl) {
            & $kubectl logs $PodName -c server "--since-time=$startedAt" 2>&1 |
                Set-Content -Path $serverLogFile -Encoding UTF8
            $serverLogExitCode = $LASTEXITCODE
        }
        else {
            "kubectl was not found." |
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
        "pod=$PodName"
        "container=$ContainerName"
        "total_requests=$TotalRequests"
        "concurrency=$Concurrency"
        "operation=$Operation"
        "seat_id=$seatDescription"
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
