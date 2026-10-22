<#
.SYNOPSIS
    Cleans user temporary files ($env:LOCALAPPDATA\Temp) and optionally empties Recycle Bin.
.DESCRIPTION
    Safely iterates through temp files, skips files currently in use by running processes,
    and reports exact space recovered.
.PARAMETER IncludeRecycleBin
    If set, empties the Windows Recycle Bin without prompt.
.PARAMETER DryRun
    Simulate the cleanup and report potential space savings.
#>
param(
    [switch]$IncludeRecycleBin,
    [switch]$DryRun
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$tempPath = "$env:LOCALAPPDATA\Temp"
if (-not (Test-Path $tempPath)) {
    Write-Host "Temp directory not found: $tempPath"
    exit 0
}

$tempFiles = Get-ChildItem -LiteralPath $tempPath -Force -Recurse -File -ErrorAction SilentlyContinue
$totalSizeMB = [math]::Round(($tempFiles | Measure-Object -Property Length -Sum).Sum / 1MB, 2)

Write-Host "Found $($tempFiles.Count) temporary files totaling $totalSizeMB MB in $tempPath" -ForegroundColor Yellow

if ($DryRun) {
    Write-Host "[DRY RUN] Would attempt to remove unlocked files in Temp directory." -ForegroundColor Cyan
    if ($IncludeRecycleBin) {
        Write-Host "[DRY RUN] Would empty Recycle Bin." -ForegroundColor Cyan
    }
    exit 0
}

Write-Host "Cleaning Temp directory (in-use files will be safely skipped)..." -ForegroundColor Cyan
$deletedCount = 0
$deletedBytes = 0

Get-ChildItem -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        if ($_.PSIsContainer) {
            $folderFiles = Get-ChildItem -LiteralPath $_.FullName -Recurse -File -Force -ErrorAction SilentlyContinue
            $sz = ($folderFiles | Measure-Object -Property Length -Sum).Sum
            Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
            $deletedBytes += $sz
            $deletedCount += $folderFiles.Count
        } else {
            $sz = $_.Length
            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
            $deletedBytes += $sz
            $deletedCount++
        }
    } catch {
        # File is locked by active process, safely ignore
    }
}

if ($IncludeRecycleBin) {
    Write-Host "Emptying Recycle Bin..." -ForegroundColor Cyan
    try {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        Write-Host "Recycle Bin emptied." -ForegroundColor Green
    } catch {
        Write-Warning "Failed to empty Recycle Bin: $($_.Exception.Message)"
    }
}

$freedMB = [math]::Round($deletedBytes / 1MB, 2)
Write-Host "`n=== TEMP CLEANUP COMPLETED ===" -ForegroundColor Green
Write-Host "Freed Space: $freedMB MB (~$([math]::Round($freedMB / 1024, 2)) GB)"
Write-Host "Cleaned $deletedCount files."
