<#
.SYNOPSIS
    Selectively purges confirmed application residues and caches.
.DESCRIPTION
    Requires explicit target IDs or paths.
    Enforces path safety checks to prevent deletion of protected directories.
    Runs in DryRun mode unless -Force is specified.
.PARAMETER TargetIds
    Comma-separated list of IDs from scan_app_residues.ps1 (e.g. RES-001,RES-003).
.PARAMETER TargetPaths
    Direct paths to delete.
.PARAMETER MockRoot
    Used for unit testing in an isolated mock sandbox.
.PARAMETER Force
    Must be explicitly specified to actually delete files.
#>
param(
    [string[]]$TargetIds,
    [string[]]$TargetPaths,
    [string]$MockRoot,
    [switch]$Force
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# First run scan to resolve IDs if TargetIds are provided
$targetsToDelete = @()

if ($TargetIds) {
    $scanCmd = if ($MockRoot) {
        & "$PSScriptRoot\scan_app_residues.ps1" -MockRoot $MockRoot -Json | ConvertFrom-Json
    } else {
        & "$PSScriptRoot\scan_app_residues.ps1" -Json | ConvertFrom-Json
    }

    foreach ($item in $scanCmd) {
        if ($TargetIds -contains $item.ID) {
            $targetsToDelete += $item
        }
    }
}

if ($TargetPaths) {
    foreach ($p in $TargetPaths) {
        $targetsToDelete += [PSCustomObject]@{
            ID = "MANUAL"
            Name = Split-Path $p -Leaf
            Path = $p
            RiskLevel = "Manual"
        }
    }
}

if ($targetsToDelete.Count -eq 0) {
    Write-Warning "No valid targets specified to delete. Use -TargetIds (e.g. RES-001) or -TargetPaths."
    exit 0
}

Write-Host "`n=== SELECTED CLEANUP CANDIDATES ===" -ForegroundColor Yellow
$targetsToDelete | Select-Object ID, Name, Path | Format-Table -AutoSize

if (-not $Force) {
    Write-Host "`n[DRY RUN MODE] -Force was not specified. No files were modified." -ForegroundColor Cyan
    Write-Host "To execute deletion after user confirmation, re-run with the -Force switch." -ForegroundColor Gray
    exit 0
}

# Safety boundary check
$forbiddenPatterns = @("System32", "WinSxS", "Windows\System", "Desktop", "Documents", "Program Files$")

$deletedCount = 0
$freedBytes = 0

foreach ($t in $targetsToDelete) {
    $p = $t.Path
    if (-not (Test-Path -LiteralPath $p)) {
        Write-Host "Skipping (Path not found): $p" -ForegroundColor Gray
        continue
    }

    # Safety check: ensure not forbidden
    $isForbidden = $false
    foreach ($fp in $forbiddenPatterns) {
        if ($p -match [regex]::Escape($fp)) {
            $isForbidden = $true
            break
        }
    }

    if ($isForbidden) {
        Write-Error "SECURITY BLOCKED: Cannot delete protected path: $p"
        continue
    }

    Write-Host "Purging target: $p ..." -ForegroundColor Cyan
    try {
        $items = Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue
        $sz = ($items | Measure-Object -Property Length -Sum).Sum
        Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop
        $freedBytes += $sz
        $deletedCount += $items.Count
        Write-Host "Successfully removed: $p" -ForegroundColor Green
    } catch {
        Write-Warning "Could not delete $($p): $($_.Exception.Message)"
    }
}

$freedMB = [math]::Round($freedBytes / 1MB, 2)
Write-Host "`n=== RESIDUES CLEANUP COMPLETED ===" -ForegroundColor Green
Write-Host "Cleaned: $deletedCount files"
Write-Host "Freed Space: $freedMB MB (~$([math]::Round($freedMB / 1024, 2)) GB)"
