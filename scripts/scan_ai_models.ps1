<#
.SYNOPSIS
    Scans for local AI/ML model caches: Hugging Face Hub, Ollama GGUF models, and PyTorch Hub checkpoints.
.DESCRIPTION
    Non-invasive read-only scanner for save-my-disk (v0.4.0).
    Correctly handles Hugging Face symlinks (ReparsePoints) to prevent double-counting.
    Provides tradeoff analysis for model weights and integrates with cleanup_manifest.md.
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

$modelsFound = @()
$counter = 1

# =========================================================
# 1. Hugging Face Hub Cache (~/.cache/huggingface/hub)
# =========================================================
$hfHubPath = if ($MockRoot) {
    Join-Path $MockRoot ".cache\huggingface\hub"
} elseif ($env:HF_HUB_CACHE) {
    $env:HF_HUB_CACHE
} elseif ($env:HF_HOME) {
    Join-Path $env:HF_HOME "hub"
} else {
    Join-Path $env:USERPROFILE ".cache\huggingface\hub"
}

if (Test-Path -LiteralPath $hfHubPath) {
    $modelDirs = Get-ChildItem -LiteralPath $hfHubPath -Directory -Force -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -like "models--*"
    }

    foreach ($mDir in $modelDirs) {
        # Parse model name: models--org--name -> org/name
        $rawName = $mDir.Name -replace '^models--', ''
        $parts = $rawName -split '--'
        $modelDisplayName = $parts -join '/'

        # Symlink double-counting defense:
        # If blobs/ directory exists, calculate physical weights from blobs/ only!
        # Otherwise filter out ReparsePoint symlinks.
        $blobsPath = Join-Path $mDir.FullName "blobs"
        $filesToMeasure = @()
        if (Test-Path -LiteralPath $blobsPath) {
            $filesToMeasure = Get-ChildItem -LiteralPath $blobsPath -Recurse -File -Force -ErrorAction SilentlyContinue
        } else {
            $filesToMeasure = Get-ChildItem -LiteralPath $mDir.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object {
                -not ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
            }
        }

        $szMB = [math]::Round(($filesToMeasure | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
        if ($szMB -gt 50 -or $MockRoot) {
            $modelsFound += [PSCustomObject]@{
                ID = "AI-" + ($counter++).ToString("D3")
                Tier = 2
                Category = "Hugging Face Model"
                Name = "Hugging Face 模型: " + $modelDisplayName
                Path = $mDir.FullName
                SizeMB = $szMB
                FileCount = $filesToMeasure.Count
                RiskLevel = "Low-Decision"
                Description = "Hugging Face 离线权重文件。删除完全不影响代码工程源码；后续若需调用该模型，Transformers/vLLM 会自动重新联网下载。"
            }
        }
    }
}

# =========================================================
# 2. Ollama Quantized GGUF Model Repository (~/.ollama/models)
# =========================================================
$ollamaPath = if ($MockRoot) {
    Join-Path $MockRoot ".ollama\models"
} elseif ($env:OLLAMA_MODELS) {
    $env:OLLAMA_MODELS
} else {
    Join-Path $env:USERPROFILE ".ollama\models"
}

if (Test-Path -LiteralPath $ollamaPath) {
    $blobsDir = Join-Path $ollamaPath "blobs"
    $targetMeasure = if (Test-Path -LiteralPath $blobsDir) { $blobsDir } else { $ollamaPath }
    $ollamaFiles = Get-ChildItem -LiteralPath $targetMeasure -Recurse -File -Force -ErrorAction SilentlyContinue
    $oSizeMB = [math]::Round(($ollamaFiles | Measure-Object -Property Length -Sum).Sum / 1MB, 2)

    if ($oSizeMB -gt 100 -or $MockRoot) {
        $modelsFound += [PSCustomObject]@{
            ID = "AI-" + ($counter++).ToString("D3")
            Tier = 2
            Category = "Ollama Models"
            Name = "Ollama 本地量化模型存储库"
            Path = $ollamaPath
            SizeMB = $oSizeMB
            FileCount = $ollamaFiles.Count
            RiskLevel = "Low-Decision"
            Description = "Ollama 本地运行的 GGUF 混杂模型数据块。若需清理单一模型，推荐使用 'ollama rm <model>'；整体清理前请务必先退出 Ollama 桌面客户端。"
        }
    }
}

# =========================================================
# 3. PyTorch Hub Checkpoints (~/.cache/torch/hub/checkpoints)
# =========================================================
$torchPath = if ($MockRoot) {
    Join-Path $MockRoot ".cache\torch\hub\checkpoints"
} elseif ($env:TORCH_HOME) {
    Join-Path $env:TORCH_HOME "hub\checkpoints"
} else {
    Join-Path $env:USERPROFILE ".cache\torch\hub\checkpoints"
}

if (Test-Path -LiteralPath $torchPath) {
    $torchFiles = Get-ChildItem -LiteralPath $torchPath -Recurse -File -Force -ErrorAction SilentlyContinue
    $tSizeMB = [math]::Round(($torchFiles | Measure-Object -Property Length -Sum).Sum / 1MB, 2)

    if ($tSizeMB -gt 50 -or $MockRoot) {
        $modelsFound += [PSCustomObject]@{
            ID = "AI-" + ($counter++).ToString("D3")
            Tier = 2
            Category = "PyTorch Checkpoint"
            Name = "PyTorch Hub 预训练权重缓存"
            Path = $torchPath
            SizeMB = $tSizeMB
            FileCount = $torchFiles.Count
            RiskLevel = "Low"
            Description = "Torchvision/Timm 等视觉库下载的预训练模型权重。可安全清空，代码下次调用时会自动重新下载。"
        }
    }
}

# =========================================================
# 4. Integrate into cleanup_manifest.md (SSOT Anchor Injection)
# =========================================================
if ($OutputManifest -and (Test-Path -LiteralPath $OutputManifest)) {
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("### 🤖 AI / ML 本地大模型与运行时缓存 (Tier 2: 需权衡决策)")
    [void]$sb.AppendLine("")
    if ($modelsFound.Count -eq 0) {
        [void]$sb.AppendLine("*（经扫描，未发现体积膨胀的本地 Hugging Face、Ollama 或 PyTorch 离线模型）*")
        [void]$sb.AppendLine("")
    } else {
        foreach ($m in $modelsFound) {
            [void]$sb.AppendLine("- [ ] **[" + $m.ID + "] " + $m.Name + "** 🟡 【需权衡决策 - 见说明】")
            [void]$sb.AppendLine('  * 路径：`' + $m.Path + '`')
            [void]$sb.AppendLine("  * 大小：" + $m.SizeMB + " MB (" + $m.FileCount + " 个文件)")
            [void]$sb.AppendLine("  * 说明与权衡：" + $m.Description)
            [void]$sb.AppendLine("")
        }
    }

    $manifestContent = Get-Content -LiteralPath $OutputManifest -Raw -Encoding UTF8
    if ($manifestContent -match '<!-- TIER2_AI_MODELS_PLACEHOLDER -->') {
        $newContent = $manifestContent -replace '<!-- TIER2_AI_MODELS_PLACEHOLDER -->', $sb.ToString().TrimEnd()
        [System.IO.File]::WriteAllText($OutputManifest, $newContent, (New-Object System.Text.UTF8Encoding($true)))
    } elseif ($manifestContent -match '<!-- DEV_ARTIFACTS_PLACEHOLDER -->') {
        # Fallback before DEV artifacts
        $newContent = $manifestContent -replace '<!-- DEV_ARTIFACTS_PLACEHOLDER -->', ($sb.ToString() + "`n<!-- DEV_ARTIFACTS_PLACEHOLDER -->")
        [System.IO.File]::WriteAllText($OutputManifest, $newContent, (New-Object System.Text.UTF8Encoding($true)))
    } else {
        [System.IO.File]::AppendAllText($OutputManifest, "`n" + $sb.ToString(), (New-Object System.Text.UTF8Encoding($true)))
    }
}

# =========================================================
# 5. Output Results
# =========================================================
if ($Json) {
    $modelsFound | ConvertTo-Json -Depth 3
} else {
    Write-Host "`n=== DETECTED AI / ML LOCAL MODEL CACHES (v0.4.0) ===" -ForegroundColor Cyan
    if ($modelsFound.Count -eq 0) {
        Write-Host "No bloated Hugging Face, Ollama, or PyTorch models found." -ForegroundColor Green
    } else {
        $modelsFound | Select-Object ID, Tier, Category, SizeMB, FileCount, Name | Format-Table -AutoSize
        Write-Host "Tip: Models can be re-downloaded anytime. Review cleanup_manifest.md before cleaning." -ForegroundColor Gray
    }
}
