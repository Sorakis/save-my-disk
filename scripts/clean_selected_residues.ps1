<#
.SYNOPSIS
    Selectively purges confirmed application residues and caches.
.DESCRIPTION
    Accepts explicit target IDs, direct paths, or parses a Markdown manifest file (.save-my-disk/cleanup_manifest.md)
    where the user has checked boxes like '- [x] **[RES-001]'.
    Enforces path safety checks to prevent deletion of protected directories.
    Runs in DryRun mode unless -Force is specified.
.PARAMETER TargetIds
    Comma-separated list of IDs from scan_app_residues.ps1 (e.g. RES-001,RES-003).
.PARAMETER FromManifest
    If specified, reads the manifest file and cleans all items marked with '- [x]'.
.PARAMETER ManifestPath
    Path to cleanup_manifest.md. Defaults to '.save-my-disk/cleanup_manifest.md'.
.PARAMETER TargetPaths
    Direct paths to delete.
.PARAMETER MockRoot
    Used for unit testing in an isolated mock sandbox.
.PARAMETER Force
    Must be explicitly specified to actually execute physical deletion.
#>
param(
    [string[]]$TargetIds,
    [switch]$FromManifest,
    [string]$ManifestPath,
    [string[]]$TargetPaths,
    [string]$MockRoot,
    [switch]$Force
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$defaultManifest = if ($MockRoot) {
    Join-Path $MockRoot ".save-my-disk\cleanup_manifest.md"
} else {
    Join-Path (Split-Path $PSScriptRoot -Parent) ".save-my-disk\cleanup_manifest.md"
}

if (-not $ManifestPath) {
    $ManifestPath = $defaultManifest
}

# Resolve selected IDs from manifest if -FromManifest is specified
if ($FromManifest -and (Test-Path $ManifestPath)) {
    $manifestContent = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8
    $matches = [regex]::Matches($manifestContent, '-\s*\[[xX]\]\s*\*\*\[(RES-\d+)\]')
    $manifestIds = foreach ($m in $matches) { $m.Groups[1].Value }
    if ($manifestIds.Count -gt 0) {
        Write-Host "Detected $($manifestIds.Count) checked item(s) from manifest: $($manifestIds -join ', ')" -ForegroundColor Cyan
        $TargetIds = @($TargetIds) + @($manifestIds)
    } else {
        Write-Warning "No checked items (- [x] **[RES-xxx]) found in manifest file: $ManifestPath"
    }
}

$targetsToDelete = @()

if ($TargetIds) {
    $scanCmd = if ($MockRoot) {
        & "$PSScriptRoot\scan_app_residues.ps1" -MockRoot $MockRoot -OutputManifest (Join-Path $MockRoot ".save-my-disk\temp_manifest.md") -Json | ConvertFrom-Json
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
    Write-Warning "No valid targets specified to delete. Use -TargetIds (e.g. RES-001) or mark items with '- [x]' in $ManifestPath and use -FromManifest."
    exit 0
}

Write-Host "`n=== SELECTED CLEANUP CANDIDATES ===" -ForegroundColor Yellow
$targetsToDelete | Select-Object ID, Name, Path, SizeMB | Format-Table -AutoSize

if (-not $Force) {
    Write-Host "`n[DRY RUN MODE] -Force was not specified. No files were modified." -ForegroundColor Cyan
    Write-Host "To execute deletion after user confirmation, re-run with the -Force switch." -ForegroundColor Gray
    exit 0
}

# Safety boundary check
$forbiddenPatterns = @("System32", "WinSxS", "Windows\System", "Desktop", "Documents", "Program Files$")

$deletedCount = 0
$freedBytes = 0
$successfullyCleanedIds = @()

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
        if ($t.ID -and $t.ID -ne "MANUAL") {
            $successfullyCleanedIds += $t.ID
        }
        Write-Host "Successfully removed: $p" -ForegroundColor Green
    } catch {
        Write-Warning "Could not delete $($p): $($_.Exception.Message)"
    }
}

# Update manifest on disk if available
if ((Test-Path $ManifestPath) -and $successfullyCleanedIds.Count -gt 0) {
    $content = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8
    foreach ($cid in $successfullyCleanedIds) {
        # Replace '- [ ] **[RES-xxx]' or '- [x] **[RES-xxx]' with '- [x] ~~**[RES-xxx]**~~ *(已清理)*'
        $content = [regex]::Replace($content, "-\s*\[[ xX]\]\s*\*\*\[$cid\]", "- [x] ~~**[$cid]**~~ *(已成功清理)*")
    }
    [System.IO.File]::WriteAllText($ManifestPath, $content, [System.Text.Encoding]::UTF8)
    Write-Host "Manifest file updated at $ManifestPath" -ForegroundColor Cyan
}

$freedMB = [math]::Round($freedBytes / 1MB, 2)
Write-Host "`n=== RESIDUES CLEANUP COMPLETED ===" -ForegroundColor Green
Write-Host "Cleaned: $deletedCount files"
Write-Host "Freed Space: $freedMB MB (~$([math]::Round($freedMB / 1024, 2)) GB)"
