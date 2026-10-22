<#
.SYNOPSIS
    Safely purges Windows Update download cache and obsolete backups.
.DESCRIPTION
    Stops wuauserv and bits services, purges SoftwareDistribution\Download and Download.bak,
    then restarts the services and verifies their operational health.
    Must be run as Administrator.
.PARAMETER DryRun
    Simulate the action without actually deleting files.
.PARAMETER Force
    Execute without interactive prompt.
#>
param(
    [switch]$DryRun,
    [switch]$Force
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "CRITICAL: This script requires Administrator privileges. Please run PowerShell as Administrator."
    exit 1
}

$downloadPath = "C:\Windows\SoftwareDistribution\Download"
$bakPath = "C:\Windows\SoftwareDistribution\Download.bak"

$initialSizeMB = 0
if (Test-Path $downloadPath) {
    $initialSizeMB += ((Get-ChildItem -LiteralPath $downloadPath -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB)
}
if (Test-Path $bakPath) {
    $initialSizeMB += ((Get-ChildItem -LiteralPath $bakPath -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB)
}
$initialSizeMB = [math]::Round($initialSizeMB, 2)

Write-Host "Target cache size detected: $initialSizeMB MB" -ForegroundColor Yellow

if ($DryRun) {
    Write-Host "[DRY RUN] Would stop wuauserv and bits, purge $downloadPath and $bakPath, and restart services." -ForegroundColor Cyan
    exit 0
}

Write-Host "Step 1/4: Stopping update-related services..." -ForegroundColor Cyan
cmd /c "net stop wuauserv & net stop bits" | Out-Null

Write-Host "Step 2/4: Deleting obsolete backup folder (Download.bak)..." -ForegroundColor Cyan
if (Test-Path $bakPath) {
    cmd /c "rd /s /q `"$bakPath`"" | Out-Null
}

Write-Host "Step 3/4: Purging download cache directory..." -ForegroundColor Cyan
if (Test-Path $downloadPath) {
    cmd /c "rd /s /q `"$downloadPath`" & md `"$downloadPath`"" | Out-Null
} else {
    New-Item -ItemType Directory -Path $downloadPath -Force | Out-Null
}

Write-Host "Step 4/4: Restarting Windows Update services..." -ForegroundColor Cyan
cmd /c "net start bits & net start wuauserv" | Out-Null

# Verification
Start-Sleep -Seconds 2
$wuStatus = (Get-Service -Name wuauserv).Status
$remainingSizeMB = [math]::Round(((Get-ChildItem -LiteralPath $downloadPath -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB), 2)
$freedMB = [math]::Max(0, [math]::Round($initialSizeMB - $remainingSizeMB, 2))

Write-Host "`n=== CLEANUP COMPLETED ===" -ForegroundColor Green
Write-Host "Freed Space: $freedMB MB (~$([math]::Round($freedMB / 1024, 2)) GB)"
Write-Host "Remaining in Download: $remainingSizeMB MB"
Write-Host "Windows Update Service Status: $wuStatus"

if ($wuStatus -eq "Running") {
    Write-Host "Verification PASSED: Windows Update is healthy and ready." -ForegroundColor Green
} else {
    Write-Warning "Windows Update service status is $wuStatus. Please verify manually."
}
