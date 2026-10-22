<#
.SYNOPSIS
    Scans for application residues, uninstalled Steam game remnants, empty software directories,
    NVIDIA OTA driver caches, and safe-to-clean office/chat caches (WPS, WeChat, QQ, Feishu, DingTalk).
.DESCRIPTION
    Non-invasive read-only scanner for save-my-disk (v0.2).
    Outputs an itemized list with unique IDs, categories, sizes, and detailed risk/tradeoff analysis.
    Generates a persistent Markdown manifest (.save-my-disk/cleanup_manifest.md) to eliminate LLM hallucinations.
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
$counter = 1

# ---------------------------------------------------------
# 1. Detect NVIDIA App / GPU Driver OTA Installer Cache
# ---------------------------------------------------------
$nvOtaPath = if ($MockRoot) {
    Join-Path $MockRoot "ProgramData\NVIDIA Corporation\NVIDIA App\UpdateFramework\ota-artifacts"
} else {
    "C:\ProgramData\NVIDIA Corporation\NVIDIA App\UpdateFramework\ota-artifacts"
}

if (Test-Path $nvOtaPath) {
    $nvFiles = Get-ChildItem -LiteralPath $nvOtaPath -Recurse -File -Force -ErrorAction SilentlyContinue
    $nvSizeMB = [math]::Round(($nvFiles | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
    if ($MockRoot -or $nvSizeMB -gt 50) {
        $exeFiles = $nvFiles | Where-Object { $_.Extension -eq '.exe' }
        $exeName = if ($exeFiles) { $exeFiles[0].Name } else { "NVIDIA Driver Package" }
        $residues += [PSCustomObject]@{
            ID = "RES-" + ($counter++).ToString("D3")
            Category = "GPU Driver Cache"
            Name = "NVIDIA App 驱动安装源缓存 ($exeName)"
            Path = $nvOtaPath
            SizeMB = $nvSizeMB
            FileCount = $nvFiles.Count
            RiskLevel = "Low-Decision"
            Description = "驱动升级后遗留在本地的离线安装包及解压源文件。删除完全不影响当前运行中的显卡驱动与游戏性能；唯一影响是以后在 NVIDIA App 里点击重新安装驱动时需重新联网下载。"
        }
    }
}

# ---------------------------------------------------------
# 2. Detect Steam Uninstalled Game Residuals & Shader Cache
# ---------------------------------------------------------
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
            $hasExe = ($files | Where-Object { $_.Extension -eq '.exe' } | Measure-Object).Count -gt 0
            if ($szMB -lt 150 -and (-not $hasExe -or $files.Count -lt 5)) {
                $residues += [PSCustomObject]@{
                    ID = "RES-" + ($counter++).ToString("D3")
                    Category = "Steam Residual"
                    Name = "Steam 卸载残余: " + $f.Name
                    Path = $f.FullName
                    SizeMB = $szMB
                    FileCount = $files.Count
                    RiskLevel = "Zero"
                    Description = "游戏已卸载后遗留的无用空壳目录（仅含残余配置文件或排错日志）。"
                }
            }
        }
    }
}

# ---------------------------------------------------------
# 3. Detect Common Software Empty or Orphaned Root Directories
# ---------------------------------------------------------
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
                    Name = "软件空目录/乱码残余: " + $c.Name
                    Path = $c.FullName
                    SizeMB = $szMB
                    FileCount = $files.Count
                    RiskLevel = "Zero"
                    Description = "已卸载软件或解压异常遗留的废弃空文件夹。"
                }
            }
        }
    }
}

# ---------------------------------------------------------
# 4. Detect Office & Communication Safe Caches
# ---------------------------------------------------------
$cacheTargets = @()
if ($MockRoot) {
    $cacheTargets += @(
        @{ Cat = "WPS Cache"; Name = "WPS 自动备份临时快照"; Path = (Join-Path $MockRoot "AppData\Kingsoft\backup"); Desc = "WPS 历史临时快照备份包（用户文档本体安全保存在各工作区）" },
        @{ Cat = "WeChat Log"; Name = "微信运行排错日志"; Path = (Join-Path $MockRoot "AppData\Tencent\WeChat\log"); Desc = "微信诊断日志，不含聊天记录与个人文件" },
        @{ Cat = "QQ Cache"; Name = "QQ 崩溃转储文件"; Path = (Join-Path $MockRoot "AppData\Tencent\QQ\CrashDump"); Desc = "QQ 崩溃内存转储，可安全清空" },
        @{ Cat = "Lark Log"; Name = "飞书 Crashpad 日志"; Path = (Join-Path $MockRoot "AppData\LarkShell\crashpad"); Desc = "飞书客户端运行诊断日志" },
        @{ Cat = "WeChat Applet"; Name = "微信小程序离线缓存"; Path = (Join-Path $MockRoot "AppData\Tencent\WeChat\Applet"); Desc = "电脑微信点开过的小程序离线沙箱缓存，再次打开时会自动拉取最新版" }
    )
} else {
    $localApp = $env:LOCALAPPDATA
    $roamApp = $env:APPDATA
    $userProf = $env:USERPROFILE

    $cacheTargets += @(
        @{ Cat = "WPS Cache"; Name = "WPS 本地升级包缓存"; Path = "$localApp\Kingsoft\wps\download"; Desc = "WPS 历史版本离线升级包" },
        @{ Cat = "WPS Cache"; Name = "WPS 临时自动备份快照"; Path = "$roamApp\Kingsoft\office6\data\backup"; Desc = "历史临时快照备份包（用户原始文档安全保存在个人工作区）" },
        @{ Cat = "WeChat Cache"; Name = "微信运行排错日志"; Path = "$roamApp\Tencent\WeChat\log"; Desc = "微信诊断日志，不含任何聊天记录" },
        @{ Cat = "WeChat Cache"; Name = "微信崩溃转储快照"; Path = "$localApp\Tencent\WeChat\CrashDump"; Desc = "微信崩溃时生成的临时 dump 报告" },
        @{ Cat = "WeChat Cache"; Name = "微信电脑版小程序/组件缓存"; Path = "$localApp\Tencent\WeChat\XPlugin"; Desc = "微信小程序独立运行环境组件缓存，删后不影响个人数据" },
        @{ Cat = "QQ Cache"; Name = "QQ 崩溃转储快照"; Path = "$localApp\Tencent\QQ\CrashDump"; Desc = "QQ 历史崩溃内存 dump" },
        @{ Cat = "Lark Cache"; Name = "飞书 Crashpad 日志"; Path = "$roamApp\LarkShell\crashpad"; Desc = "飞书客户端运行诊断日志" },
        @{ Cat = "DingTalk Cache"; Name = "钉钉运行排错日志"; Path = "$roamApp\DingTalk\logs"; Desc = "钉钉客户端运行诊断日志" }
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

# ---------------------------------------------------------
# 5. Generate Markdown Manifest (.save-my-disk/cleanup_manifest.md)
# ---------------------------------------------------------
$manifestDir = if ($MockRoot) {
    Join-Path $MockRoot ".save-my-disk"
} else {
    Join-Path (Split-Path $PSScriptRoot -Parent) ".save-my-disk"
}

if (-not $OutputManifest) {
    if (-not (Test-Path $manifestDir)) {
        New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null
    }
    $OutputManifest = Join-Path $manifestDir "cleanup_manifest.md"
} else {
    $parent = Split-Path $OutputManifest -Parent
    if ($parent -and (-not (Test-Path $parent))) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
}

$totalSizeMB = [math]::Round(($residues | Measure-Object -Property SizeMB -Sum).Sum, 2)
$totalSizeGB = [math]::Round($totalSizeMB / 1024, 2)

$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine("# Save My Disk - 磁盘体检与候选清理清单 (Manifest)")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("> 生成时间：" + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
[void]$sb.AppendLine("> 候选清理项数量：" + $residues.Count + " 项")
[void]$sb.AppendLine("> 预估可释放空间上限：" + $totalSizeMB + " MB (~" + $totalSizeGB + " GB)")
[void]$sb.AppendLine('> 操作说明：本文件是 Agent 与您的单一真实事实来源（SSOT）。您可以在下方将想清理项的 [ ] 改为 [x]，保存后告知 Agent 按照清单执行清理；或者直接在聊天框中告知 Agent 对应的编号（如“清理 RES-001”）。')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('---')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## 候选清理清单明细')
[void]$sb.AppendLine('')

foreach ($item in $residues) {
    $riskBadge = switch ($item.RiskLevel) {
        "Zero" { "【零风险 - 纯废弃】" }
        "Low" { "【低风险 - 纯运行缓存】" }
        "Low-Decision" { "【需权衡决策 - 见说明】" }
        Default { "【常规缓存】" }
    }
    [void]$sb.AppendLine('- [ ] **[' + $item.ID + '] ' + $item.Name + '** ' + $riskBadge)
    [void]$sb.AppendLine('  * 路径：`' + $item.Path + '`')
    [void]$sb.AppendLine('  * 大小：' + $item.SizeMB + ' MB (' + $item.FileCount + ' 个文件)')
    [void]$sb.AppendLine('  * 说明与权衡：' + $item.Description)
    [void]$sb.AppendLine('')
}

[void]$sb.AppendLine("---")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## 严禁触碰的保护红线 (Tier 4)")
[void]$sb.AppendLine("* System32 与 SysWOW64 (操作系统核心)")
[void]$sb.AppendLine("* WinSxS (Windows 组件存储库)")
[void]$sb.AppendLine("* 个人工作区与工程代码文件库")
[void]$sb.AppendLine("* 微信与 QQ 的核心聊天记录数据库与已接收文件")

[System.IO.File]::WriteAllText($OutputManifest, $sb.ToString(), [System.Text.Encoding]::UTF8)

# ---------------------------------------------------------
# Output results
# ---------------------------------------------------------
if ($Json) {
    $residues | ConvertTo-Json -Depth 3
} else {
    Write-Host "`n=== DETECTED APP RESIDUES & SAFE CACHES (v0.2) ===" -ForegroundColor Cyan
    if ($residues.Count -eq 0) {
        Write-Host "No residue or safe cache targets found." -ForegroundColor Green
    } else {
        $residues | Select-Object ID, Category, SizeMB, FileCount, Name, Path | Format-Table -AutoSize
        Write-Host "`nManifest file generated at: $OutputManifest" -ForegroundColor Green
        Write-Host "Total reclaimable space detected: $totalSizeMB MB (~$totalSizeGB GB)" -ForegroundColor Yellow
        Write-Host "Tip: Review the manifest above or specify IDs like 'clean_selected_residues.ps1 -TargetIds RES-001 -Force'." -ForegroundColor Gray
    }
}
