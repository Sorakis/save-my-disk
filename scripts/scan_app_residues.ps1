<#
.SYNOPSIS
    Scans for 4-Tier disk candidates: Tier 1 system/update items (including absent status reporting for cleanmgr files),
    Tier 2 developer/GPU driver caches, and Tier 3 uninstalled app residues and diagnostic logs.
.DESCRIPTION
    Non-invasive read-only scanner for save-my-disk (v0.3.1).
    Outputs an itemized list with unique IDs (SYS-xxx, RES-xxx), categories, tiers, sizes, and tradeoff analysis.
    Generates a persistent Markdown manifest (.save-my-disk/cleanup_manifest.md) organized by 4 canonical tiers.
.PARAMETER MockRoot
    Used for unit testing in an isolated mock sandbox.
.PARAMETER OutputManifest
    File path to write the Markdown manifest to. Defaults to '.save-my-disk/cleanup_manifest.md'.
.PARAMETER Json
    Outputs structured JSON.
#>
param(
    [string]$MockRoot,
    [string]$OutputManifest,
    [switch]$Json
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$residues = @()
$sysCounter = 1
$resCounter = 1

# =========================================================
# 🟢 TIER 1: System & Windows Update Caches (Zero-Risk)
# =========================================================

# 1.1 Windows Upgrade Residuals ($WINDOWS.~BT / Windows.old)
$btPath = if ($MockRoot) { Join-Path $MockRoot '$WINDOWS.~BT' } else { 'C:\$WINDOWS.~BT' }
$oldPath = if ($MockRoot) { Join-Path $MockRoot 'Windows.old' } else { 'C:\Windows.old' }

$hasBt = Test-Path -LiteralPath $btPath
$hasOld = Test-Path -LiteralPath $oldPath

if ($hasBt -or $hasOld) {
    $upgradePath = if ($hasBt) { $btPath } else { $oldPath }
    $uFiles = Get-ChildItem -LiteralPath $upgradePath -Recurse -File -Force -ErrorAction SilentlyContinue
    $uSizeMB = [math]::Round(($uFiles | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
    if ($uSizeMB -gt 50 -or $MockRoot) {
        $residues += [PSCustomObject]@{
            ID = 'SYS-' + ($sysCounter++).ToString('D3')
            Tier = 1
            Category = 'Windows Upgrade Residual'
            Name = 'Windows 大版本升级备份 ($WINDOWS.~BT / Windows.old)'
            Path = $upgradePath
            SizeMB = $uSizeMB
            FileCount = $uFiles.Count
            RiskLevel = 'Zero'
            Description = '大版本系统升级留存的历史备份包。若当前系统稳定，可放心删除（可通过 cleanmgr 磁盘清理或管理员权限清理）。'
        }
    }
} else {
    # Explicitly report 0 MB status so users know it was checked!
    $residues += [PSCustomObject]@{
        ID = 'SYS-000'
        Tier = 1
        Category = 'Windows Upgrade Residual'
        Name = 'Windows 大版本升级备份 ($WINDOWS.~BT / Windows.old) [已清理/健康]'
        Path = $btPath
        SizeMB = 0
        FileCount = 0
        RiskLevel = 'Healthy'
        Description = '未检测到历史升级冗余包（状态健康：Windows 在升级 10 天后已自动释放空间，或此前已通过 cleanmgr 完成清理）。'
    }
}

# 1.2 Windows Update Download Cache
$wuDownloadPath = if ($MockRoot) { Join-Path $MockRoot 'Windows\SoftwareDistribution\Download' } else { 'C:\Windows\SoftwareDistribution\Download' }
if (Test-Path -LiteralPath $wuDownloadPath) {
    $wuFiles = Get-ChildItem -LiteralPath $wuDownloadPath -Recurse -File -Force -ErrorAction SilentlyContinue
    $wuSizeMB = [math]::Round(($wuFiles | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
    if ($wuSizeMB -gt 50 -or $MockRoot) {
        $residues += [PSCustomObject]@{
            ID = 'SYS-' + ($sysCounter++).ToString('D3')
            Tier = 1
            Category = 'Windows Update Cache'
            Name = 'Windows Update 补丁下载缓存'
            Path = $wuDownloadPath
            SizeMB = $wuSizeMB
            FileCount = $wuFiles.Count
            RiskLevel = 'Zero'
            Description = '系统更新安装成功后留存的累积补丁源文件。停止更新服务后可安全清空，随时可通过 clean_windows_update.ps1 清理并自动重启服务。'
        }
    }
}

# 1.3 User Temp Directory
$tempPath = if ($MockRoot) { Join-Path $MockRoot 'AppData\Local\Temp' } else { "$env:LOCALAPPDATA\Temp" }
if (Test-Path -LiteralPath $tempPath) {
    $tmpFiles = Get-ChildItem -LiteralPath $tempPath -Recurse -File -Force -ErrorAction SilentlyContinue
    $tmpSizeMB = [math]::Round(($tmpFiles | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
    if ($tmpSizeMB -gt 50 -or $MockRoot) {
        $residues += [PSCustomObject]@{
            ID = 'SYS-' + ($sysCounter++).ToString('D3')
            Tier = 1
            Category = 'User Temp'
            Name = '用户临时运行缓存 (AppData Local Temp)'
            Path = $tempPath
            SizeMB = $tmpSizeMB
            FileCount = $tmpFiles.Count
            RiskLevel = 'Zero'
            Description = '应用程序运行时产生的临时中转数据。已随进程退出失效，随时可通过 clean_user_temp.ps1 或 clean_selected_residues.ps1 清理。'
        }
    }
}

# =========================================================
# 🟡 TIER 2: GPU Driver OTA Cache (Low-Decision)
# =========================================================
$nvOtaPath = if ($MockRoot) {
    Join-Path $MockRoot 'ProgramData\NVIDIA Corporation\NVIDIA App\UpdateFramework\ota-artifacts'
} else {
    'C:\ProgramData\NVIDIA Corporation\NVIDIA App\UpdateFramework\ota-artifacts'
}

if (Test-Path -LiteralPath $nvOtaPath) {
    $nvFiles = Get-ChildItem -LiteralPath $nvOtaPath -Recurse -File -Force -ErrorAction SilentlyContinue
    $nvSizeMB = [math]::Round(($nvFiles | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
    if ($MockRoot -or $nvSizeMB -gt 50) {
        $exeFiles = $nvFiles | Where-Object { $_.Extension -eq '.exe' }
        $exeName = if ($exeFiles) { $exeFiles[0].Name } else { 'NVIDIA Driver Package' }
        $residues += [PSCustomObject]@{
            ID = 'RES-' + ($resCounter++).ToString('D3')
            Tier = 2
            Category = 'GPU Driver Cache'
            Name = 'NVIDIA App 驱动安装源缓存 (' + $exeName + ')'
            Path = $nvOtaPath
            SizeMB = $nvSizeMB
            FileCount = $nvFiles.Count
            RiskLevel = 'Low-Decision'
            Description = '驱动升级后遗留在本地的离线安装包及解压源文件。删除完全不影响当前运行中的显卡驱动与游戏性能；唯一影响是以后在 NVIDIA App 里点击重新安装驱动时需重新联网下载。'
        }
    }
}

# =========================================================
# 🟠 TIER 3: App Residuals & Safe Diagnostic Caches
# =========================================================

# 3.1 Steam Uninstalled Game Residuals
$steamCommonPaths = @()
if ($MockRoot) {
    $steamCommonPaths += Join-Path $MockRoot 'Steam\steamapps\common'
} else {
    $drives = Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter } | ForEach-Object { "$($_.DriveLetter):\" }
    foreach ($d in $drives) {
        $p1 = Join-Path $d 'STEAM\steamapps\common'
        $p2 = Join-Path $d 'SteamLibrary\steamapps\common'
        $p3 = Join-Path $d 'Program Files (x86)\Steam\steamapps\common'
        foreach ($p in @($p1, $p2, $p3)) {
            if (Test-Path -LiteralPath $p) { $steamCommonPaths += $p }
        }
    }
}

foreach ($scPath in $steamCommonPaths) {
    if (Test-Path -LiteralPath $scPath) {
        $folders = Get-ChildItem -LiteralPath $scPath -Directory -ErrorAction SilentlyContinue
        foreach ($f in $folders) {
            $files = Get-ChildItem -LiteralPath $f.FullName -Recurse -File -Force -ErrorAction SilentlyContinue
            $szMB = [math]::Round(($files | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
            $hasExe = ($files | Where-Object { $_.Extension -eq '.exe' } | Measure-Object).Count -gt 0
            if ($szMB -lt 150 -and (-not $hasExe -or $files.Count -lt 5)) {
                $residues += [PSCustomObject]@{
                    ID = 'RES-' + ($resCounter++).ToString('D3')
                    Tier = 3
                    Category = 'Steam Residual'
                    Name = 'Steam 卸载残余: ' + $f.Name
                    Path = $f.FullName
                    SizeMB = $szMB
                    FileCount = $files.Count
                    RiskLevel = 'Zero'
                    Description = '游戏已卸载后遗留的无用空壳目录（仅含残余配置文件或排错日志）。'
                }
            }
        }
    }
}

# 3.2 Common Software Empty or Orphaned Root Directories
$checkRoots = @()
if ($MockRoot) {
    $checkRoots += $MockRoot
} else {
    $drives = Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter } | ForEach-Object { "$($_.DriveLetter):\" }
    $checkRoots += $drives
}

foreach ($r in $checkRoots) {
    if (Test-Path -LiteralPath $r) {
        $candidates = Get-ChildItem -LiteralPath $r -Directory -Force -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -match '^(MUMU|_ide|鑻|中国移动|Temp|downloading)$' -or $_.Name -like '*鑻*'
        }
        foreach ($c in $candidates) {
            $files = Get-ChildItem -LiteralPath $c.FullName -Recurse -File -Force -ErrorAction SilentlyContinue
            $szMB = [math]::Round(($files | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
            if ($szMB -lt 10) {
                $residues += [PSCustomObject]@{
                    ID = 'RES-' + ($resCounter++).ToString('D3')
                    Tier = 3
                    Category = 'Empty/Corrupt Directory'
                    Name = '软件空目录/乱码残余: ' + $c.Name
                    Path = $c.FullName
                    SizeMB = $szMB
                    FileCount = $files.Count
                    RiskLevel = 'Zero'
                    Description = '已卸载软件或解压异常遗留的废弃空文件夹。'
                }
            }
        }
    }
}

# 3.3 Office & Communication Safe Caches
$cacheTargets = @()
if ($MockRoot) {
    $cacheTargets += @(
        @{ Cat = 'WPS Cache'; Name = 'WPS 自动备份临时快照'; Path = (Join-Path $MockRoot 'AppData\Kingsoft\backup'); Desc = 'WPS 历史临时快照备份包（用户文档本体安全保存在各工作区）' },
        @{ Cat = 'WeChat Log'; Name = '微信运行排错日志'; Path = (Join-Path $MockRoot 'AppData\Tencent\WeChat\log'); Desc = '微信诊断日志，不含聊天记录与个人文件' },
        @{ Cat = 'QQ Cache'; Name = 'QQ 崩溃转储文件'; Path = (Join-Path $MockRoot 'AppData\Tencent\QQ\CrashDump'); Desc = 'QQ 崩溃内存转储，可安全清空' },
        @{ Cat = 'Lark Log'; Name = '飞书 Crashpad 日志'; Path = (Join-Path $MockRoot 'AppData\LarkShell\crashpad'); Desc = '飞书客户端运行诊断日志' },
        @{ Cat = 'WeChat Applet'; Name = '微信小程序离线缓存'; Path = (Join-Path $MockRoot 'AppData\Tencent\WeChat\Applet'); Desc = '电脑微信点开过的小程序离线沙箱缓存，再次打开时会自动拉取最新版' }
    )
} else {
    $localApp = $env:LOCALAPPDATA
    $roamApp = $env:APPDATA

    $cacheTargets += @(
        @{ Cat = 'WPS Cache'; Name = 'WPS 本地升级包缓存'; Path = "$localApp\Kingsoft\wps\download"; Desc = 'WPS 历史版本离线升级包' },
        @{ Cat = 'WPS Cache'; Name = 'WPS 临时自动备份快照'; Path = "$roamApp\Kingsoft\office6\data\backup"; Desc = '历史临时快照备份包（用户原始文档安全保存在个人工作区）' },
        @{ Cat = 'WeChat Cache'; Name = '微信运行排错日志'; Path = "$roamApp\Tencent\WeChat\log"; Desc = '微信诊断日志，不含任何聊天记录' },
        @{ Cat = 'WeChat Cache'; Name = '微信崩溃转储快照'; Path = "$localApp\Tencent\WeChat\CrashDump"; Desc = '微信崩溃时生成的临时 dump 报告' },
        @{ Cat = 'WeChat Cache'; Name = '微信电脑版小程序/组件缓存'; Path = "$localApp\Tencent\WeChat\XPlugin"; Desc = '微信小程序独立运行环境组件缓存，删后不影响个人数据' },
        @{ Cat = 'QQ Cache'; Name = 'QQ 崩溃转储快照'; Path = "$localApp\Tencent\QQ\CrashDump"; Desc = 'QQ 历史崩溃内存 dump' },
        @{ Cat = 'Lark Cache'; Name = '飞书 Crashpad 日志'; Path = "$roamApp\LarkShell\crashpad"; Desc = '飞书客户端运行诊断日志' },
        @{ Cat = 'DingTalk Cache'; Name = '钉钉运行排错日志'; Path = "$roamApp\DingTalk\logs"; Desc = '钉钉客户端运行诊断日志' }
    )
}

foreach ($ct in $cacheTargets) {
    if (Test-Path -LiteralPath $ct.Path) {
        $files = Get-ChildItem -LiteralPath $ct.Path -Recurse -File -Force -ErrorAction SilentlyContinue
        $szMB = [math]::Round(($files | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
        if ($szMB -gt 0.1 -or $files.Count -gt 0) {
            $residues += [PSCustomObject]@{
                ID = 'RES-' + ($resCounter++).ToString('D3')
                Tier = 3
                Category = $ct.Cat
                Name = $ct.Name
                Path = $ct.Path
                SizeMB = $szMB
                FileCount = $files.Count
                RiskLevel = 'Low'
                Description = $ct.Desc
            }
        }
    }
}

# =========================================================
# 4. Generate Canonical 4-Tier Markdown Manifest
# =========================================================
$manifestDir = if ($MockRoot) {
    Join-Path $MockRoot '.save-my-disk'
} else {
    Join-Path (Split-Path $PSScriptRoot -Parent) '.save-my-disk'
}

if (-not $OutputManifest) {
    if (-not (Test-Path -LiteralPath $manifestDir)) {
        New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null
    }
    $OutputManifest = Join-Path $manifestDir 'cleanup_manifest.md'
} else {
    $parent = Split-Path $OutputManifest -Parent
    if ($parent -and (-not (Test-Path -LiteralPath $parent))) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
}

$reclaimableItems = $residues | Where-Object { $_.SizeMB -gt 0 }
$sumVal = ($reclaimableItems | Measure-Object -Property SizeMB -Sum).Sum
if (-not $sumVal) { $sumVal = 0 }
$totalSizeMB = [math]::Round($sumVal, 2)
$totalSizeGB = [math]::Round($totalSizeMB / 1024, 2)

$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine('# Save My Disk - 磁盘体检与候选清理清单 (Manifest)')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('> 生成时间：' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
[void]$sb.AppendLine('> 候选清理项数量：' + $reclaimableItems.Count + ' 项 (已审计健康项已单独列出)')
[void]$sb.AppendLine('> 预估可释放空间上限：' + $totalSizeMB + ' MB (~' + $totalSizeGB + ' GB)')
[void]$sb.AppendLine('> 核心协议：本清单为单一真实事实来源（SSOT）。请在下方将待清理项的 [ ] 改为 [x] 保存后让 Agent 执行，或直接在聊天窗口告知编号。')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('---')
[void]$sb.AppendLine('')

# Section 1: Tier 1
[void]$sb.AppendLine('## 🟢 Tier 1: 零风险系统与更新项 (Zero-Risk System & Update)')
[void]$sb.AppendLine('')
$tier1Items = $residues | Where-Object { $_.Tier -eq 1 }
foreach ($item in $tier1Items) {
    if ($item.SizeMB -eq 0) {
        [void]$sb.AppendLine('- 🟢 **[' + $item.ID + '] ' + $item.Name + '** 【0 MB - 状态：健康已清理】')
        [void]$sb.AppendLine('  * 路径：`' + $item.Path + '`')
        [void]$sb.AppendLine('  * 说明：' + $item.Description)
        [void]$sb.AppendLine('')
    } else {
        [void]$sb.AppendLine('- [ ] **[' + $item.ID + '] ' + $item.Name + '** 【零风险 - 纯废弃】')
        [void]$sb.AppendLine('  * 路径：`' + $item.Path + '`')
        [void]$sb.AppendLine('  * 大小：' + $item.SizeMB + ' MB (' + $item.FileCount + ' 个文件)')
        [void]$sb.AppendLine('  * 说明与建议：' + $item.Description)
        [void]$sb.AppendLine('')
    }
}

[void]$sb.AppendLine('<!-- TIER1_PKG_CACHES_PLACEHOLDER -->')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('<!-- TIER1_IM_OFFICE_PLACEHOLDER -->')
[void]$sb.AppendLine('')

# Section 2: Tier 2
[void]$sb.AppendLine('## 🟡 Tier 2: 开发者与环境大缓存 (需权衡决策)')
[void]$sb.AppendLine('')
$tier2Items = $residues | Where-Object { $_.Tier -eq 2 }
if ($tier2Items.Count -eq 0) {
    [void]$sb.AppendLine('*未发现独立的显卡离线驱动安装包缓存。*')
    [void]$sb.AppendLine('')
} else {
    foreach ($item in $tier2Items) {
        [void]$sb.AppendLine('- [ ] **[' + $item.ID + '] ' + $item.Name + '** 【需权衡决策 - 见说明】')
        [void]$sb.AppendLine('  * 路径：`' + $item.Path + '`')
        [void]$sb.AppendLine('  * 大小：' + $item.SizeMB + ' MB (' + $item.FileCount + ' 个文件)')
        [void]$sb.AppendLine('  * 说明与权衡：' + $item.Description)
        [void]$sb.AppendLine('')
    }
}
[void]$sb.AppendLine('<!-- TIER2_AI_MODELS_PLACEHOLDER -->')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('<!-- TIER2_PKG_CACHES_PLACEHOLDER -->')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('<!-- DEV_ARTIFACTS_PLACEHOLDER -->')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('<!-- TIER2_IM_OFFICE_PLACEHOLDER -->')
[void]$sb.AppendLine('')

# Section 3: Tier 3
[void]$sb.AppendLine('## 🟠 Tier 3: 常用软件残留与日志 (推荐清理)')
[void]$sb.AppendLine('')
$tier3Items = $residues | Where-Object { $_.Tier -eq 3 }
if ($tier3Items.Count -eq 0) {
    [void]$sb.AppendLine('*未发现软件卸载空目录或常用办公通讯缓存。*')
    [void]$sb.AppendLine('')
} else {
    foreach ($item in $tier3Items) {
        $riskBadge = switch ($item.RiskLevel) {
            'Zero' { '【零风险 - 纯废弃】' }
            'Low'  { '【低风险 - 运行排错日志】' }
            Default { '【常规缓存】' }
        }
        [void]$sb.AppendLine('- [ ] **[' + $item.ID + '] ' + $item.Name + '** ' + $riskBadge)
        [void]$sb.AppendLine('  * 路径：`' + $item.Path + '`')
        [void]$sb.AppendLine('  * 大小：' + $item.SizeMB + ' MB (' + $item.FileCount + ' 个文件)')
        [void]$sb.AppendLine('  * 说明：' + $item.Description)
        [void]$sb.AppendLine('')
    }
}

[void]$sb.AppendLine('<!-- TIER3_IM_OFFICE_PLACEHOLDER -->')
[void]$sb.AppendLine('')

# Section 4: Tier 4
[void]$sb.AppendLine('---')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## 🔴 Tier 4: 严禁触碰的保护红线 (Protected Red Line)')
[void]$sb.AppendLine('* System32 与 SysWOW64 (Windows 核心系统文件与动态链接库)')
[void]$sb.AppendLine('* WinSxS (Windows 并行组件存储库，严禁直接删除文件)')
[void]$sb.AppendLine('* 个人工作区与工程源代码文件（任何删除规则均不得误伤项目源码）')
[void]$sb.AppendLine('* 微信与 QQ 的核心聊天记录数据库及用户已接收的个人文件')
[void]$sb.AppendLine('')

[System.IO.File]::WriteAllText($OutputManifest, $sb.ToString(), (New-Object System.Text.UTF8Encoding($true)))

# =========================================================
# Output Results
# =========================================================
if ($Json) {
    $residues | ConvertTo-Json -Depth 3
} else {
    Write-Host "`n=== 4-TIER DISK AUDIT CANDIDATES (v0.3.1) ===" -ForegroundColor Cyan
    $residues | Select-Object ID, Tier, Category, SizeMB, FileCount, Name | Format-Table -AutoSize
    Write-Host "`nManifest file generated at: $OutputManifest" -ForegroundColor Green
    Write-Host "Total reclaimable space detected: $totalSizeMB MB (~$totalSizeGB GB)" -ForegroundColor Yellow
    Write-Host "Tip: Review the manifest above or specify IDs like: clean_selected_residues.ps1 -TargetIds RES-001 -Force" -ForegroundColor Gray
}
