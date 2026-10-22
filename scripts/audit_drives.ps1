<#
.SYNOPSIS
    Non-invasive, read-only disk audit script for AI Agents and System Administrators.
.DESCRIPTION
    Scans fixed drives, root folders, and key cache hotspots without locking files or burdening I/O.
    Supports structured JSON output for AI Agent parsing (Antigravity, Codex, Claude Code, OpenCode, DeepSeek).
.PARAMETER Json
    If specified, returns a single JSON object. Otherwise, prints formatted console tables.
#>
param(
    [switch]$Json
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$report = [PSCustomObject]@{
    Timestamp = (Get-Date).ToString("s")
    Volumes = @()
    Hotspots = @()
    AppDataTop = @()
    UserHomeTop = @()
}

# 1. Volume information
$volumes = Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter }
foreach ($v in $volumes) {
    $totalGB = [math]::Round($v.Size / 1GB, 2)
    $freeGB = [math]::Round($v.SizeRemaining / 1GB, 2)
    $usedGB = [math]::Round(($v.Size - $v.SizeRemaining) / 1GB, 2)
    $usedPercent = if ($totalGB -gt 0) { [math]::Round(($usedGB / $totalGB) * 100, 1) } else { 0 }

    $report.Volumes += [PSCustomObject]@{
        DriveLetter = "$($v.DriveLetter):"
        Label = $v.FileSystemLabel
        TotalGB = $totalGB
        UsedGB = $usedGB
        FreeGB = $freeGB
        UsedPercent = $usedPercent
    }
}

# 2. Key System Hotspots on C:
$cHotspots = @(
    @{ Name = "Windows Upgrade Residual (`$WINDOWS.~BT)"; Path = "C:\`$WINDOWS.~BT"; Tier = 1; Recommendation = "Safe to delete (via cleanmgr/cmd) if current OS is stable" },
    @{ Name = "Windows Update Download Cache"; Path = "C:\Windows\SoftwareDistribution\Download"; Tier = 1; Recommendation = "Safe to purge after stopping wuauserv" },
    @{ Name = "Windows Update Download.bak Backup"; Path = "C:\Windows\SoftwareDistribution\Download.bak"; Tier = 1; Recommendation = "Obsolete backup folder; safe to delete immediately" },
    @{ Name = "Windows Hibernation File (hiberfil.sys)"; Path = "C:\hiberfil.sys"; Tier = 2; Recommendation = "Can disable via 'powercfg -h off' if hibernate unused" },
    @{ Name = "Windows Paging File (pagefile.sys)"; Path = "C:\pagefile.sys"; Tier = 4; Recommendation = "Do not manually delete; can migrate to non-system drive" },
    @{ Name = "User Temp Directory"; Path = "$env:LOCALAPPDATA\Temp"; Tier = 1; Recommendation = "Safe to empty" },
    @{ Name = "Docker Virtual Disk (docker_data.vhdx)"; Path = "$env:LOCALAPPDATA\Docker\wsl\disk\docker_data.vhdx"; Tier = 2; Recommendation = "Migrate to secondary drive or prune unneeded images" }
)

foreach ($h in $cHotspots) {
    if (Test-Path -LiteralPath $h.Path) {
        $item = Get-Item -LiteralPath $h.Path -Force -ErrorAction SilentlyContinue
        $sizeMB = 0
        if ($item.PSIsContainer) {
            $sizeMB = [math]::Round(((Get-ChildItem -LiteralPath $h.Path -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB), 2)
        } else {
            $sizeMB = [math]::Round(($item.Length / 1MB), 2)
        }

        if ($sizeMB -gt 0) {
            $report.Hotspots += [PSCustomObject]@{
                Name = $h.Name
                Path = $h.Path
                SizeMB = $sizeMB
                SizeGB = [math]::Round(($sizeMB / 1024), 2)
                Tier = $h.Tier
                Recommendation = $h.Recommendation
            }
        }
    }
}

# 3. Top AppData Subdirectories
$appDataLocal = "$env:LOCALAPPDATA"
$appDataRoaming = "$env:APPDATA"

$appDataDirs = @()
if (Test-Path $appDataLocal) { $appDataDirs += Get-ChildItem -LiteralPath $appDataLocal -Directory -ErrorAction SilentlyContinue }
if (Test-Path $appDataRoaming) { $appDataDirs += Get-ChildItem -LiteralPath $appDataRoaming -Directory -ErrorAction SilentlyContinue }

$appDataResults = foreach ($d in $appDataDirs) {
    $sz = (Get-ChildItem -LiteralPath $d.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    [PSCustomObject]@{
        Name = "$($d.Parent.Name)\$($d.Name)"
        Path = $d.FullName
        SizeMB = [math]::Round(($sz / 1MB), 2)
        SizeGB = [math]::Round(($sz / 1GB), 2)
    }
}
$report.AppDataTop = $appDataResults | Sort-Object -Property SizeMB -Descending | Select-Object -First 10

# 4. Top User Home Subdirectories
$userHome = $env:USERPROFILE
$userDirs = Get-ChildItem -LiteralPath $userHome -Force -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer -and ($_.Attributes -notmatch 'ReparsePoint') }
$userResults = foreach ($ud in $userDirs) {
    $sz = (Get-ChildItem -LiteralPath $ud.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    [PSCustomObject]@{
        Name = $ud.Name
        Path = $ud.FullName
        SizeMB = [math]::Round(($sz / 1MB), 2)
        SizeGB = [math]::Round(($sz / 1GB), 2)
    }
}
$report.UserHomeTop = $userResults | Sort-Object -Property SizeMB -Descending | Select-Object -First 10

if ($Json) {
    $report | ConvertTo-Json -Depth 4
} else {
    Write-Host "`n=== 1. DISK VOLUMES ===" -ForegroundColor Cyan
    $report.Volumes | Format-Table -AutoSize

    Write-Host "=== 2. DETECTED HOTSPOTS ===" -ForegroundColor Yellow
    $report.Hotspots | Select-Object Tier, SizeGB, Name, Recommendation | Format-Table -AutoSize

    Write-Host "=== 3. TOP APPDATA FOLDERS ===" -ForegroundColor Green
    $report.AppDataTop | Select-Object SizeGB, Name, Path | Format-Table -AutoSize

    Write-Host "=== 4. TOP USER PROFILE FOLDERS ===" -ForegroundColor Magenta
    $report.UserHomeTop | Select-Object SizeGB, Name, Path | Format-Table -AutoSize
}
