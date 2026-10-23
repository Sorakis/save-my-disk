<#
.SYNOPSIS
    Scans for browser caches (Chrome, Edge, Brave, Firefox), GPU/DirectX shader caches, and Windows crash dumps.
.DESCRIPTION
    Non-invasive read-only scanner for save-my-disk (v0.5.2).
    Discovers V8/Wasm Code Cache, WebGL/WebGPU caches, DirectX/NVIDIA shader caches, and crash minidumps.
    Strictly enforces Tier 4 absolute immunity for all browser credentials, cookies, bookmarks, and history.
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

$cachesFound = @()
$counter = 1

function Get-SafeFolderMetrics {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $files = Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue
    $totalBytes = ($files | Measure-Object -Property Length -Sum).Sum
    if (-not $totalBytes) { $totalBytes = 0 }
    return [PSCustomObject]@{
        Path = $Path
        FileCount = $files.Count
        SizeMB = [math]::Round($totalBytes / 1MB, 2)
    }
}

# Strict whitelist candidate probe function for Chromium profiles
function Probe-ChromiumProfile {
    param(
        [string]$BrowserName,
        [string]$ProfileName,
        [string]$ProfilePath
    )

    if (-not (Test-Path -LiteralPath $ProfilePath)) { return }

    # Whitelist 1: Code Cache (V8 JavaScript & WebAssembly bytecode)
    $codeCachePath = Join-Path $ProfilePath "Code Cache"
    $m = Get-SafeFolderMetrics -Path $codeCachePath
    if ($m -and ($m.SizeMB -gt 20 -or $MockRoot)) {
        $script:cachesFound += [PSCustomObject]@{
            ID = "BRW-" + ($script:counter++).ToString("D3")
            Tier = 1
            App = $BrowserName
            Category = "Browser Code Cache"
            Name = "$BrowserName ($ProfileName) 脚本运行与编译缓存 (Code Cache)"
            Path = $codeCachePath
            SizeMB = $m.SizeMB
            FileCount = $m.FileCount
            RiskLevel = "Zero"
            Description = "浏览器编译网页 JavaScript 与 WebAssembly 生成的本地 JIT 字节码缓存。清空完全不影响个人密码、书签与登录状态，下次访问网站时会自动重新编译生成。"
        }
    }

    # Whitelist 2: GPUCache (WebGL & Canvas Shaders)
    $gpuCachePath = Join-Path $ProfilePath "GPUCache"
    $m = Get-SafeFolderMetrics -Path $gpuCachePath
    if ($m -and ($m.SizeMB -gt 15 -or $MockRoot)) {
        $script:cachesFound += [PSCustomObject]@{
            ID = "BRW-" + ($script:counter++).ToString("D3")
            Tier = 1
            App = $BrowserName
            Category = "Browser GPU Cache"
            Name = "$BrowserName ($ProfileName) 页面渲染与图形着色缓存 (GPUCache)"
            Path = $gpuCachePath
            SizeMB = $m.SizeMB
            FileCount = $m.FileCount
            RiskLevel = "Zero"
            Description = "浏览器渲染复杂网页图表、Canvas 与 WebGL 积累的 GPU 编译着色器缓存。100% 零风险清理。"
        }
    }

    # Whitelist 3: DawnCache (WebGPU Compute Shaders)
    $dawnCachePath = Join-Path $ProfilePath "DawnCache"
    $m = Get-SafeFolderMetrics -Path $dawnCachePath
    if ($m -and ($m.SizeMB -gt 15 -or $MockRoot)) {
        $script:cachesFound += [PSCustomObject]@{
            ID = "BRW-" + ($script:counter++).ToString("D3")
            Tier = 1
            App = $BrowserName
            Category = "Browser WebGPU Cache"
            Name = "$BrowserName ($ProfileName) WebGPU 计算管线缓存 (DawnCache)"
            Path = $dawnCachePath
            SizeMB = $m.SizeMB
            FileCount = $m.FileCount
            RiskLevel = "Zero"
            Description = "现代化 WebGPU 渲染管线积累的计算与渲染着色器缓存。100% 零风险清理。"
        }
    }

    # Whitelist 4: Cache (HTTP Cache / Cache_Data)
    $httpCachePath = Join-Path $ProfilePath "Cache"
    $m = Get-SafeFolderMetrics -Path $httpCachePath
    if ($m -and ($m.SizeMB -gt 50 -or $MockRoot)) {
        $script:cachesFound += [PSCustomObject]@{
            ID = "BRW-" + ($script:counter++).ToString("D3")
            Tier = 1
            App = $BrowserName
            Category = "Browser HTTP Cache"
            Name = "$BrowserName ($ProfileName) 离线静态资源网络缓存 (Cache)"
            Path = $httpCachePath
            SizeMB = $m.SizeMB
            FileCount = $m.FileCount
            RiskLevel = "Zero"
            Description = "浏览网页下载的静态图片、CSS 样式与静态包缓存。清空不影响用户个人凭据与 Cookie 状态。"
        }
    }
}

# =========================================================
# 1. Chromium Browsers (Google Chrome, Edge, Brave)
# =========================================================
$chromiumBrowsers = @(
    @{ Name = "Google Chrome"; RelPath = "Google\Chrome\User Data" },
    @{ Name = "Microsoft Edge"; RelPath = "Microsoft\Edge\User Data" },
    @{ Name = "Brave Browser"; RelPath = "BraveSoftware\Brave-Browser\User Data" }
)

foreach ($b in $chromiumBrowsers) {
    $uDataPath = if ($MockRoot) {
        Join-Path $MockRoot "AppData\Local\$($b.RelPath)"
    } else {
        Join-Path $env:LOCALAPPDATA $b.RelPath
    }

    if (Test-Path -LiteralPath $uDataPath) {
        # 1.1 Root-level browser shared caches
        $sharedShader = Join-Path $uDataPath "GrShaderCache"
        $m = Get-SafeFolderMetrics -Path $sharedShader
        if ($m -and ($m.SizeMB -gt 15 -or $MockRoot)) {
            $cachesFound += [PSCustomObject]@{
                ID = "BRW-" + ($counter++).ToString("D3")
                Tier = 1
                App = $b.Name
                Category = "Browser Shared Shader"
                Name = "$($b.Name) 全局图形渲染共享缓存 (GrShaderCache)"
                Path = $sharedShader
                SizeMB = $m.SizeMB
                FileCount = $m.FileCount
                RiskLevel = "Zero"
                Description = "Skia 图形引擎在多进程间共享的着色器缓存。100% 零风险。"
            }
        }

        $crashpadPath = Join-Path $uDataPath "Crashpad\reports"
        $m = Get-SafeFolderMetrics -Path $crashpadPath
        if ($m -and ($m.SizeMB -gt 5 -or $MockRoot)) {
            $cachesFound += [PSCustomObject]@{
                ID = "BRW-" + ($counter++).ToString("D3")
                Tier = 1
                App = $b.Name
                Category = "Browser Crashpad Reports"
                Name = "$($b.Name) 历史崩溃转储日志 (Crashpad)"
                Path = $crashpadPath
                SizeMB = $m.SizeMB
                FileCount = $m.FileCount
                RiskLevel = "Zero"
                Description = "浏览器崩溃时记录的 minidump 文件。100% 零风险清理。"
            }
        }

        # 1.2 Multi-Profile Whitelist Probing
        $profiles = Get-ChildItem -LiteralPath $uDataPath -Directory -Force -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -eq "Default" -or $_.Name -like "Profile *"
        }

        foreach ($prof in $profiles) {
            Probe-ChromiumProfile -BrowserName $b.Name -ProfileName $prof.Name -ProfilePath $prof.FullName
        }
    }
}

# =========================================================
# 2. Mozilla Firefox Profiles (Local Caches Only)
# =========================================================
$ffLocalRoot = if ($MockRoot) {
    Join-Path $MockRoot "AppData\Local\Mozilla\Firefox\Profiles"
} else {
    Join-Path $env:LOCALAPPDATA "Mozilla\Firefox\Profiles"
}

if (Test-Path -LiteralPath $ffLocalRoot) {
    $ffProfiles = Get-ChildItem -LiteralPath $ffLocalRoot -Directory -Force -ErrorAction SilentlyContinue
    foreach ($prof in $ffProfiles) {
        $c2Path = Join-Path $prof.FullName "cache2\entries"
        $m = Get-SafeFolderMetrics -Path $c2Path
        if ($m -and ($m.SizeMB -gt 30 -or $MockRoot)) {
            $cachesFound += [PSCustomObject]@{
                ID = "BRW-" + ($counter++).ToString("D3")
                Tier = 1
                App = "Mozilla Firefox"
                Category = "Firefox Cache2"
                Name = "Mozilla Firefox ($($prof.Name)) 本地网络缓存 (cache2)"
                Path = $c2Path
                SizeMB = $m.SizeMB
                FileCount = $m.FileCount
                RiskLevel = "Zero"
                Description = "Firefox 存储在 LocalAppData 的纯网页缓存。密码与书签完整存储在 Roaming，完全不受影响。"
            }
        }

        $sCachePath = Join-Path $prof.FullName "startupCache"
        $m = Get-SafeFolderMetrics -Path $sCachePath
        if ($m -and ($m.SizeMB -gt 15 -or $MockRoot)) {
            $cachesFound += [PSCustomObject]@{
                ID = "BRW-" + ($counter++).ToString("D3")
                Tier = 1
                App = "Mozilla Firefox"
                Category = "Firefox Startup Cache"
                Name = "Mozilla Firefox ($($prof.Name)) 启动执行缓存 (startupCache)"
                Path = $sCachePath
                SizeMB = $m.SizeMB
                FileCount = $m.FileCount
                RiskLevel = "Zero"
                Description = "Firefox 启动加速脚本缓存。删除后在下次启动时自动刷新重建。"
            }
        }
    }
}

# =========================================================
# 3. DirectX & GPU Vendor Shader Caches
# =========================================================
$shaderTargets = @(
    @{ Name = "Windows DirectX 着色器缓存 (D3DSCache)"; RelPath = "D3DSCache"; Cat = "DirectX Shader Cache" },
    @{ Name = "NVIDIA DirectX 11/12 驱动着色器缓存 (DXCache)"; RelPath = "NVIDIA\DXCache"; Cat = "NVIDIA DXCache" },
    @{ Name = "NVIDIA OpenGL/Vulkan 着色器缓存 (GLCache)"; RelPath = "NVIDIA\GLCache"; Cat = "NVIDIA GLCache" },
    @{ Name = "AMD 驱动着色器缓存 (DxCache)"; RelPath = "AMD\DxCache"; Cat = "AMD Shader Cache" },
    @{ Name = "Intel 核心显卡着色器缓存 (ShaderCache)"; RelPath = "Intel\ShaderCache"; Cat = "Intel Shader Cache" }
)

foreach ($st in $shaderTargets) {
    $sPath = if ($MockRoot) {
        Join-Path $MockRoot "AppData\Local\$($st.RelPath)"
    } else {
        Join-Path $env:LOCALAPPDATA $st.RelPath
    }

    if (Test-Path -LiteralPath $sPath) {
        $m = Get-SafeFolderMetrics -Path $sPath
        if ($m -and ($m.SizeMB -gt 30 -or $MockRoot)) {
            $cachesFound += [PSCustomObject]@{
                ID = "BRW-" + ($counter++).ToString("D3")
                Tier = 1
                App = "Graphics Driver"
                Category = $st.Cat
                Name = $st.Name
                Path = $sPath
                SizeMB = $m.SizeMB
                FileCount = $m.FileCount
                RiskLevel = "Zero"
                Description = "显卡驱动与 DirectX 编译积累的 GPU 机器码缓存。Windows 官方 cleanmgr 认证零风险项，清理后若再次运行相应游戏，显卡驱动会自动重新编译所需着色器。"
            }
        }
    }
}

# =========================================================
# 4. Windows Crash Dumps & Diagnostics
# =========================================================
$crashDumpsPath = if ($MockRoot) {
    Join-Path $MockRoot "AppData\Local\CrashDumps"
} else {
    Join-Path $env:LOCALAPPDATA "CrashDumps"
}

if (Test-Path -LiteralPath $crashDumpsPath) {
    $m = Get-SafeFolderMetrics -Path $crashDumpsPath
    if ($m -and ($m.SizeMB -gt 10 -or $MockRoot)) {
        $cachesFound += [PSCustomObject]@{
            ID = "BRW-" + ($counter++).ToString("D3")
            Tier = 1
            App = "Windows System"
            Category = "Windows Crash Dumps"
            Name = "Windows 用户层应用程序崩溃转储 (CrashDumps)"
            Path = $crashDumpsPath
            SizeMB = $m.SizeMB
            FileCount = $m.FileCount
            RiskLevel = "Zero"
            Description = "应用程序异常闪退时由系统自动生成的临时内存转储文件 (*.dmp)。不影响任何软件正常功能，100% 零风险清理。"
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

    $t1Md = ""
    if ($cachesFound.Count -gt 0) {
        $sb = [System.Text.StringBuilder]::new()
        [void]$sb.AppendLine("### 🌐 浏览器与显卡 GPU 着色器深度缓存 (Browser Code Cache & DirectX ShaderCache)")
        foreach ($item in $cachesFound) {
            [void]$sb.AppendLine("- [ ] **[$($item.ID)] $($item.Name)** 【零风险 - 纯编译缓存/转储】")
            [void]$sb.AppendLine('  * 路径：`' + $item.Path + '`')
            [void]$sb.AppendLine("  * 大小：$($item.SizeMB) MB ($($item.FileCount) 个文件)")
            [void]$sb.AppendLine("  * 说明：$($item.Description)")
            [void]$sb.AppendLine("")
        }
        $t1Md = $sb.ToString()
    }

    if ($manifestContent -match '<!-- TIER1_BROWSER_SYSTEM_PLACEHOLDER -->') {
        $manifestContent = $manifestContent.Replace('<!-- TIER1_BROWSER_SYSTEM_PLACEHOLDER -->', $t1Md)
    }

    [System.IO.File]::WriteAllText($OutputManifest, $manifestContent, (New-Object System.Text.UTF8Encoding($true)))
}

if ($Json) {
    if ($cachesFound.Count -eq 0) {
        Write-Output "[]"
    } else {
        $cachesFound | ConvertTo-Json -Depth 5
    }
} else {
    Write-Host "`n=== BROWSER CACHES & GPU SHADER CACHES AUDIT ===" -ForegroundColor Yellow
    if ($cachesFound.Count -eq 0) {
        Write-Host "No heavy browser or GPU shader caches detected exceeding threshold." -ForegroundColor Green
    } else {
        $cachesFound | Select-Object ID, App, Name, SizeMB, FileCount | Format-Table -AutoSize
        $totalMB = ($cachesFound | Measure-Object -Property SizeMB -Sum).Sum
        Write-Host "Total Reclaimable Browser/Shader Space: $totalMB MB (~$([math]::Round($totalMB / 1024, 2)) GB)" -ForegroundColor Cyan
    }
}
