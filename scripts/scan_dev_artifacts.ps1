<#
.SYNOPSIS
    Scans for inactive/zombie developer build artifacts (node_modules, target, .vs, build).
.DESCRIPTION
    Non-invasive scanner.
    Analyzes project directories and filters only those where all source files have been
    untouched for at least $DaysInactive (default: 60 days).
    Active projects are strictly preserved!
.PARAMETER ScanPath
    Path to scan for development projects (e.g. workspace or projects root).
.PARAMETER MockRoot
    Used for unit testing in an isolated mock sandbox.
.PARAMETER DaysInactive
    Minimum number of days without code changes to qualify as an inactive/zombie project. Default is 60.
.PARAMETER OutputManifest
    If specified, appends/writes findings to the cleanup_manifest.md.
.PARAMETER Json
    Outputs structured JSON.
#>
param(
    [string]$ScanPath,
    [string]$MockRoot,
    [int]$DaysInactive = 60,
    [string]$OutputManifest,
    [switch]$Json
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$targetRoots = @()

if ($MockRoot) {
    $targetRoots += Join-Path $MockRoot "Projects"
} elseif ($ScanPath) {
    if (Test-Path -LiteralPath $ScanPath) {
        $targetRoots += $ScanPath
    }
} else {
    # Default search locations: User Desktop and Documents
    $userDesktop = [Environment]::GetFolderPath("Desktop")
    $userDocs = [Environment]::GetFolderPath("MyDocuments")
    foreach ($p in @($userDesktop, $userDocs)) {
        if (Test-Path $p) { $targetRoots += $p }
    }
}

$artifactsFound = @()
$counter = 1
$cutoffDate = (Get-Date).AddDays(-$DaysInactive)

# Artifact folder names to look for
$buildFolderNames = @('node_modules', 'target', '.vs', 'build', '.gradle', '__pycache__', '.pytest_cache')

foreach ($root in $targetRoots) {
    if (-not (Test-Path -LiteralPath $root)) { continue }

    # Find candidate build folders up to 4 directory levels deep
    $candidateDirs = Get-ChildItem -LiteralPath $root -Directory -Recurse -Depth 4 -Force -ErrorAction SilentlyContinue | Where-Object {
        $buildFolderNames -contains $_.Name -or $_.Name -like "cmake-build-*"
    }

    foreach ($bDir in $candidateDirs) {
        $projDir = $bDir.Parent
        if (-not $projDir) { continue }

        # Check project activity by inspecting source files OUTSIDE the build directory
        $srcFiles = Get-ChildItem -LiteralPath $projDir.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object {
            $_.FullName -notlike "$($bDir.FullName)*" -and $_.Extension -match '\.(rs|js|ts|jsx|tsx|py|cpp|c|h|hpp|java|kt|go|cs|toml|json)$'
        }

        # Find latest modification among source files
        $latestSrcDate = [DateTime]::MinValue
        if ($srcFiles -and $srcFiles.Count -gt 0) {
            $latestSrcDate = ($srcFiles | Measure-Object -Property LastWriteTime -Maximum).Maximum
        } else {
            $latestSrcDate = $projDir.LastWriteTime
        }

        # Only qualify if project is inactive
        if ($latestSrcDate -lt $cutoffDate) {
            $daysSilent = [math]::Round(((Get-Date) - $latestSrcDate).TotalDays, 0)
            $bFiles = Get-ChildItem -LiteralPath $bDir.FullName -Recurse -File -Force -ErrorAction SilentlyContinue
            $szMB = [math]::Round(($bFiles | Measure-Object -Property Length -Sum).Sum / 1MB, 2)

            if ($szMB -gt 5) {
                $artifactsFound += [PSCustomObject]@{
                    ID = "DEV-" + ($counter++).ToString("D3")
                    Project = $projDir.Name
                    ArtifactType = $bDir.Name
                    Path = $bDir.FullName
                    SizeMB = $szMB
                    FileCount = $bFiles.Count
                    DaysInactive = $daysSilent
                    LastActive = $latestSrcDate.ToString("yyyy-MM-dd")
                    Description = "项目已沉睡 $daysSilent 天未修改代码。清理构建产物不会丢失任何源码，随时可通过构建命令重新生成。"
                }
            }
        }
    }
}

# If manifest output requested, append to it
if ($OutputManifest -and (Test-Path $OutputManifest)) {
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## 🟡 沉睡工程构建产物 (Tier 2: 长期未修改工程)")
    [void]$sb.AppendLine("")
    if ($artifactsFound.Count -eq 0) {
        [void]$sb.AppendLine("*未发现超过 $DaysInactive 天未修改的沉睡构建产物。*")
    } else {
        foreach ($art in $artifactsFound) {
            [void]$sb.AppendLine("- [ ] **[" + $art.ID + "] " + $art.Project + " -> " + $art.ArtifactType + "** 🟡 【沉睡 " + $art.DaysInactive + " 天】")
            [void]$sb.AppendLine('  * 路径：`' + $art.Path + '`')
            [void]$sb.AppendLine("  * 大小：" + $art.SizeMB + " MB (" + $art.FileCount + " 个文件)")
            [void]$sb.AppendLine("  * 说明：" + $art.Description)
            [void]$sb.AppendLine("")
        }
    }
    [System.IO.File]::AppendAllText($OutputManifest, $sb.ToString(), [System.Text.Encoding]::UTF8)
}

if ($Json) {
    $artifactsFound | ConvertTo-Json -Depth 3
} else {
    Write-Host "`n=== DETECTED INACTIVE DEV BUILD ARTIFACTS (> $DaysInactive DAYS) ===" -ForegroundColor Cyan
    if ($artifactsFound.Count -eq 0) {
        Write-Host "No zombie build artifacts found (all projects are active within $DaysInactive days)." -ForegroundColor Green
    } else {
        $artifactsFound | Select-Object ID, Project, ArtifactType, DaysInactive, SizeMB, Path | Format-Table -AutoSize
        Write-Host "Tip: Source code is 100% safe. Re-building project regenerates these artifacts anytime." -ForegroundColor Gray
    }
}
