<#
.SYNOPSIS
    Scans for global developer package manager caches: pip, npm, Conda, and Gradle.
.DESCRIPTION
    Non-invasive read-only scanner for save-my-disk (v0.4.0).
    Categorizes pip/npm/Conda tarballs into Tier 1 (Zero-Risk), and Conda unpacked/Gradle into Tier 2 (Tradeoff).
    Seamlessly integrates into cleanup_manifest.md via standard Tier placeholders.
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

# =========================================================
# 1. Python pip Cache (%LOCALAPPDATA%\pip\cache) [Tier 1]
# =========================================================
$pipCachePaths = @()
if ($MockRoot) {
    $pipCachePaths += Join-Path $MockRoot "AppData\Local\pip\cache"
} else {
    if ($env:PIP_CACHE_DIR -and (Test-Path -LiteralPath $env:PIP_CACHE_DIR)) {
        $pipCachePaths += $env:PIP_CACHE_DIR
    }
    $defPip = Join-Path $env:LOCALAPPDATA "pip\cache"
    if (Test-Path -LiteralPath $defPip) { $pipCachePaths += $defPip }
}
$pipCachePaths = $pipCachePaths | Select-Object -Unique

foreach ($pPath in $pipCachePaths) {
    if (Test-Path -LiteralPath $pPath) {
        $pFiles = Get-ChildItem -LiteralPath $pPath -Recurse -File -Force -ErrorAction SilentlyContinue
        $szMB = [math]::Round(($pFiles | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
        if ($szMB -gt 50 -or $MockRoot) {
            $cachesFound += [PSCustomObject]@{
                ID = "PKG-" + ($counter++).ToString("D3")
                Tier = 1
                Category = "pip Cache"
                Name = "Python pip 全局下载缓存"
                Path = $pPath
                SizeMB = $szMB
                FileCount = $pFiles.Count
                RiskLevel = "Zero"
                Description = "pip install 历史下载的 wheel 包与 HTTP 缓存。清空完全不影响已安装的 Python 库环境，下次安装相同包时会自动重新下载。"
            }
        }
    }
}

# =========================================================
# 2. Node.js npm Cache (%LOCALAPPDATA%\npm-cache) [Tier 1]
# =========================================================
$npmCachePaths = @()
if ($MockRoot) {
    $npmCachePaths += Join-Path $MockRoot "AppData\Local\npm-cache"
} else {
    $c1 = Join-Path $env:LOCALAPPDATA "npm-cache"
    $c2 = Join-Path $env:APPDATA "npm-cache"
    $c3 = Join-Path $env:USERPROFILE ".npm"
    foreach ($p in @($c1, $c2, $c3)) {
        if (Test-Path -LiteralPath $p) { $npmCachePaths += $p }
    }
}

foreach ($nPath in $npmCachePaths) {
    if (Test-Path -LiteralPath $nPath) {
        $nFiles = Get-ChildItem -LiteralPath $nPath -Recurse -File -Force -ErrorAction SilentlyContinue
        $szMB = [math]::Round(($nFiles | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
        if ($szMB -gt 50 -or $MockRoot) {
            $cachesFound += [PSCustomObject]@{
                ID = "PKG-" + ($counter++).ToString("D3")
                Tier = 1
                Category = "npm Cache"
                Name = "Node.js npm 全局离线缓存"
                Path = $nPath
                SizeMB = $szMB
                FileCount = $nFiles.Count
                RiskLevel = "Zero"
                Description = "npm install 历史下载的全局 tarball 离线包。清空完全不影响现有工程中已安装的 node_modules 模块。"
            }
        }
    }
}

# =========================================================
# 3. Conda Package Cache (pkgs) [Tier 1 & Tier 2]
# =========================================================
$condaPkgsPaths = @()
if ($MockRoot) {
    $condaPkgsPaths += Join-Path $MockRoot "miniconda3\pkgs"
} else {
    $cp1 = Join-Path $env:USERPROFILE "miniconda3\pkgs"
    $cp2 = Join-Path $env:USERPROFILE "anaconda3\pkgs"
    $cp3 = "C:\ProgramData\anaconda3\pkgs"
    foreach ($p in @($cp1, $cp2, $cp3)) {
        if (Test-Path -LiteralPath $p) { $condaPkgsPaths += $p }
    }
}

foreach ($cPath in $condaPkgsPaths) {
    if (Test-Path -LiteralPath $cPath) {
        # 3.1 Tier 1: Compressed tarballs (*.tar.bz2, *.conda) and index caches
        $tarFiles = Get-ChildItem -LiteralPath $cPath -File -Force -ErrorAction SilentlyContinue | Where-Object {
            $_.Extension -match '^\.(conda|bz2)$' -or $_.Name -like "*.tar.bz2"
        }
        $tarSizeMB = [math]::Round(($tarFiles | Measure-Object -Property Length -Sum).Sum / 1MB, 2)

        if ($tarSizeMB -gt 50 -or $MockRoot) {
            $cachesFound += [PSCustomObject]@{
                ID = "PKG-" + ($counter++).ToString("D3")
                Tier = 1
                Category = "Conda Tarballs"
                Name = "Conda 历史下载包归档 (*.tar.bz2 / *.conda)"
                Path = $cPath
                SizeMB = $tarSizeMB
                FileCount = $tarFiles.Count
                RiskLevel = "Zero"
                Description = "Conda 历史下载的压缩包源文件。已解压安装至虚拟环境中的包不再需要压缩源，删除后 100% 零风险（等效于 conda clean -t）。"
            }
        }

        # 3.2 Tier 2: Uncompressed package directories (tradeoff, managed by conda)
        $unpackedDirs = Get-ChildItem -LiteralPath $cPath -Directory -Force -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -ne "cache" -and $_.Name -ne "urls"
        }
        $unpackedFiles = Get-ChildItem -LiteralPath $cPath -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object {
            $_.FullName -notlike "$cPath\*.tar.bz2" -and $_.FullName -notlike "$cPath\*.conda"
        }
        $unpackedSizeMB = [math]::Round(($unpackedFiles | Measure-Object -Property Length -Sum).Sum / 1MB, 2)

        if ($unpackedSizeMB -gt 100 -or $MockRoot) {
            $cachesFound += [PSCustomObject]@{
                ID = "PKG-" + ($counter++).ToString("D3")
                Tier = 2
                Category = "Conda Unpacked Packages"
                Name = "Conda 已解压包共享缓存 (pkgs)"
                Path = $cPath
                SizeMB = $unpackedSizeMB
                FileCount = $unpackedFiles.Count
                RiskLevel = "Low-Decision"
                Description = "Conda 存放已解压硬链接包的目录。严禁直接物理删除整个目录（防止破坏虚拟环境硬链接）；推荐在终端使用 'conda clean -p -y' 安全剔除无引用的陈旧包。"
            }
        }
    }
}

# =========================================================
# 4. Gradle Cache (~/.gradle/caches) [Tier 2]
# =========================================================
$gradlePath = if ($MockRoot) {
    Join-Path $MockRoot ".gradle\caches"
} else {
    Join-Path $env:USERPROFILE ".gradle\caches"
}

if (Test-Path -LiteralPath $gradlePath) {
    $gFiles = Get-ChildItem -LiteralPath $gradlePath -Recurse -File -Force -ErrorAction SilentlyContinue
    $gSizeMB = [math]::Round(($gFiles | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
    if ($gSizeMB -gt 100 -or $MockRoot) {
        $cachesFound += [PSCustomObject]@{
            ID = "PKG-" + ($counter++).ToString("D3")
            Tier = 2
            Category = "Gradle Cache"
            Name = "Gradle 构建依赖与分发包缓存"
            Path = $gradlePath
            SizeMB = $gSizeMB
            FileCount = $gFiles.Count
            RiskLevel = "Low-Decision"
            Description = "Gradle 历史下载的第三方依赖 jar 包与 wrapper 分发包。清空后下次构建会自动重新拉取所需版本。"
        }
    }
}

# =========================================================
# 5. Integrate into cleanup_manifest.md (SSOT Anchor Injection)
# =========================================================
if ($OutputManifest -and (Test-Path -LiteralPath $OutputManifest)) {
    $manifestContent = Get-Content -LiteralPath $OutputManifest -Raw -Encoding UTF8

    # 5.1 Inject Tier 1 Package Caches
    $t1Pkg = $cachesFound | Where-Object { $_.Tier -eq 1 }
    $sb1 = [System.Text.StringBuilder]::new()
    [void]$sb1.AppendLine("### 📦 全局通用包管理器零风险缓存 (Tier 1: 随时可重下)")
    [void]$sb1.AppendLine("")
    if ($t1Pkg.Count -eq 0) {
        [void]$sb1.AppendLine("*（未发现体积膨胀的全局 pip 或 npm 离线安装缓存）*")
        [void]$sb1.AppendLine("")
    } else {
        foreach ($item in $t1Pkg) {
            [void]$sb1.AppendLine("- [ ] **[" + $item.ID + "] " + $item.Name + "** 【零风险 - 纯废弃】")
            [void]$sb1.AppendLine('  * 路径：`' + $item.Path + '`')
            [void]$sb1.AppendLine("  * 大小：" + $item.SizeMB + " MB (" + $item.FileCount + " 个文件)")
            [void]$sb1.AppendLine("  * 说明与建议：" + $item.Description)
            [void]$sb1.AppendLine("")
        }
    }

    if ($manifestContent -match '<!-- TIER1_PKG_CACHES_PLACEHOLDER -->') {
        $manifestContent = $manifestContent -replace '<!-- TIER1_PKG_CACHES_PLACEHOLDER -->', $sb1.ToString().TrimEnd()
    } else {
        # Fallback under Tier 1 header
        $manifestContent = $manifestContent -replace '(## 🟢 Tier 1[^\r\n]*)', ("`$1`n`n" + $sb1.ToString())
    }

    # 5.2 Inject Tier 2 Package Caches
    $t2Pkg = $cachesFound | Where-Object { $_.Tier -eq 2 }
    $sb2 = [System.Text.StringBuilder]::new()
    [void]$sb2.AppendLine("### 📦 开发环境与依赖包共享缓存 (Tier 2: 需权衡决策)")
    [void]$sb2.AppendLine("")
    if ($t2Pkg.Count -eq 0) {
        [void]$sb2.AppendLine("*（未发现体积膨胀的 Conda 或 Gradle 共享解压包缓存）*")
        [void]$sb2.AppendLine("")
    } else {
        foreach ($item in $t2Pkg) {
            [void]$sb2.AppendLine("- [ ] **[" + $item.ID + "] " + $item.Name + "** 🟡 【需权衡决策 - 见说明】")
            [void]$sb2.AppendLine('  * 路径：`' + $item.Path + '`')
            [void]$sb2.AppendLine("  * 大小：" + $item.SizeMB + " MB (" + $item.FileCount + " 个文件)")
            [void]$sb2.AppendLine("  * 说明与权衡：" + $item.Description)
            [void]$sb2.AppendLine("")
        }
    }

    if ($manifestContent -match '<!-- TIER2_PKG_CACHES_PLACEHOLDER -->') {
        $manifestContent = $manifestContent -replace '<!-- TIER2_PKG_CACHES_PLACEHOLDER -->', $sb2.ToString().TrimEnd()
    } else {
        # Fallback under Tier 2 header
        $manifestContent = $manifestContent -replace '(## 🟡 Tier 2[^\r\n]*)', ("`$1`n`n" + $sb2.ToString())
    }

    [System.IO.File]::WriteAllText($OutputManifest, $manifestContent, (New-Object System.Text.UTF8Encoding($true)))
}

# =========================================================
# 6. Output Results
# =========================================================
if ($Json) {
    $cachesFound | ConvertTo-Json -Depth 3
} else {
    Write-Host "`n=== DETECTED GLOBAL PACKAGE MANAGER CACHES (v0.4.0) ===" -ForegroundColor Cyan
    if ($cachesFound.Count -eq 0) {
        Write-Host "No bloated pip, npm, Conda, or Gradle caches found." -ForegroundColor Green
    } else {
        $cachesFound | Select-Object ID, Tier, Category, SizeMB, FileCount, Name | Format-Table -AutoSize
        Write-Host "Tip: pip/npm tarballs are Tier 1 (100% safe). Conda unpacked pkgs require tradeoff." -ForegroundColor Gray
    }
}
