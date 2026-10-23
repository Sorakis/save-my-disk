<#
.SYNOPSIS
    Interactive Terminal Menu (TUI) for Save-My-Disk.
.DESCRIPTION
    Provides an interactive, zero-dependency console control center for human developers
    to audit disk space, review 4-Tier candidates, execute guarded cleanups, and export visual reports.
#>
param(
    [string]$MockRoot,
    [switch]$NonInteractive,
    [switch]$TestMenu
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $scriptDir) { $scriptDir = ".\scripts" }

$manifestPath = if ($MockRoot) {
    Join-Path $MockRoot ".save-my-disk\cleanup_manifest.md"
} else {
    ".\.save-my-disk\cleanup_manifest.md"
}

function Show-Header {
    if ($Host.UI.RawUI -and -not [Console]::IsOutputRedirected) {
        try { Clear-Host } catch {}
    }
    Write-Host "=============================================================" -ForegroundColor Cyan
    Write-Host "  🚀 SAVE-MY-DISK (v0.5.3) - 智能磁盘诊断与安全治理控制台" -ForegroundColor Green
    Write-Host "=============================================================" -ForegroundColor Cyan
    Write-Host " [1] 🔍 一键全流程只读体检 (Full 4-Tier Audit & Manifest Base)"
    Write-Host " [2] 📊 生成并打开 HTML 可视化战报 (Export Visual Dashboard)"
    Write-Host " [3] 📋 查看当前待决策候选清单 (View Pending Candidates)"
    Write-Host " [4] 🎯 交互式受控靶向安全清理 (Targeted Clean by Manifest)"
    Write-Host " [5] 🩺 系统与服务健康自愈检查 (Verify System & Service Health)"
    Write-Host " [6] 🚪 退出控制台 (Exit)"
    Write-Host "=============================================================" -ForegroundColor Cyan
}

if ($TestMenu) {
    Show-Header
    Write-Host "[TEST MODE] Menu initialized successfully. Exiting cleanly." -ForegroundColor Green
    exit 0
}

function Run-FullAudit {
    Write-Host "`n>>> 启动全流程 4-Tier 只读深度体检..." -ForegroundColor Cyan
    $extraArgs = @{}
    if ($MockRoot) { $extraArgs['MockRoot'] = $MockRoot }
    
    Write-Host "[1/7] 正在审计磁盘卷容量与系统热点..." -ForegroundColor Gray
    & (Join-Path $scriptDir "audit_drives.ps1") @extraArgs | Out-Null
    
    Write-Host "[2/7] 正在扫描软件残留与建立基础清单..." -ForegroundColor Gray
    & (Join-Path $scriptDir "scan_app_residues.ps1") -OutputManifest $manifestPath @extraArgs | Out-Null
    
    Write-Host "[3/7] 正在扫描浏览器与 GPU 着色器深层缓存..." -ForegroundColor Gray
    & (Join-Path $scriptDir "scan_browser_system_caches.ps1") -OutputManifest $manifestPath @extraArgs | Out-Null
    
    Write-Host "[4/7] 正在扫描全局包管理器缓存 (pip, npm, Conda, Gradle)..." -ForegroundColor Gray
    & (Join-Path $scriptDir "scan_package_caches.ps1") -OutputManifest $manifestPath @extraArgs | Out-Null
    
    Write-Host "[5/7] 正在扫描本地 AI/ML 大模型缓存与权重..." -ForegroundColor Gray
    & (Join-Path $scriptDir "scan_ai_models.ps1") -OutputManifest $manifestPath @extraArgs | Out-Null
    
    Write-Host "[6/7] 正在扫描国内通讯办公应用缓存 (微信 3.x/4.0, 企微, 飞书, 钉钉)..." -ForegroundColor Gray
    & (Join-Path $scriptDir "scan_im_office_residues.ps1") -OutputManifest $manifestPath @extraArgs | Out-Null
    
    Write-Host "[7/7] 正在扫描沉睡工程构建产物 (node_modules, target)..." -ForegroundColor Gray
    & (Join-Path $scriptDir "scan_dev_artifacts.ps1") -DaysInactive 60 -OutputManifest $manifestPath @extraArgs | Out-Null
    
    Write-Host "✅ 全流程只读体检完成！清单已同步至: $manifestPath" -ForegroundColor Green
}

function Show-ManifestList {
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        Write-Host "⚠️ 清单文件不存在，请先执行选项 [1] 进行全流程体检。" -ForegroundColor Yellow
        return
    }
    
    $mText = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8
    $itemBlocks = [regex]::Matches($mText, '(?ms)^-\s*(?:(?<chk>\[[ xX]\])\s*)?(?:[🟢🟡🟠🔴]\s*)?(?:~~)?\*\*\[(?<id>[A-Z]+-\d+)\](?:\*\*)?(?:~~)?(?:\s*\*\((?<cleaned>已成功清理)\)\*)?\s*(?<titleLine>[^\r\n]+)(?<body>.*?)(?=(?:\r?\n-\s|\r?\n##|\Z))')
    
    Write-Host "`n=== 当前候选清单 ($($itemBlocks.Count) 项) ===" -ForegroundColor Cyan
    Write-Host ("{0,-10} {1,-8} {2,-12} {3}" -f "编号", "勾选状态", "大小", "项目名称") -ForegroundColor Gray
    Write-Host "-------------------------------------------------------------" -ForegroundColor Gray
    foreach ($b in $itemBlocks) {
        $cid = $b.Groups['id'].Value
        $chk = if ($b.Groups['chk'].Success) { $b.Groups['chk'].Value } else { "[ ]" }
        $body = $b.Groups['body'].Value
        $sz = if ($body -match '大小[：:]\s*(?<s>[0-9.]+\s*(?:MB|GB))') { $Matches['s'] } else { "0 MB" }
        $nm = ($b.Groups['titleLine'].Value -replace '\*\*$', '' -replace '【.*】', '').Trim()
        $isClean = ($b.Groups['cleaned'].Success -or $b.Value -match "~~" -or $b.Value -match "已成功清理")
        $statusStr = if ($isClean) { "已清理" } elseif ($chk -match 'x|X') { "[x] 已勾选" } else { "[ ] 未勾选" }
        Write-Host ("{0,-10} {1,-8} {2,-12} {3}" -f $cid, $statusStr, $sz, $nm)
    }
    Write-Host "-------------------------------------------------------------" -ForegroundColor Gray
}

function Run-GuardedClean {
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        Write-Host "⚠️ 清单文件不存在，请先执行选项 [1] 进行体检建档。" -ForegroundColor Yellow
        return
    }
    
    $mText = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8
    $itemBlocks = [regex]::Matches($mText, '(?ms)^-\s*\[[xX]\]\s*(?:[🟢🟡🟠🔴]\s*)?(?:~~)?\*\*\[(?<id>[A-Z]+-\d+)\](?:\*\*)?(?:~~)?(?:\s*\*\((?<cleaned>已成功清理)\)\*)?\s*(?<titleLine>[^\r\n]+)(?<body>.*?)(?=(?:\r?\n-\s|\r?\n##|\Z))')
    
    $pendingChecked = @()
    foreach ($b in $itemBlocks) {
        $isClean = ($b.Groups['cleaned'].Success -or $b.Value -match "~~" -or $b.Value -match "已成功清理")
        if (-not $isClean) {
            $pendingChecked += $b
        }
    }
    
    $targetIdList = $null
    if ($pendingChecked.Count -eq 0) {
        Write-Host "`nℹ️ 当前清单中没有勾选为 - [x] 且未清理的待处理项。" -ForegroundColor Yellow
        Write-Host "💡 提示：您可以直接打开本地清单文件将目标项改为 - [x]，或在下方输入需要清理的编号。" -ForegroundColor Gray
        $manualIds = Read-Host "请输入需要清理的 ID 列表（以逗号分隔，如 RES-001,DEV-001；按 Enter 返回）"
        if ($null -eq $manualIds -or $manualIds.Trim() -eq "") {
            Write-Host "已取消清理操作。" -ForegroundColor Gray
            return
        }
        $targetIdList = $manualIds.Trim()
    } else {
        Write-Host "`n=== 检测到以下已在清单中勾选的待清理项 ($($pendingChecked.Count) 项) ===" -ForegroundColor Cyan
        foreach ($p in $pendingChecked) {
            $body = $p.Groups['body'].Value
            $sz = if ($body -match '大小[：:]\s*(?<s>[0-9.]+\s*(?:MB|GB))') { $Matches['s'] } else { "0 MB" }
            $nm = ($p.Groups['titleLine'].Value -replace '\*\*$', '' -replace '【.*】', '').Trim()
            Write-Host " * [$($p.Groups['id'].Value)] $nm ($sz)" -ForegroundColor White
        }
    }
    
    # 严格风险分级评估：检测是否包含 Tier 2 (DEV-xxx, AI-xxx)
    $hasTier2 = ($pendingChecked | Where-Object { $_.Groups['id'].Value -match '^(DEV|AI)-' }) -or 
                ($targetIdList -and ($targetIdList -match '(DEV|AI)-'))
    
    Write-Host "`n⚠️ 【安全红线确认】" -ForegroundColor Yellow
    if ($hasTier2) {
        Write-Host "检测到待清理项包含 Tier 2 (开发者构建产物 / AI模型 / 微信历史文档)。" -ForegroundColor Red
        Write-Host "为杜绝误删，必须在键盘输入全大写 'CONFIRM' 方可执行！" -ForegroundColor Yellow
        $confirm = Read-Host "请输入 CONFIRM 确认执行（输入其他任意内容取消）"
        if ($confirm -cne "CONFIRM") {
            Write-Host "安全熔断：未输入正确确认码，操作已安全取消。" -ForegroundColor Gray
            return
        }
    } else {
        $confirm = Read-Host "请输入 Y 确认执行清理（输入其他任意内容取消）"
        if ($confirm -ne "Y" -and $confirm -ne "y") {
            Write-Host "操作已安全取消。" -ForegroundColor Gray
            return
        }
    }
    
    Write-Host "`n>>> 正在启动安全清理引擎..." -ForegroundColor Cyan
    $extraArgs = @{}
    if ($MockRoot) { $extraArgs['MockRoot'] = $MockRoot }
    
    if ($targetIdList) {
        & (Join-Path $scriptDir "clean_selected_residues.ps1") -ManifestPath $manifestPath -TargetIds ($targetIdList -split ",") -Force @extraArgs
    } else {
        & (Join-Path $scriptDir "clean_selected_residues.ps1") -ManifestPath $manifestPath -FromManifest -Force @extraArgs
    }
    
    Write-Host "`n>>> 正在自动生成最新战报..." -ForegroundColor Cyan
    & (Join-Path $scriptDir "export_dashboard.ps1") -ManifestPath $manifestPath @extraArgs | Out-Null
    Write-Host "✅ 清理完成，战报已同步刷新！" -ForegroundColor Green
}

# Console interactive loop with non-interactive protection
while ($true) {
    Show-Header
    if ($NonInteractive -or [Console]::IsInputRedirected) {
        Write-Host "[NON-INTERACTIVE] Non-interactive console detected. Exiting cleanly." -ForegroundColor Yellow
        exit 0
    }
    
    $choice = Read-Host "请选择操作序号 [1-6]"
    if ($null -eq $choice -or $choice.Trim() -eq "" -or $choice.Trim() -eq "6") {
        Write-Host "`n感谢使用 Save-My-Disk！再见。" -ForegroundColor Green
        break
    }
    
    switch ($choice.Trim()) {
        "1" { Run-FullAudit }
        "2" {
            $extraArgs = @{}
            if ($MockRoot) { $extraArgs['MockRoot'] = $MockRoot }
            & (Join-Path $scriptDir "export_dashboard.ps1") -ManifestPath $manifestPath -Open @extraArgs
        }
        "3" { Show-ManifestList }
        "4" { Run-GuardedClean }
        "5" {
            $extraArgs = @{}
            if ($MockRoot) { $extraArgs['MockRoot'] = $MockRoot }
            & (Join-Path $scriptDir "verify_health.ps1") @extraArgs
        }
        default {
            Write-Host "⚠️ 无效选项，请输入 1 到 6 之间的数字。" -ForegroundColor Yellow
        }
    }
    
    Write-Host "`n按 Enter 键返回主菜单..." -ForegroundColor Gray
    [void](Read-Host)
}
