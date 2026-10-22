<#
.SYNOPSIS
    Scans for application residues, uninstalled Steam game remnants, empty software directories,
    and safe-to-clean office/chat caches (WPS, WeChat, QQ, Feishu, DingTalk).
.DESCRIPTION
    Non-invasive read-only scanner.
    Outputs an itemized list with unique IDs, categories, sizes, and risk levels.
    Designed for AI Agent parsing (JSON) and interactive human review.
.PARAMETER MockRoot
    Used for unit testing in an isolated mock sandbox.
.PARAMETER Json
    Outputs structured JSON.
#>
param(
    [string]$MockRoot,
    [switch]$Json
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$residues = @()
$counter = 1

# 1. Detect Steam Residuals
$steamCommonPaths = @()
if ($MockRoot) {
    $steamCommonPaths += Join-Path $MockRoot "Steam\steamapps\common"
} else {
    $drives = Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter } | ForEach-Object { "$($_.DriveLetter):\" }
    foreach ($d in $drives) {
        $p1 = Join-Path $d "STEAM\steamapps\common"
        $p2 = Join-Path $d "SteamLibrary\steamapps\common"
        $p3 = Join-Path $d "Program Files (x86)\Steam\steamapps\common"
        foreach ($p in @($p1, $p2, $p3)) {
            if (Test-Path $p) { $steamCommonPaths += $p }
        }
    }
}

foreach ($scPath in $steamCommonPaths) {
    if (Test-Path $scPath) {
        $folders = Get-ChildItem -LiteralPath $scPath -Directory -ErrorAction SilentlyContinue
        foreach ($f in $folders) {
            $files = Get-ChildItem -LiteralPath $f.FullName -Recurse -File -Force -ErrorAction SilentlyContinue
            $szMB = [math]::Round(($files | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
            # Residual criteria: < 150MB, or 0 files, or no main exe found
            $hasExe = ($files | Where-Object { $_.Extension -eq '.exe' } | Measure-Object).Count -gt 0
            if ($szMB -lt 150 -and (-not $hasExe -or $files.Count -lt 5)) {
                $residues += [PSCustomObject]@{
                    ID = "RES-" + ($counter++).ToString("D3")
                    Category = "Steam Residual"
                    Name = $f.Name
                    Path = $f.FullName
                    SizeMB = $szMB
                    FileCount = $files.Count
                    RiskLevel = "Low"
                    Description = "Uninstalled game remnant (logs/empty config leftovers)"
                }
            }
        }
    }
}

# 2. Detect Common Software Empty or Orphaned Root Directories
$checkRoots = @()
if ($MockRoot) {
    $checkRoots += $MockRoot
} else {
    $drives = Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter } | ForEach-Object { "$($_.DriveLetter):\" }
    $checkRoots += $drives
}

foreach ($r in $checkRoots) {
    if (Test-Path $r) {
        $candidates = Get-ChildItem -LiteralPath $r -Directory -Force -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -match '^(MUMU|_ide|鑻|中国移动|Temp|downloading)$' -or $_.Name -like "*鑻*"
        }
        foreach ($c in $candidates) {
            $files = Get-ChildItem -LiteralPath $c.FullName -Recurse -File -Force -ErrorAction SilentlyContinue
            $szMB = [math]::Round(($files | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
            if ($szMB -lt 10) {
                $residues += [PSCustomObject]@{
                    ID = "RES-" + ($counter++).ToString("D3")
                    Category = "Empty/Corrupt Directory"
                    Name = $c.Name
                    Path = $c.FullName
                    SizeMB = $szMB
                    FileCount = $files.Count
                    RiskLevel = "Low"
                    Description = "Empty or corrupt uninstall residual directory"
                }
            }
        }
    }
}

# 3. Detect Office & Communication Safe Caches (Logs, Crash dumps, Temp download packages)
$cacheTargets = @()
if ($MockRoot) {
    $cacheTargets += @(
        @{ Cat = "WPS Cache"; Name = "WPS AutoBackup/Temp"; Path = (Join-Path $MockRoot "AppData\Kingsoft\backup"); Desc = "WPS temporary document backups" },
        @{ Cat = "WeChat Log"; Name = "WeChat Logs"; Path = (Join-Path $MockRoot "AppData\Tencent\WeChat\log"); Desc = "WeChat client runtime diagnostic logs" },
        @{ Cat = "QQ Cache"; Name = "QQ Crash Dumps"; Path = (Join-Path $MockRoot "AppData\Tencent\QQ\CrashDump"); Desc = "QQ crash dump memory snapshots" },
        @{ Cat = "Lark Log"; Name = "Feishu Crashpad Logs"; Path = (Join-Path $MockRoot "AppData\LarkShell\crashpad"); Desc = "Feishu crashpad logs" }
    )
} else {
    $localApp = $env:LOCALAPPDATA
    $roamApp = $env:APPDATA
    $userProf = $env:USERPROFILE

    $cacheTargets += @(
        @{ Cat = "WPS Cache"; Name = "WPS Local Updates/Downloads"; Path = "$localApp\Kingsoft\wps\download"; Desc = "WPS update installer cache" },
        @{ Cat = "WPS Cache"; Name = "WPS Cloud Temp Cache"; Path = "$roamApp\Kingsoft\office6\data\backup"; Desc = "WPS historical auto-backup snapshots" },
        @{ Cat = "WeChat Cache"; Name = "WeChat Runtime Logs"; Path = "$roamApp\Tencent\WeChat\log"; Desc = "WeChat client diagnostic logs" },
        @{ Cat = "WeChat Cache"; Name = "WeChat Crash Dumps"; Path = "$localApp\Tencent\WeChat\CrashDump"; Desc = "WeChat crash memory snapshots" },
        @{ Cat = "QQ Cache"; Name = "QQ Crash Dumps"; Path = "$localApp\Tencent\QQ\CrashDump"; Desc = "QQ crash dumps" },
        @{ Cat = "Lark Cache"; Name = "Feishu Crashpad Logs"; Path = "$roamApp\LarkShell\crashpad"; Desc = "Feishu/Lark crash diagnostic logs" },
        @{ Cat = "DingTalk Cache"; Name = "DingTalk Client Logs"; Path = "$roamApp\DingTalk\logs"; Desc = "DingTalk diagnostic runtime logs" }
    )
}

foreach ($ct in $cacheTargets) {
    if (Test-Path $ct.Path) {
        $files = Get-ChildItem -LiteralPath $ct.Path -Recurse -File -Force -ErrorAction SilentlyContinue
        $szMB = [math]::Round(($files | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
        if ($szMB -gt 0.1 -or $files.Count -gt 0) {
            $residues += [PSCustomObject]@{
                ID = "RES-" + ($counter++).ToString("D3")
                Category = $ct.Cat
                Name = $ct.Name
                Path = $ct.Path
                SizeMB = $szMB
                FileCount = $files.Count
                RiskLevel = "Low"
                Description = $ct.Desc
            }
        }
    }
}

if ($Json) {
    $residues | ConvertTo-Json -Depth 3
} else {
    Write-Host "`n=== DETECTED APP RESIDUES & SAFE CACHES ===" -ForegroundColor Cyan
    if ($residues.Count -eq 0) {
        Write-Host "No residue or safe cache targets found." -ForegroundColor Green
    } else {
        $residues | Select-Object ID, Category, SizeMB, FileCount, Name, Path | Format-Table -AutoSize
        Write-Host "`nTotal items detected: $($residues.Count)" -ForegroundColor Yellow
        Write-Host "Tip: Use 'clean_selected_residues.ps1 -TargetIds RES-001,RES-002' to clean selected items after user confirmation." -ForegroundColor Gray
    }
}
