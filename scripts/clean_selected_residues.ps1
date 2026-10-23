<#
.SYNOPSIS
    Selectively purges confirmed application residues, caches, inactive dev artifacts,
    AI model weights, and global package manager caches.
.DESCRIPTION
    Accepts explicit target IDs (SYS, RES, DEV, AI, PKG), direct paths, or parses a Markdown
    manifest file (.save-my-disk/cleanup_manifest.md) where the user has checked boxes like
    '- [x] **[RES-001]' or '- [x] **[AI-001]'.
    Enforces strict path safety checks and project root immunity to prevent deletion of protected directories.
    Runs in DryRun mode unless -Force is specified.
.PARAMETER TargetIds
    Comma-separated list of IDs (e.g. RES-001, DEV-002, AI-001, PKG-001).
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

$targetsToDelete = @()

# 1. Resolve selected items from manifest if -FromManifest is specified
if ($FromManifest -and (Test-Path -LiteralPath $ManifestPath)) {
    $manifestContent = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8
    $pattern = '-\s*\[[xX]\]\s*\*\*\[((?:SYS|RES|DEV|AI|PKG|IM|BRW)-\d+)\]\s*(.+?)\*\*.*?\r?\n\s*\*\s*路径[：:]\s*`([^`]+)`'
    $itemMatches = [regex]::Matches($manifestContent, $pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

    foreach ($m in $itemMatches) {
        $targetsToDelete += [PSCustomObject]@{
            ID = $m.Groups[1].Value
            Name = $m.Groups[2].Value.Trim()
            Path = $m.Groups[3].Value.Trim()
            RiskLevel = "FromManifest"
        }
    }

    if ($targetsToDelete.Count -gt 0) {
        Write-Host "Detected $($targetsToDelete.Count) checked item(s) from manifest: $(($targetsToDelete | ForEach-Object { $_.ID }) -join ', ')" -ForegroundColor Cyan
    } else {
        Write-Warning "No checked items (- [x] **[SYS/RES/DEV/AI/PKG-xxx]) found in manifest file: $ManifestPath"
    }
}

# 2. Resolve manually specified TargetIds from all scanner modules if needed
if ($TargetIds -and $targetsToDelete.Count -eq 0) {
    # 2.1 Check scan_app_residues
    if (Test-Path -LiteralPath "$PSScriptRoot\scan_app_residues.ps1") {
        $tempManifestResolve = if ($MockRoot) { Join-Path $MockRoot ".save-my-disk\temp_resolve.md" } else { Join-Path $env:TEMP "save_my_disk_temp_resolve.md" }
        $scanResidues = & "$PSScriptRoot\scan_app_residues.ps1" -MockRoot $MockRoot -OutputManifest $tempManifestResolve -Json | ConvertFrom-Json | ForEach-Object { $_ }
        foreach ($item in $scanResidues) {
            if ($TargetIds -contains $item.ID -and $item.SizeMB -gt 0) {
                $targetsToDelete += $item
            }
        }
    }

    # 2.2 Check scan_dev_artifacts
    if (Test-Path -LiteralPath "$PSScriptRoot\scan_dev_artifacts.ps1") {
        $scanDev = if ($MockRoot) {
            & "$PSScriptRoot\scan_dev_artifacts.ps1" -MockRoot $MockRoot -Json | ConvertFrom-Json | ForEach-Object { $_ }
        } else {
            & "$PSScriptRoot\scan_dev_artifacts.ps1" -Json | ConvertFrom-Json | ForEach-Object { $_ }
        }
        foreach ($item in $scanDev) {
            if ($TargetIds -contains $item.ID -and $item.SizeMB -gt 0) {
                $targetsToDelete += $item
            }
        }
    }

    # 2.3 Check scan_ai_models
    if (Test-Path -LiteralPath "$PSScriptRoot\scan_ai_models.ps1") {
        $scanAi = if ($MockRoot) {
            & "$PSScriptRoot\scan_ai_models.ps1" -MockRoot $MockRoot -Json | ConvertFrom-Json | ForEach-Object { $_ }
        } else {
            & "$PSScriptRoot\scan_ai_models.ps1" -Json | ConvertFrom-Json | ForEach-Object { $_ }
        }
        foreach ($item in $scanAi) {
            if ($TargetIds -contains $item.ID -and $item.SizeMB -gt 0) {
                $targetsToDelete += $item
            }
        }
    }

    # 2.4 Check scan_package_caches
    if (Test-Path -LiteralPath "$PSScriptRoot\scan_package_caches.ps1") {
        $scanPkg = if ($MockRoot) {
            & "$PSScriptRoot\scan_package_caches.ps1" -MockRoot $MockRoot -Json | ConvertFrom-Json | ForEach-Object { $_ }
        } else {
            & "$PSScriptRoot\scan_package_caches.ps1" -Json | ConvertFrom-Json | ForEach-Object { $_ }
        }
        foreach ($item in $scanPkg) {
            if ($TargetIds -contains $item.ID -and $item.SizeMB -gt 0) {
                $targetsToDelete += $item
            }
        }
    }

    # 2.5 Check scan_im_office_residues
    if (Test-Path -LiteralPath "$PSScriptRoot\scan_im_office_residues.ps1") {
        $scanIm = if ($MockRoot) {
            & "$PSScriptRoot\scan_im_office_residues.ps1" -MockRoot $MockRoot -Json | ConvertFrom-Json | ForEach-Object { $_ }
        } else {
            & "$PSScriptRoot\scan_im_office_residues.ps1" -Json | ConvertFrom-Json | ForEach-Object { $_ }
        }
        foreach ($item in $scanIm) {
            if ($TargetIds -contains $item.ID -and $item.SizeMB -gt 0) {
                $targetsToDelete += $item
            }
        }
    }

    # 2.6 Check scan_browser_system_caches
    if (Test-Path -LiteralPath "$PSScriptRoot\scan_browser_system_caches.ps1") {
        $scanBrw = if ($MockRoot) {
            & "$PSScriptRoot\scan_browser_system_caches.ps1" -MockRoot $MockRoot -Json | ConvertFrom-Json | ForEach-Object { $_ }
        } else {
            & "$PSScriptRoot\scan_browser_system_caches.ps1" -Json | ConvertFrom-Json | ForEach-Object { $_ }
        }
        foreach ($item in $scanBrw) {
            if ($TargetIds -contains $item.ID -and $item.SizeMB -gt 0) {
                $targetsToDelete += $item
            }
        }
    }
}

# 3. Handle manual direct paths
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
    Write-Warning "No valid targets specified to delete. Use -TargetIds (e.g. RES-001, DEV-001, AI-001, PKG-001) or mark items with '- [x]' in $ManifestPath and use -FromManifest."
    exit 0
}

Write-Host "`n=== SELECTED CLEANUP CANDIDATES ===" -ForegroundColor Yellow
$targetsToDelete | Select-Object ID, Name, Path | Format-Table -AutoSize

if (-not $Force) {
    Write-Host "`n[DRY RUN MODE] -Force was not specified. No files were modified." -ForegroundColor Cyan
    Write-Host "To execute deletion after user confirmation, re-run with the -Force switch." -ForegroundColor Gray
    exit 0
}

# 4. Rigorous Security Boundary Checks
$forbiddenPatterns = @(
    "System32", "WinSxS", "Windows\\System",
    "^([a-zA-Z]:\\)?Program Files( \(x86\))?\\?$",
    "\\Desktop\\?$", "\\Documents\\?$",
    "\\miniconda3\\envs", "\\anaconda3\\envs", "\\\.conda\\envs",
    "\\(mini|ana)?conda\d?\\pkgs$",
    "\\(db_storage|nt_db|contact|session)($|\\)",
    "\\(All Users|all_users)($|\\)",
    "\\Backup($|\\)",
    "\\Msg($|\\)",
    "\\Msg3?\.0?\.db",
    "\\User Data\\?$",
    "\\User Data\\(Default|Profile \d+)\\?$",
    "\\Mozilla\\Firefox\\Profiles\\?$",
    "\\Mozilla\\Firefox\\Profiles\\[^\\]+\\?$",
    "\\(Login Data|Cookies|Web Data|History|Bookmarks|IndexedDB|Local Storage|Extensions)($|\\|-|\.)",
    "\\Network\\Cookies"
)

$deletedCount = 0
$freedBytes = 0
$successfullyCleanedIds = @()

foreach ($t in $targetsToDelete) {
    $p = $t.Path
    if (-not (Test-Path -LiteralPath $p)) {
        Write-Host "Skipping (Path not found): $p" -ForegroundColor Gray
        continue
    }

    # Check 4.1: Forbidden system & root paths
    $isForbidden = $false
    foreach ($fp in $forbiddenPatterns) {
        if ($p -match $fp) {
            # Special allowance: Conda Tarballs category performs selective file purge inside pkgs, never deletes pkgs directory
            if ($fp -like "*pkgs*" -and ($t.Category -eq "Conda Tarballs" -or $t.Name -like "*Conda*归档*" -or $t.Name -like "*Conda*Tarball*")) {
                continue
            }
            $isForbidden = $true
            break
        }
    }

    if ($isForbidden) {
        Write-Error "SECURITY BLOCKED: Cannot delete protected path: $p"
        continue
    }

    # Check 4.2: Active project source root immunity & critical marker protection
    $leafName = Split-Path $p -Leaf
    if ($leafName -in @(".git", "package.json", "Cargo.toml", "pyproject.toml", "go.mod", "CMakeLists.txt")) {
        Write-Error "SECURITY BLOCKED: Target is an essential project marker file: $p"
        continue
    }

    if ((Test-Path -LiteralPath (Join-Path $p ".git")) -or
        (Test-Path -LiteralPath (Join-Path $p "package.json")) -or
        (Test-Path -LiteralPath (Join-Path $p "Cargo.toml")) -or
        (Test-Path -LiteralPath (Join-Path $p "pyproject.toml")) -or
        (Test-Path -LiteralPath (Join-Path $p "go.mod"))) {
        Write-Error "SECURITY BLOCKED: Target contains active project root marker: $p"
        continue
    }

    # Check 4.3: Rigid Chat Database & Browser Credential Sentinel (熔断哨兵) - Never delete database files, credentials, or cookies!
    $hasDbOrCredFile = Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Extension -match '^\.(db|sqlite|sqlite3|kvdb|mmkv)$' -or
            $_.Name -match '\.(db|sqlite|sqlite3|kvdb|mmkv)-(wal|shm|journal)$' -or
            $_.Name -like '*.material' -or
            $_.Name -match '^(Login Data|Cookies|Web Data|History|Bookmarks|places\.sqlite|key4\.db|logins\.json)'
        }
    if ($hasDbOrCredFile) {
        Write-Error "SECURITY BLOCKED: Target directory contains chat history database, browser credentials, or cookies! Aborting deletion: $p"
        continue
    }

    Write-Host "Purging target: $p ..." -ForegroundColor Cyan
    try {
        if ($p.TrimEnd('\') -like "*AppData\Local\Temp" -or $p.TrimEnd('\') -like "*\Temp") {
            # Temp directory: purge contents inside Temp without destroying Temp root folder
            $items = Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue
            $sz = ($items | Measure-Object -Property Length -Sum).Sum
            if ($null -eq $sz) { $sz = 0 }
            Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue | ForEach-Object {
                Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
            $freedBytes += $sz
            $deletedCount += $items.Count
        } elseif ($p -like "*SoftwareDistribution\Download*" -and (-not $MockRoot)) {
            # Windows Update download cache: delegate to self-healing script on host
            Write-Host "Target is Windows Update download cache. Delegating to clean_windows_update.ps1..." -ForegroundColor Cyan
            & "$PSScriptRoot\clean_windows_update.ps1" -Force
            if ($t.ID -and $t.ID -ne "MANUAL") {
                $successfullyCleanedIds += $t.ID
            }
            continue
        } elseif ($t.Category -eq "Conda Tarballs" -or $t.Name -like "*Conda*归档*" -or $t.Name -like "*Conda*Tarball*") {
            # Conda Tarballs: delete ONLY compressed .tar.bz2 and .conda archives, never delete pkgs dir or unpacked packages
            Write-Host "Purging Conda compressed archive tarballs (*.tar.bz2, *.conda) in $p..." -ForegroundColor Cyan
            $tarFiles = Get-ChildItem -LiteralPath $p -File -Force -ErrorAction SilentlyContinue | Where-Object {
                $_.Extension -match '^\.(conda|bz2)$' -or $_.Name -like "*.tar.bz2"
            }
            $sz = ($tarFiles | Measure-Object -Property Length -Sum).Sum
            if ($null -eq $sz) { $sz = 0 }
            $tarFiles | ForEach-Object {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
            }
            $freedBytes += $sz
            $deletedCount += $tarFiles.Count
        } elseif (($p -like "*pip\cache*" -or $p -like "*pip\wheels*" -or $t.Name -like "*pip*") -and (-not $MockRoot)) {
            # pip cache: on real host, purge directory contents
            Write-Host "Purging pip cache files..." -ForegroundColor Cyan
            $items = Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue
            $sz = ($items | Measure-Object -Property Length -Sum).Sum
            if ($null -eq $sz) { $sz = 0 }
            Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue | ForEach-Object {
                Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
            $freedBytes += $sz
            $deletedCount += $items.Count
        } elseif (($p -like "*npm-cache*" -or $p -like "*\.npm*" -or $t.Name -like "*npm*") -and (-not $MockRoot)) {
            # npm cache: purge directory contents
            Write-Host "Purging npm cache files..." -ForegroundColor Cyan
            $items = Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue
            $sz = ($items | Measure-Object -Property Length -Sum).Sum
            if ($null -eq $sz) { $sz = 0 }
            Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue | ForEach-Object {
                Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
            $freedBytes += $sz
            $deletedCount += $items.Count
        } elseif ($t.Category -like "*Inactive Files*" -or $t.Name -like "*沉睡历史*") {
            # Inactive received documents (> 90 days): selectively purge old files without destroying recent files or folder structure
            Write-Host "Selectively purging inactive files (> 90 days) in $p..." -ForegroundColor Cyan
            $cutoff = (Get-Date).AddDays(-90)
            $oldFiles = Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object {
                $_.LastWriteTime -lt $cutoff
            }
            $sz = ($oldFiles | Measure-Object -Property Length -Sum).Sum
            if ($null -eq $sz) { $sz = 0 }
            $oldFiles | ForEach-Object {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
            }
            $freedBytes += $sz
            $deletedCount += $oldFiles.Count
        } elseif ($t.ID -like "BRW-*" -or $t.Category -like "*Browser*" -or $t.Category -like "*Shader*" -or $t.Category -like "*Crash*" -or $p -like "*Code Cache*" -or $p -like "*GPUCache*" -or $p -like "*DXCache*" -or $p -like "*D3DSCache*" -or $p -like "*CrashDumps*" -or $p -like "*cache2*" -or $p -like "*DawnCache*" -or $p -like "*startupCache*") {
            # Browser caches, GPU shader caches, and crash dumps: purge container contents with graceful lock skipping
            Write-Host "Purging browser / shader cache files in $p (preserving container)..." -ForegroundColor Cyan
            $items = Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue
            $sz = ($items | Measure-Object -Property Length -Sum).Sum
            if ($null -eq $sz) { $sz = 0 }
            Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue | ForEach-Object {
                Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
            $freedBytes += $sz
            $deletedCount += $items.Count
        } else {
            # Standard directory or file target
            $items = Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue
            $sz = ($items | Measure-Object -Property Length -Sum).Sum
            if ($null -eq $sz) { $sz = 0 }
            Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop
            $freedBytes += $sz
            $deletedCount += $items.Count
        }

        if ($t.ID -and $t.ID -ne "MANUAL") {
            $successfullyCleanedIds += $t.ID
        }
        Write-Host "Successfully removed: $p" -ForegroundColor Green
    } catch {
        Write-Warning "Could not delete $($p): $($_.Exception.Message)"
    }
}

# Update manifest on disk if available
if ((Test-Path -LiteralPath $ManifestPath) -and $successfullyCleanedIds.Count -gt 0) {
    $content = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8
    foreach ($cid in $successfullyCleanedIds) {
        $content = [regex]::Replace($content, "-\s*\[[ xX]\]\s*\*\*\[$cid\]", "- [x] ~~**[$cid]**~~ *(已成功清理)*")
    }
    [System.IO.File]::WriteAllText($ManifestPath, $content, (New-Object System.Text.UTF8Encoding($true)))
    Write-Host "Manifest file updated at $ManifestPath" -ForegroundColor Cyan
}

$freedMB = [math]::Round($freedBytes / 1MB, 2)
Write-Host "`n=== RESIDUES CLEANUP COMPLETED ===" -ForegroundColor Green
Write-Host "Cleaned: $deletedCount files"
Write-Host "Freed Space: $freedMB MB (~$([math]::Round($freedMB / 1024, 2)) GB)"
