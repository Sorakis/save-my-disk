<#
.SYNOPSIS
    Scans for domestic instant messaging & heavyweight office app caches (WeChat 3.x/4.0, WXWork, QQ, Feishu, DingTalk).
.DESCRIPTION
    Non-invasive read-only scanner for save-my-disk (v0.5.1).
    Distinguishes ephemeral playback/image caches (Tier 3) from historic received files (Tier 2).
    Strictly shields all chat history databases (*.db, *.kvdb, db_storage) into Tier 4 immunity.
.PARAMETER MockRoot
    Used for unit testing in an isolated mock sandbox.
.PARAMETER OutputManifest
    File path to write the Markdown manifest to. Defaults to '.save-my-disk/cleanup_manifest.md'.
.PARAMETER DaysInactive
    Threshold in days for identifying inactive historic received documents. Default is 90.
.PARAMETER Json
    Outputs structured JSON.
#>
param(
    [string]$MockRoot,
    [string]$OutputManifest,
    [int]$DaysInactive = 90,
    [switch]$Json
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$imFound = @()
$counter = 1
$cutoffDate = (Get-Date).AddDays(-$DaysInactive)

# Helper function to measure a directory safely
function Get-SafeFolderMetrics {
    param([string]$Path, [scriptblock]$FilterBlock)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $files = Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue
    if ($FilterBlock) {
        $files = $files | Where-Object $FilterBlock
    }
    $totalBytes = ($files | Measure-Object -Property Length -Sum).Sum
    if (-not $totalBytes) { $totalBytes = 0 }
    return [PSCustomObject]@{
        Path = $Path
        FileCount = $files.Count
        SizeMB = [math]::Round($totalBytes / 1MB, 2)
    }
}

# =========================================================
# 1. Tencent WeChat 3.x (WeChat Files)
# =========================================================
$wechat3Roots = @()
if ($MockRoot) {
    $m3 = Join-Path $MockRoot "Documents\WeChat Files"
    if (Test-Path -LiteralPath $m3) { $wechat3Roots += $m3 }
} else {
    try {
        $regVal = (Get-ItemProperty -Path "HKCU:\Software\Tencent\WeChat" -Name "FileSavePath" -ErrorAction SilentlyContinue).FileSavePath
        if ($regVal) {
            $regVal = $regVal.Trim()
            if ($regVal -eq "MyDocument:" -or $regVal -eq "") {
                $docDir = [Environment]::GetFolderPath('MyDocuments')
                $wechat3Roots += (Join-Path $docDir "WeChat Files")
            } else {
                $wechat3Roots += [System.IO.Path]::GetFullPath($regVal)
            }
        }
    } catch {}
    $defaultDoc = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "WeChat Files"
    if (Test-Path -LiteralPath $defaultDoc) { $wechat3Roots += $defaultDoc }
}
$wechat3Roots = $wechat3Roots | Select-Object -Unique

$wechatBlacklist = @('All Users', 'all_users', 'Applet', 'WMPF', 'Backup', 'BackupFiles')

foreach ($wRoot in $wechat3Roots) {
    if (-not (Test-Path -LiteralPath $wRoot)) { continue }
    $accountDirs = Get-ChildItem -LiteralPath $wRoot -Directory -Force -ErrorAction SilentlyContinue | Where-Object {
        $wechatBlacklist -notcontains $_.Name
    }

    foreach ($acc in $accountDirs) {
        $accPath = $acc.FullName
        $accName = $acc.Name

        # 1.1 Video Cache (Tier 3)
        $vidPath = Join-Path $accPath "FileStorage\Video"
        $m = Get-SafeFolderMetrics -Path $vidPath
        if ($m -and ($m.SizeMB -gt 10 -or $MockRoot)) {
            $imFound += [PSCustomObject]@{
                ID = "IM-" + ($counter++).ToString("D3")
                Tier = 3
                App = "WeChat 3.x"
                Category = "WeChat Video Cache"
                Name = "微信 3.x 视频播放缓存 ($accName)"
                Path = $vidPath
                SizeMB = $m.SizeMB
                FileCount = $m.FileCount
                RiskLevel = "Low"
                Description = "微信聊天中播放短视频产生的本地缓存文件。删除不影响文字聊天记录，重新在聊天记录中点击视频可重新加载播放。"
            }
        }

        # 1.2 Cache / Emoticons / Thumbnails (Tier 3)
        $cachePath = Join-Path $accPath "FileStorage\Cache"
        $m = Get-SafeFolderMetrics -Path $cachePath
        if ($m -and ($m.SizeMB -gt 10 -or $MockRoot)) {
            $imFound += [PSCustomObject]@{
                ID = "IM-" + ($counter++).ToString("D3")
                Tier = 3
                App = "WeChat 3.x"
                Category = "WeChat Emoji & Thumb Cache"
                Name = "微信 3.x 表情与缩略图缓存 ($accName)"
                Path = $cachePath
                SizeMB = $m.SizeMB
                FileCount = $m.FileCount
                RiskLevel = "Low"
                Description = "微信聊天中的表情包、头像与临时预览缩略图。删除后不影响聊天记录本身，必要时微信会自动重新拉取缩略图。"
            }
        }

        # 1.3 Received Chat Images (Tier 2 - Tradeoff)
        $imgPath = Join-Path $accPath "FileStorage\Image"
        $m = Get-SafeFolderMetrics -Path $imgPath
        if ($m -and ($m.SizeMB -gt 50 -or $MockRoot)) {
            $imFound += [PSCustomObject]@{
                ID = "IM-" + ($counter++).ToString("D3")
                Tier = 2
                App = "WeChat 3.x"
                Category = "WeChat Received Images"
                Name = "微信 3.x 历史聊天图片缓存 ($accName)"
                Path = $imgPath
                SizeMB = $m.SizeMB
                FileCount = $m.FileCount
                RiskLevel = "Low-Decision"
                Description = "微信聊天中接收的已保存图片。清理后在聊天记录中查看历史原图时可能显示已过期，建议仅在确保存档后勾选。"
            }
        }

        # 1.4 Inactive Received Files (> 90 days) (Tier 2 - Tradeoff)
        $filePath = Join-Path $accPath "FileStorage\File"
        $m = Get-SafeFolderMetrics -Path $filePath -FilterBlock { $_.LastWriteTime -lt $cutoffDate }
        if ($m -and ($m.SizeMB -gt 20 -or $MockRoot)) {
            $imFound += [PSCustomObject]@{
                ID = "IM-" + ($counter++).ToString("D3")
                Tier = 2
                App = "WeChat 3.x"
                Category = "WeChat Inactive Files"
                Name = "微信 3.x 沉睡历史接收文档 (>$DaysInactive 天未访问) ($accName)"
                Path = $filePath
                SizeMB = $m.SizeMB
                FileCount = $m.FileCount
                RiskLevel = "Low-Decision"
                Description = "微信接收且超过 $DaysInactive 天未修改的历史文档（PDF、Office、压缩包等）。清理前请确认工作区已备份重要文档。"
            }
        }
    }
}

# =========================================================
# 2. Tencent WeChat 4.0 (xwechat_files)
# =========================================================
$wechat4Roots = @()
if ($MockRoot) {
    $m4 = Join-Path $MockRoot "Documents\xwechat_files"
    if (Test-Path -LiteralPath $m4) { $wechat4Roots += $m4 }
} else {
    try {
        $regVal = (Get-ItemProperty -Path "HKCU:\Software\Tencent\Weixin" -Name "FileSavePath" -ErrorAction SilentlyContinue).FileSavePath
        if ($regVal) {
            $regVal = $regVal.Trim()
            if ($regVal -eq "MyDocument:" -or $regVal -eq "") {
                $docDir = [Environment]::GetFolderPath('MyDocuments')
                $wechat4Roots += (Join-Path $docDir "xwechat_files")
            } else {
                $wechat4Roots += [System.IO.Path]::GetFullPath($regVal)
            }
        }
    } catch {}
    $defaultDoc4 = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "xwechat_files"
    if (Test-Path -LiteralPath $defaultDoc4) { $wechat4Roots += $defaultDoc4 }
}
$wechat4Roots = $wechat4Roots | Select-Object -Unique

foreach ($wRoot in $wechat4Roots) {
    if (-not (Test-Path -LiteralPath $wRoot)) { continue }
    $accountDirs = Get-ChildItem -LiteralPath $wRoot -Directory -Force -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -ne 'all_users' -and $_.Name -ne 'All Users' -and $_.Name -ne 'Backup'
    }

    foreach ($acc in $accountDirs) {
        $accPath = $acc.FullName
        $accName = $acc.Name

        # 2.1 WeChat 4.0 Cache (Emoticon, HttpResource, Message, Sns) (Tier 3)
        $cPath = Join-Path $accPath "cache"
        $m = Get-SafeFolderMetrics -Path $cPath
        if ($m -and ($m.SizeMB -gt 10 -or $MockRoot)) {
            $imFound += [PSCustomObject]@{
                ID = "IM-" + ($counter++).ToString("D3")
                Tier = 3
                App = "WeChat 4.0"
                Category = "WeChat 4.0 Resource Cache"
                Name = "微信 4.0 资源与表情缓存 ($accName)"
                Path = $cPath
                SizeMB = $m.SizeMB
                FileCount = $m.FileCount
                RiskLevel = "Low"
                Description = "微信 4.0 全新架构下的表情包、朋友圈流媒体预览与 HTTP 临时资源缓存。清空不影响聊天记录。"
            }
        }

        # 2.2 WeChat 4.0 Temp Images (Tier 3)
        $tempImgPath = Join-Path $accPath "temp"
        $m = Get-SafeFolderMetrics -Path $tempImgPath
        if ($m -and ($m.SizeMB -gt 10 -or $MockRoot)) {
            $imFound += [PSCustomObject]@{
                ID = "IM-" + ($counter++).ToString("D3")
                Tier = 3
                App = "WeChat 4.0"
                Category = "WeChat 4.0 Temp Images"
                Name = "微信 4.0 临时图片与头像缓存 ($accName)"
                Path = $tempImgPath
                SizeMB = $m.SizeMB
                FileCount = $m.FileCount
                RiskLevel = "Low"
                Description = "微信 4.0 运行生成的临时图片中转与联系人头像缓存。"
            }
        }

        # 2.3 WeChat 4.0 Video (Tier 3)
        $v4Path = Join-Path $accPath "msg\video"
        $m = Get-SafeFolderMetrics -Path $v4Path
        if ($m -and ($m.SizeMB -gt 10 -or $MockRoot)) {
            $imFound += [PSCustomObject]@{
                ID = "IM-" + ($counter++).ToString("D3")
                Tier = 3
                App = "WeChat 4.0"
                Category = "WeChat 4.0 Video Cache"
                Name = "微信 4.0 视频播放缓存 ($accName)"
                Path = $v4Path
                SizeMB = $m.SizeMB
                FileCount = $m.FileCount
                RiskLevel = "Low"
                Description = "微信 4.0 聊天记录中下载的短视频播放缓存文件。"
            }
        }

        # 2.4 WeChat 4.0 Received Files (> 90 days) (Tier 2 - Tradeoff)
        $f4Path = Join-Path $accPath "msg\file"
        $m = Get-SafeFolderMetrics -Path $f4Path -FilterBlock { $_.LastWriteTime -lt $cutoffDate }
        if ($m -and ($m.SizeMB -gt 20 -or $MockRoot)) {
            $imFound += [PSCustomObject]@{
                ID = "IM-" + ($counter++).ToString("D3")
                Tier = 2
                App = "WeChat 4.0"
                Category = "WeChat 4.0 Inactive Files"
                Name = "微信 4.0 沉睡历史接收文档 (>$DaysInactive 天未访问) ($accName)"
                Path = $f4Path
                SizeMB = $m.SizeMB
                FileCount = $m.FileCount
                RiskLevel = "Low-Decision"
                Description = "微信 4.0 接收且超过 $DaysInactive 天未访问的历史文档附件。"
            }
        }
    }
}

# =========================================================
# 3. Enterprise WeChat (企业微信 / WXWork)
# =========================================================
$wxworkRoots = @()
if ($MockRoot) {
    $mw = Join-Path $MockRoot "Documents\WXWork"
    if (Test-Path -LiteralPath $mw) { $wxworkRoots += $mw }
} else {
    try {
        $regVal = (Get-ItemProperty -Path "HKCU:\Software\Tencent\WXWork" -Name "DataPath" -ErrorAction SilentlyContinue).DataPath
        if ($regVal) { $wxworkRoots += [System.IO.Path]::GetFullPath($regVal.Trim()) }
    } catch {}
    $defWxWork = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "WXWork"
    if (Test-Path -LiteralPath $defWxWork) { $wxworkRoots += $defWxWork }
}
$wxworkRoots = $wxworkRoots | Select-Object -Unique

foreach ($wRoot in $wxworkRoots) {
    if (-not (Test-Path -LiteralPath $wRoot)) { continue }
    $corpDirs = Get-ChildItem -LiteralPath $wRoot -Directory -Force -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -notin @('Global', 'Crash', 'update', 'All Users')
    }

    foreach ($cDir in $corpDirs) {
        $cPath = $cDir.FullName
        $cName = $cDir.Name

        # 3.1 Video & Cache (Tier 3)
        $vPath = Join-Path $cPath "Storage\Video"
        $m = Get-SafeFolderMetrics -Path $vPath
        if ($m -and ($m.SizeMB -gt 10 -or $MockRoot)) {
            $imFound += [PSCustomObject]@{
                ID = "IM-" + ($counter++).ToString("D3")
                Tier = 3
                App = "WXWork"
                Category = "WXWork Video Cache"
                Name = "企业微信视频播放缓存 ($cName)"
                Path = $vPath
                SizeMB = $m.SizeMB
                FileCount = $m.FileCount
                RiskLevel = "Low"
                Description = "企业微信群聊与私聊视频播放历史缓存。"
            }
        }

        # 3.2 Inactive Files (> 90 days) (Tier 2)
        $fPath = Join-Path $cPath "Storage\File"
        $m = Get-SafeFolderMetrics -Path $fPath -FilterBlock { $_.LastWriteTime -lt $cutoffDate }
        if ($m -and ($m.SizeMB -gt 20 -or $MockRoot)) {
            $imFound += [PSCustomObject]@{
                ID = "IM-" + ($counter++).ToString("D3")
                Tier = 2
                App = "WXWork"
                Category = "WXWork Inactive Files"
                Name = "企业微信沉睡历史工作文档 (>$DaysInactive 天未访问) ($cName)"
                Path = $fPath
                SizeMB = $m.SizeMB
                FileCount = $m.FileCount
                RiskLevel = "Low-Decision"
                Description = "企业微信接收且超过 $DaysInactive 天未访问的历史文档。"
            }
        }
    }
}

# =========================================================
# 4. ByteDance Feishu (飞书) & Alibaba DingTalk (钉钉)
# =========================================================
# Feishu
$feishuPaths = @()
if ($MockRoot) {
    $feishuPaths += Join-Path $MockRoot "AppData\Local\Feishu\app_data"
} else {
    $fp1 = "$env:LOCALAPPDATA\Feishu\app_data"
    $fp2 = "$env:APPDATA\LarkShell\crashpad"
    foreach ($p in @($fp1, $fp2)) {
        if (Test-Path -LiteralPath $p) { $feishuPaths += $p }
    }
}

foreach ($fPath in $feishuPaths) {
    if (Test-Path -LiteralPath $fPath) {
        $logPath = if ($fPath -like "*crashpad*") { $fPath } else { Join-Path $fPath "logs" }
        if (-not (Test-Path -LiteralPath $logPath)) { continue }
        $m = Get-SafeFolderMetrics -Path $logPath
        if ($m -and ($m.SizeMB -gt 5 -or $MockRoot)) {
            $imFound += [PSCustomObject]@{
                ID = "IM-" + ($counter++).ToString("D3")
                Tier = 1
                App = "Feishu"
                Category = "Feishu Logs"
                Name = "飞书运行排错与崩溃日志"
                Path = $logPath
                SizeMB = $m.SizeMB
                FileCount = $m.FileCount
                RiskLevel = "Zero"
                Description = "飞书客户端运行时产生的诊断日志与崩溃记录。100% 零风险清理。"
            }
        }
    }
}

# DingTalk
$dingPaths = @()
if ($MockRoot) {
    $dingPaths += Join-Path $MockRoot "AppData\Roaming\DingTalk"
} else {
    $dp = "$env:APPDATA\DingTalk"
    if (Test-Path -LiteralPath $dp) { $dingPaths += $dp }
}

foreach ($dPath in $dingPaths) {
    if (Test-Path -LiteralPath $dPath) {
        $logPath = Join-Path $dPath "logs"
        $m = Get-SafeFolderMetrics -Path $logPath
        if ($m -and ($m.SizeMB -gt 5 -or $MockRoot)) {
            $imFound += [PSCustomObject]@{
                ID = "IM-" + ($counter++).ToString("D3")
                Tier = 1
                App = "DingTalk"
                Category = "DingTalk Logs"
                Name = "钉钉客户端排错日志"
                Path = $logPath
                SizeMB = $m.SizeMB
                FileCount = $m.FileCount
                RiskLevel = "Zero"
                Description = "钉钉客户端运行产生的诊断日志。100% 零风险清理。"
            }
        }
    }
}

# =========================================================
# Output Handling: Manifest Injection & JSON
# =========================================================
if (-not $OutputManifest) {
    $mDir = if ($MockRoot) { Join-Path $MockRoot '.save-my-disk' } else { Join-Path (Split-Path $PSScriptRoot -Parent) '.save-my-disk' }
    $OutputManifest = Join-Path $mDir 'cleanup_manifest.md'
}

if (Test-Path -LiteralPath $OutputManifest) {
    $manifestContent = Get-Content -LiteralPath $OutputManifest -Raw -Encoding UTF8

    # Format Tier 1 Markdown
    $t1Items = $imFound | Where-Object { $_.Tier -eq 1 }
    $t1Md = ""
    if ($t1Items.Count -gt 0) {
        $sb1 = [System.Text.StringBuilder]::new()
        [void]$sb1.AppendLine("### 💬 通讯与办公应用排错日志与废弃源 (IM & Office Safe Logs)")
        foreach ($item in $t1Items) {
            [void]$sb1.AppendLine("- [ ] **[$($item.ID)] $($item.Name)** 【零风险 - 日志/安装包】")
            [void]$sb1.AppendLine('  * 路径：`' + $item.Path + '`')
            [void]$sb1.AppendLine("  * 大小：$($item.SizeMB) MB ($($item.FileCount) 个文件)")
            [void]$sb1.AppendLine("  * 说明：$($item.Description)")
            [void]$sb1.AppendLine("")
        }
        $t1Md = $sb1.ToString()
    }

    # Format Tier 2 Markdown
    $t2Items = $imFound | Where-Object { $_.Tier -eq 2 }
    $t2Md = ""
    if ($t2Items.Count -gt 0) {
        $sb2 = [System.Text.StringBuilder]::new()
        [void]$sb2.AppendLine("### 💬 微信/办公长期沉睡历史文件与聊天图片 (需权衡决策)")
        foreach ($item in $t2Items) {
            [void]$sb2.AppendLine("- [ ] **[$($item.ID)] $($item.Name)** 【需权衡决策 - 沉睡文件】")
            [void]$sb2.AppendLine('  * 路径：`' + $item.Path + '`')
            [void]$sb2.AppendLine("  * 大小：$($item.SizeMB) MB ($($item.FileCount) 个文件)")
            [void]$sb2.AppendLine("  * 说明与权衡：$($item.Description)")
            [void]$sb2.AppendLine("")
        }
        $t2Md = $sb2.ToString()
    }

    # Format Tier 3 Markdown
    $t3Items = $imFound | Where-Object { $_.Tier -eq 3 }
    $t3Md = ""
    if ($t3Items.Count -gt 0) {
        $sb3 = [System.Text.StringBuilder]::new()
        [void]$sb3.AppendLine("### 💬 微信与办公软件流媒体/缩略图临时缓存 (推荐清理)")
        foreach ($item in $t3Items) {
            [void]$sb3.AppendLine("- [ ] **[$($item.ID)] $($item.Name)** 【低风险 - 临时媒体缓存】")
            [void]$sb3.AppendLine('  * 路径：`' + $item.Path + '`')
            [void]$sb3.AppendLine("  * 大小：$($item.SizeMB) MB ($($item.FileCount) 个文件)")
            [void]$sb3.AppendLine("  * 说明：$($item.Description)")
            [void]$sb3.AppendLine("")
        }
        $t3Md = $sb3.ToString()
    }

    # Anchor replacement
    if ($manifestContent -match '<!-- TIER1_IM_OFFICE_PLACEHOLDER -->') {
        $manifestContent = $manifestContent.Replace('<!-- TIER1_IM_OFFICE_PLACEHOLDER -->', $t1Md)
    }
    if ($manifestContent -match '<!-- TIER2_IM_OFFICE_PLACEHOLDER -->') {
        $manifestContent = $manifestContent.Replace('<!-- TIER2_IM_OFFICE_PLACEHOLDER -->', $t2Md)
    }
    if ($manifestContent -match '<!-- TIER3_IM_OFFICE_PLACEHOLDER -->') {
        $manifestContent = $manifestContent.Replace('<!-- TIER3_IM_OFFICE_PLACEHOLDER -->', $t3Md)
    }

    [System.IO.File]::WriteAllText($OutputManifest, $manifestContent, (New-Object System.Text.UTF8Encoding($true)))
}

if ($Json) {
    if ($imFound.Count -eq 0) {
        Write-Output "[]"
    } else {
        $imFound | ConvertTo-Json -Depth 5
    }
} else {
    Write-Host "`n=== DOMESTIC IM & OFFICE APPLICATION CACHES AUDIT ===" -ForegroundColor Yellow
    if ($imFound.Count -eq 0) {
        Write-Host "No heavy IM/office media caches detected exceeding threshold." -ForegroundColor Green
    } else {
        $imFound | Select-Object ID, Tier, App, Name, SizeMB, FileCount | Format-Table -AutoSize
        $totalMB = ($imFound | Measure-Object -Property SizeMB -Sum).Sum
        Write-Host "Total Reclaimable IM/Office Space: $totalMB MB (~$([math]::Round($totalMB / 1024, 2)) GB)" -ForegroundColor Cyan
    }
}
