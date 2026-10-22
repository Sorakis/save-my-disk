<#
.SYNOPSIS
    Non-invasive, read-only disk audit script for AI Agents and System Administrators.
.DESCRIPTION
    Scans fixed drives, root folders, and key cache hotspots without locking files or burdening I/O.
    Audits 4-Tier hotspots, explicitly reporting 0 MB healthy/purged status for upgrade files ($WINDOWS.~BT/Windows.old).
    Supports structured JSON output for AI Agent parsing (Antigravity, Codex, Claude Code, OpenCode, DeepSeek).
.PARAMETER MockRoot
    Used for unit testing in an isolated mock sandbox.
.PARAMETER Json
    If specified, returns a single JSON object. Otherwise, prints formatted console tables.
#>
param(
    [string]$MockRoot,
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
if ($MockRoot) {
    $report.Volumes += [PSCustomObject]@{
        DriveLetter = "C:"
        Label = "MockSystem"
        TotalGB = 500.0
        UsedGB = 300.0
        FreeGB = 200.0
        UsedPercent = 60.0
    }
} else {
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
}

# 2. Key System Hotspots on C: (Auditing all 4 Tiers)
$cHotspots = @(
    @{ Name = 'Windows 升级历史备份 ($WINDOWS.~BT)'; Path = if ($MockRoot) { Join-Path $MockRoot '$WINDOWS.~BT' } else { 'C:\$WINDOWS.~BT' }; Tier = 1; Recommendation = '大版本升级旧系统残留。稳定后可通过 cleanmgr (磁盘清理->清理系统文件) 清理' },
    @{ Name = 'Windows 历史回退版本 (Windows.old)'; Path = if ($MockRoot) { Join-Path $MockRoot 'Windows.old' } else { 'C:\Windows.old' }; Tier = 1; Recommendation = '跨版本回退文件。稳定后可通过 cleanmgr 清理' },
    @{ Name = 'Windows Update 补丁下载缓存'; Path = if ($MockRoot) { Join-Path $MockRoot 'Windows\SoftwareDistribution\Download' } else { 'C:\Windows\SoftwareDistribution\Download' }; Tier = 1; Recommendation = '历史补丁缓存。可通过 clean_windows_update.ps1 安全清空并自愈重启服务' },
    @{ Name = '用户临时运行缓存 (Temp)'; Path = if ($MockRoot) { Join-Path $MockRoot 'AppData\Local\Temp' } else { "$env:LOCALAPPDATA\Temp" }; Tier = 1; Recommendation = '临时中转文件。可通过 clean_user_temp.ps1 安全清空' },
    @{ Name = 'Windows 休眠文件 (hiberfil.sys)'; Path = if ($MockRoot) { Join-Path $MockRoot 'hiberfil.sys' } else { 'C:\hiberfil.sys' }; Tier = 2; Recommendation = '若不使用休眠功能，可用管理员运行 powercfg -h off 禁用释放' },
    @{ Name = 'Docker/WSL2 虚拟磁盘 (docker_data.vhdx)'; Path = if ($MockRoot) { Join-Path $MockRoot 'Docker\wsl\disk\docker_data.vhdx' } else { "$env:LOCALAPPDATA\Docker\wsl\disk\docker_data.vhdx" }; Tier = 2; Recommendation = '可用 manage_wsl_disk.ps1 压缩回收空洞，或迁移至非系统盘' },
    @{ Name = 'Windows 虚拟内存页面文件 (pagefile.sys)'; Path = if ($MockRoot) { Join-Path $MockRoot 'pagefile.sys' } else { 'C:\pagefile.sys' }; Tier = 4; Recommendation = '系统核心保护红线。严禁手动删除，可在系统设置中转移至非系统盘' }
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
                Tier = $h.Tier
                Name = $h.Name
                Path = $h.Path
                SizeMB = $sizeMB
                SizeGB = [math]::Round(($sizeMB / 1024), 2)
                Status = "可释放 / 待清理"
                Recommendation = $h.Recommendation
            }
        } else {
            # 0 MB or empty directory
            $report.Hotspots += [PSCustomObject]@{
                Tier = $h.Tier
                Name = $h.Name
                Path = $h.Path
                SizeMB = 0
                SizeGB = 0
                Status = "健康 / 无残留 (0 MB)"
                Recommendation = "目录已清空或无冗余文件"
            }
        }
    } else {
        # Path does not exist on disk
        if ($h.Tier -eq 1) {
            $rec = if ($h.Name -like "*升级*" -or $h.Name -like "*Windows.old*") {
                "未检测到历史升级残留（Windows 在升级 10 天后已自动释放，或此前已清理完毕）"
            } else {
                "目录无冗余文件或已被完全清空"
            }
            $report.Hotspots += [PSCustomObject]@{
                Tier = $h.Tier
                Name = $h.Name
                Path = $h.Path
                SizeMB = 0
                SizeGB = 0
                Status = "健康 / 已清理 (0 MB)"
                Recommendation = $rec
            }
        }
    }
}

# 3. Top AppData Subdirectories
$appDataLocal = if ($MockRoot) { Join-Path $MockRoot "AppData\Local" } else { "$env:LOCALAPPDATA" }
$appDataRoaming = if ($MockRoot) { Join-Path $MockRoot "AppData\Roaming" } else { "$env:APPDATA" }

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
$userHome = if ($MockRoot) { Join-Path $MockRoot "UserProfile" } else { $env:USERPROFILE }
if (Test-Path $userHome) {
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
}

if ($Json) {
    $report | ConvertTo-Json -Depth 4
} else {
    Write-Host "`n=== 1. DISK VOLUMES ===" -ForegroundColor Cyan
    $report.Volumes | Format-Table -AutoSize

    Write-Host "=== 2. DETECTED 4-TIER HOTSPOTS ===" -ForegroundColor Yellow
    $report.Hotspots | Select-Object Tier, Status, SizeGB, Name, Recommendation | Format-Table -AutoSize

    Write-Host "=== 3. TOP APPDATA FOLDERS ===" -ForegroundColor Green
    $report.AppDataTop | Select-Object SizeGB, Name, Path | Format-Table -AutoSize

    Write-Host "=== 4. TOP USER PROFILE FOLDERS ===" -ForegroundColor Magenta
    $report.UserHomeTop | Select-Object SizeGB, Name, Path | Format-Table -AutoSize
}
