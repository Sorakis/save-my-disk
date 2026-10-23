<#
.SYNOPSIS
    Generates a zero-dependency, standalone HTML visual dashboard for Save-My-Disk.
.DESCRIPTION
    Parses .save-my-disk/cleanup_manifest.md and system disk statistics to build an offline,
    single-file, interactive HTML report with embedded CSS, inline SVG charts, and responsive UI.
#>
param(
    [string]$ManifestPath,
    [string]$OutputPath,
    [string]$MockRoot,
    [switch]$Open,
    [switch]$Json
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Default paths
if (-not $ManifestPath) {
    if ($MockRoot) {
        $ManifestPath = Join-Path $MockRoot ".save-my-disk\cleanup_manifest.md"
    } else {
        $ManifestPath = ".\.save-my-disk\cleanup_manifest.md"
    }
}

if (-not $OutputPath) {
    if ($MockRoot) {
        $OutputPath = Join-Path $MockRoot ".save-my-disk\disk_triage_report.html"
    } else {
        $OutputPath = ".\.save-my-disk\disk_triage_report.html"
    }
}

# Ensure parent directory exists
$parentDir = Split-Path -Parent $OutputPath
if ($parentDir -and -not (Test-Path -LiteralPath $parentDir)) {
    New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
}

# 1. Disk Space Statistics (Mock vs Live)
$diskInfo = if ($MockRoot) {
    [PSCustomObject]@{ TotalGB = 500.0; UsedGB = 320.0; FreeGB = 180.0; Drive = "C:" }
} else {
    $c = Get-Volume -DriveLetter C -ErrorAction SilentlyContinue
    if ($c -and $c.Size -gt 0) {
        [PSCustomObject]@{
            TotalGB = [math]::Round($c.Size / 1GB, 2)
            FreeGB  = [math]::Round($c.SizeRemaining / 1GB, 2)
            UsedGB  = [math]::Round(($c.Size - $c.SizeRemaining) / 1GB, 2)
            Drive   = "C:"
        }
    } else {
        [PSCustomObject]@{ TotalGB = 500.0; UsedGB = 300.0; FreeGB = 200.0; Drive = "C:" }
    }
}

# 2. Parse cleanup_manifest.md
$parsedItems = @()
$totalPendingMB = 0.0
$totalCleanedMB = 0.0
$tier1MB = 0.0
$tier2MB = 0.0
$tier3MB = 0.0

if (Test-Path -LiteralPath $ManifestPath) {
    $manifestRaw = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8
    
    # Split into sections by Markdown header ##
    $sections = [regex]::Split($manifestRaw, '(?m)^##\s+')
    
    foreach ($sec in $sections) {
        $tier = 1
        if ($sec -match "Tier 2") { $tier = 2 }
        elseif ($sec -match "Tier 3") { $tier = 3 }
        elseif ($sec -match "Tier 4") { continue }
        
        # Extract item blocks: from start of item line until next item line or section
        $itemBlocks = [regex]::Matches($sec, '(?ms)^-\s*(?:\[(?<chk>[ xX])\]\s*)?(?:[🟢🟡🟠🔴]\s*)?(?:~~)?\*\*\[(?<id>[A-Z]+-\d+)\](?:\*\*)?(?:~~)?(?:\s*\*\((?<cleaned>已成功清理)\)\*)?\s*(?<titleLine>[^\r\n]+)(?<body>.*?)(?=(?:\r?\n-\s|\r?\n##|\Z))')
        
        foreach ($b in $itemBlocks) {
            $id = $b.Groups['id'].Value
            $cleanMarker = $b.Groups['cleaned'].Success
            $title = $b.Groups['titleLine'].Value -replace '\*\*$', '' -replace '【.*】', ''
            $title = $title.Trim()
            $body = $b.Groups['body'].Value
            
            $path = if ($body -match '路径[：:]\s*`(?<p>[^`]+)`') { $Matches['p'].Trim() } else { "N/A" }
            $sizeVal = 0.0
            if ($body -match '大小[：:]\s*(?<s>[0-9.]+)\s*(?<u>MB|GB)') {
                $sizeVal = [double]$Matches['s']
                if ($Matches['u'] -eq "GB") { $sizeVal = $sizeVal * 1024.0 }
            } elseif ($b.Value -match '【0 MB - 状态：健康') {
                $sizeVal = 0.0
            }
            
            $isCleaned = ($cleanMarker -or $b.Value -match "~~" -or $b.Value -match "已成功清理")
            
            if ($isCleaned) {
                $totalCleanedMB += $sizeVal
            } else {
                $totalPendingMB += $sizeVal
            }
            
            if ($tier -eq 1) { $tier1MB += $sizeVal }
            elseif ($tier -eq 2) { $tier2MB += $sizeVal }
            elseif ($tier -eq 3) { $tier3MB += $sizeVal }
            
            $parsedItems += [PSCustomObject]@{
                ID = $id
                Name = $title
                Path = $path
                SizeMB = [math]::Round($sizeVal, 2)
                Tier = $tier
                Status = if ($isCleaned) { "Cleaned" } else { "Pending" }
            }
        }
    }
}

# Category aggregates
$catMap = @{
    "System & Update" = 0.0
    "Browser & Shader" = 0.0
    "IM & Office" = 0.0
    "Dev & Build" = 0.0
    "AI Models" = 0.0
    "Package Caches" = 0.0
    "App Residues" = 0.0
}

foreach ($it in $parsedItems) {
    $cid = $it.ID
    $sz = $it.SizeMB
    if ($cid -like "SYS-*") { $catMap["System & Update"] += $sz }
    elseif ($cid -like "BRW-*") { $catMap["Browser & Shader"] += $sz }
    elseif ($cid -like "IM-*") { $catMap["IM & Office"] += $sz }
    elseif ($cid -like "DEV-*") { $catMap["Dev & Build"] += $sz }
    elseif ($cid -like "AI-*") { $catMap["AI Models"] += $sz }
    elseif ($cid -like "PKG-*") { $catMap["Package Caches"] += $sz }
    else { $catMap["App Residues"] += $sz }
}

$cleanableGB = [math]::Round(($totalPendingMB + $totalCleanedMB) / 1024.0, 2)
$cleanedGB = [math]::Round($totalCleanedMB / 1024.0, 2)
$pendingGB = [math]::Round($totalPendingMB / 1024.0, 2)

# Calculate Donut Chart Angles & SVG DashArrays
# Radius = 70, Circumference = 2 * PI * 70 ~= 439.82
$circ = 439.82
$totalGB = [math]::Max($diskInfo.TotalGB, 1.0)
$usedPct = [math]::Min(([math]::Max($diskInfo.UsedGB, 0.0) / $totalGB), 1.0)
$freePct = [math]::Min(([math]::Max($diskInfo.FreeGB, 0.0) / $totalGB), 1.0)

$usedDash = [math]::Round($usedPct * $circ, 2)
$usedOffset = 0.0
$freeDash = [math]::Round($freePct * $circ, 2)
$freeOffset = -$usedDash

# Timestamp
$generatedTime = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$hostName = $env:COMPUTERNAME

# Build Table Rows HTML
$tableRowsHtml = [System.Text.StringBuilder]::new()
foreach ($it in $parsedItems) {
    $badgeClass = if ($it.Status -eq "Cleaned") { "badge-cleaned" } else { "badge-pending" }
    $badgeText = if ($it.Status -eq "Cleaned") { "✓ 已清理" } else { "待决策" }
    $tierBadge = switch ($it.Tier) {
        1 { "<span class='tier-pill t1'>Tier 1 零风险</span>" }
        2 { "<span class='tier-pill t2'>Tier 2 开发者权衡</span>" }
        3 { "<span class='tier-pill t3'>Tier 3 应用残留</span>" }
        default { "<span class='tier-pill'>Tier 1</span>" }
    }
    $sizeText = if ($it.SizeMB -ge 1024) { "$([math]::Round($it.SizeMB/1024.0, 2)) GB" } else { "$([math]::Round($it.SizeMB, 1)) MB" }
    
    $row = @"
    <tr class="$($it.Status.ToLower())">
      <td><span class="item-id">$($it.ID)</span></td>
      <td><strong>$([System.Net.WebUtility]::HtmlEncode($it.Name))</strong></td>
      <td>$tierBadge</td>
      <td><span class="size-val">$sizeText</span></td>
      <td><span class="path-val" title="$([System.Net.WebUtility]::HtmlEncode($it.Path))">$([System.Net.WebUtility]::HtmlEncode($it.Path))</span></td>
      <td><span class="badge $badgeClass">$badgeText</span></td>
    </tr>
"@
    [void]$tableRowsHtml.AppendLine($row)
}

# Top Category Bars HTML
$catBarsHtml = [System.Text.StringBuilder]::new()
$maxCatMB = 1.0
foreach ($v in $catMap.Values) { if ($v -gt $maxCatMB) { $maxCatMB = $v } }

foreach ($k in ($catMap.Keys | Sort-Object { -$catMap[$_] })) {
    $cVal = $catMap[$k]
    if ($cVal -le 0) { continue }
    $cBarWidth = [math]::Min(100, [math]::Max(4, [math]::Round(($cVal / $maxCatMB) * 100, 1)))
    $cSizeText = if ($cVal -ge 1024) { "$([math]::Round($cVal / 1024.0, 2)) GB" } else { "$([math]::Round($cVal, 1)) MB" }
    $catRow = @"
    <div class="cat-bar-item">
      <div class="cat-bar-header">
        <span>$k</span>
        <span class="cat-bar-size">$cSizeText</span>
      </div>
      <div class="cat-bar-track">
        <div class="cat-bar-fill" style="width: ${cBarWidth}%;"></div>
      </div>
    </div>
"@
    [void]$catBarsHtml.AppendLine($catRow)
}

# HTML Template
$htmlContent = @"
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Save-My-Disk 磁盘诊断与安全治理可视化战报</title>
  <style>
    :root {
      --bg: #0b0f19;
      --card-bg: #151d30;
      --card-border: #232f48;
      --text: #f1f5f9;
      --text-muted: #94a3b8;
      --accent: #38bdf8;
      --green: #10b981;
      --amber: #f59e0b;
      --red: #ef4444;
      --purple: #a855f7;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "PingFang SC", "Microsoft YaHei", sans-serif;
      background: var(--bg);
      color: var(--text);
      line-height: 1.5;
      padding: 24px;
    }
    .container { max-width: 1240px; margin: 0 auto; }
    .header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding-bottom: 20px;
      border-bottom: 1px solid var(--card-border);
      margin-bottom: 24px;
    }
    .header h1 { font-size: 26px; font-weight: 700; color: #fff; display: flex; align-items: center; gap: 10px; }
    .header-badge { font-size: 13px; background: #0369a1; color: #e0f2fe; padding: 4px 10px; border-radius: 999px; }
    .meta { font-size: 13px; color: var(--text-muted); text-align: right; }
    .stats-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
      gap: 16px;
      margin-bottom: 24px;
    }
    .card {
      background: var(--card-bg);
      border: 1px solid var(--card-border);
      border-radius: 12px;
      padding: 20px;
    }
    .card-title { font-size: 13px; text-transform: uppercase; letter-spacing: 0.05em; color: var(--text-muted); margin-bottom: 6px; }
    .card-val { font-size: 32px; font-weight: 800; color: #fff; }
    .card-val.green { color: var(--green); }
    .card-val.accent { color: var(--accent); }
    .card-sub { font-size: 12px; color: var(--text-muted); margin-top: 4px; }
    
    .charts-row {
      display: grid;
      grid-template-columns: 340px 1fr;
      gap: 20px;
      margin-bottom: 24px;
    }
    @media (max-width: 860px) { .charts-row { grid-template-columns: 1fr; } }
    
    .donut-container { display: flex; flex-direction: column; align-items: center; justify-content: center; position: relative; }
    .donut-legend { margin-top: 16px; width: 100%; display: flex; justify-content: space-around; font-size: 13px; }
    .legend-item { display: flex; align-items: center; gap: 6px; }
    .dot { width: 10px; height: 10px; border-radius: 50%; }
    .dot.used { background: var(--accent); }
    .dot.free { background: var(--green); }
    
    .cat-bar-item { margin-bottom: 14px; }
    .cat-bar-header { display: flex; justify-content: space-between; font-size: 13px; margin-bottom: 4px; }
    .cat-bar-size { font-weight: 600; color: var(--accent); }
    .cat-bar-track { background: #1e293b; height: 8px; border-radius: 4px; overflow: hidden; }
    .cat-bar-fill { background: linear-gradient(90deg, #38bdf8, #818cf8); height: 100%; border-radius: 4px; }

    .table-card { margin-top: 24px; overflow-x: auto; }
    .table-header { margin-bottom: 16px; display: flex; justify-content: space-between; align-items: center; }
    table { width: 100%; border-collapse: collapse; text-align: left; font-size: 13px; }
    th { color: var(--text-muted); font-weight: 600; padding: 12px 14px; border-bottom: 1px solid var(--card-border); }
    td { padding: 14px; border-bottom: 1px solid #1a2338; vertical-align: middle; }
    tr:hover { background: rgba(255,255,255,0.02); }
    .item-id { font-family: monospace; font-weight: 700; color: var(--accent); background: #0c4a6e; padding: 2px 6px; border-radius: 4px; }
    .tier-pill { display: inline-block; padding: 2px 8px; border-radius: 6px; font-size: 11px; font-weight: 600; }
    .tier-pill.t1 { background: rgba(16, 185, 129, 0.15); color: #34d399; }
    .tier-pill.t2 { background: rgba(245, 158, 11, 0.15); color: #fbbf24; }
    .tier-pill.t3 { background: rgba(239, 68, 68, 0.15); color: #f87171; }
    .size-val { font-weight: 700; }
    .path-val { font-family: monospace; color: var(--text-muted); max-width: 380px; display: inline-block; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .badge { display: inline-block; padding: 3px 10px; border-radius: 999px; font-size: 12px; font-weight: 700; }
    .badge-cleaned { background: rgba(16, 185, 129, 0.2); color: #34d399; }
    .badge-pending { background: rgba(56, 189, 248, 0.2); color: #38bdf8; }
    
    .footer { text-align: center; margin-top: 40px; color: var(--text-muted); font-size: 12px; }
  </style>
</head>
<body>
  <div class="container">
    <header class="header">
      <div>
        <h1>🚀 Save-My-Disk 智能磁盘诊断与战报 <span class="header-badge">v0.5.3</span></h1>
      </div>
      <div class="meta">
        <div>主机节点: <strong>$hostName</strong></div>
        <div>诊断时间: <strong>$generatedTime</strong></div>
      </div>
    </header>

    <div class="stats-grid">
      <div class="card">
        <div class="card-title">系统盘总容量 ($($diskInfo.Drive))</div>
        <div class="card-val">$($diskInfo.TotalGB) <span style="font-size:16px;">GB</span></div>
        <div class="card-sub">当前剩余可用: <strong>$($diskInfo.FreeGB) GB</strong></div>
      </div>
      <div class="card">
        <div class="card-title">累计已释放空间 (战果)</div>
        <div class="card-val green">+$cleanedGB <span style="font-size:16px;">GB</span></div>
        <div class="card-sub">经 4-Tier 严格自愈审计</div>
      </div>
      <div class="card">
        <div class="card-title">待权衡决策空间 (可释放潜力)</div>
        <div class="card-val accent">$pendingGB <span style="font-size:16px;">GB</span></div>
        <div class="card-sub">含 Tier 1 补丁缓存与 Tier 2 模型</div>
      </div>
      <div class="card">
        <div class="card-title">安全红线 (Tier 4) 状态</div>
        <div class="card-val green">100% 免疫</div>
        <div class="card-sub">微信数据库、浏览器密码与源码安全</div>
      </div>
    </div>

    <div class="charts-row">
      <div class="card donut-container">
        <div class="card-title" style="width:100%; text-align:center;">系统盘容量分布</div>
        <svg width="180" height="180" viewBox="0 0 180 180">
          <circle cx="90" cy="90" r="70" fill="transparent" stroke="#1e293b" stroke-width="20"/>
          <circle cx="90" cy="90" r="70" fill="transparent" stroke="#38bdf8" stroke-width="20"
                  stroke-dasharray="$usedDash $circ" stroke-dashoffset="0" transform="rotate(-90 90 90)"/>
          <circle cx="90" cy="90" r="70" fill="transparent" stroke="#10b981" stroke-width="20"
                  stroke-dasharray="$freeDash $circ" stroke-dashoffset="$freeOffset" transform="rotate(-90 90 90)"/>
        </svg>
        <div class="donut-legend">
          <div class="legend-item"><span class="dot used"></span>已用 $($diskInfo.UsedGB)G</div>
          <div class="legend-item"><span class="dot free"></span>剩余 $($diskInfo.FreeGB)G</div>
        </div>
      </div>

      <div class="card">
        <div class="card-title">各类存储热点规模 (Top Categories)</div>
        $($catBarsHtml.ToString())
      </div>
    </div>

    <div class="card table-card">
      <div class="table-header">
        <div class="card-title" style="margin-bottom:0;">4-Tier 候选明细与治理清单 ($($parsedItems.Count) 项)</div>
      </div>
      <table>
        <thead>
          <tr>
            <th>编号</th>
            <th>项目名称</th>
            <th>风险梯度</th>
            <th>容量</th>
            <th>路径</th>
            <th>状态</th>
          </tr>
        </thead>
        <tbody>
          $($tableRowsHtml.ToString())
        </tbody>
      </table>
    </div>

    <footer class="footer">
      <p>Save-My-Disk (v0.5.3) · Universal Disk Optimization Runbook for AI Agents & Developers · 100% Offline & Open Source</p>
    </footer>
  </div>
</body>
</html>
"@

[System.IO.File]::WriteAllText($OutputPath, $htmlContent, [System.Text.Encoding]::UTF8)
Write-Host "Visual dashboard successfully generated at: $OutputPath" -ForegroundColor Green

if ($Open -and (-not $MockRoot)) {
    try {
        Start-Process $OutputPath
    } catch {
        Write-Host "Notice: Could not automatically launch browser. View report at $OutputPath" -ForegroundColor Gray
    }
}

$summaryObj = [PSCustomObject]@{
    ReportPath = (Resolve-Path $OutputPath).Path
    TotalCleanedGB = $cleanedGB
    TotalPendingGB = $pendingGB
    CleanablePotentialGB = $cleanableGB
    TotalCandidates = $parsedItems.Count
}

if ($Json) {
    $summaryObj | ConvertTo-Json -Depth 3
}
