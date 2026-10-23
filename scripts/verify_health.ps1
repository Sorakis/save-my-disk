<#
.SYNOPSIS
    Post-cleanup verification script for AI Agents.
.DESCRIPTION
    Checks disk volume space remaining, delta comparisons, and critical Windows service states.
    Supports generating/refreshing the visual HTML dashboard if -ExportHtml is specified.
#>
param(
    [string]$MockRoot,
    [string]$ManifestPath,
    [switch]$ExportHtml,
    [switch]$Json
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $scriptDir) { $scriptDir = ".\scripts" }

if ($MockRoot) {
    $volumes = @([PSCustomObject]@{ DriveLetter = 'C'; FileSystemLabel = 'MockSystem'; SizeGB = 500.0; FreeGB = 220.0 })
    $wuService = "Running"
    $bitsService = "Running"
} else {
    $volumes = Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter } | Select-Object DriveLetter, FileSystemLabel, @{N='SizeGB';E={[math]::Round($_.Size/1GB,2)}}, @{N='FreeGB';E={[math]::Round($_.SizeRemaining/1GB,2)}}
    $wuService = Get-Service -Name wuauserv -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Status
    $bitsService = Get-Service -Name bits -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Status
}

$dashboardPath = $null
if ($ExportHtml) {
    $exportScript = Join-Path $scriptDir "export_dashboard.ps1"
    if (Test-Path -LiteralPath $exportScript) {
        $extraArgs = @{}
        if ($MockRoot) { $extraArgs['MockRoot'] = $MockRoot }
        if ($ManifestPath) { $extraArgs['ManifestPath'] = $ManifestPath }
        $dashRes = & $exportScript @extraArgs -Json | ConvertFrom-Json
        $dashboardPath = $dashRes.ReportPath
    }
}

$res = [PSCustomObject]@{
    Timestamp = (Get-Date).ToString("s")
    Volumes = $volumes
    Services = [PSCustomObject]@{
        wuauserv = "$wuService"
        bits = "$bitsService"
    }
    DashboardPath = $dashboardPath
}

if ($Json) {
    $res | ConvertTo-Json -Depth 3
} else {
    Write-Host "=== POST-CLEANUP DISK & SERVICE STATUS ===" -ForegroundColor Cyan
    $volumes | Format-Table -AutoSize
    Write-Host "Service States:" -ForegroundColor Yellow
    Write-Host "  Windows Update (wuauserv) : $wuService"
    Write-Host "  BITS                     : $bitsService"
    if ($dashboardPath) {
        Write-Host "Visual Dashboard Refreshed at: $dashboardPath" -ForegroundColor Green
    }
}
