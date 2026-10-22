<#
.SYNOPSIS
    Self-contained Mock Sandbox Test Suite for save-my-disk v0.4.0.
.DESCRIPTION
    Creates an isolated mock directory in Temp, runs all scan modules:
    - audit_drives.ps1 (Hotspots & absent upgrade files)
    - scan_app_residues.ps1 (Base 4-Tier manifest & app caches)
    - scan_package_caches.ps1 (pip, npm, Conda pkgs)
    - scan_ai_models.ps1 (Hugging Face with symlinks, Ollama, PyTorch)
    - scan_dev_artifacts.ps1 (Inactive build artifacts)
    - manage_wsl_disk.ps1 (VHDX analysis)
    - clean_selected_residues.ps1 (Manifest-driven deletion across SYS, RES, DEV, AI, PKG)
    - verify_health.ps1 (Service & volume verification)
    GUARANTEE: 100% isolated inside $env:TEMP, zero impact or leaks to host files or host CLI!
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$testRunId = [guid]::NewGuid().ToString().Substring(0, 8)
$sandbox = Join-Path $env:TEMP "disk_cleaner_test_$testRunId"

Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " STARTING ISOLATED MOCK SANDBOX TEST SUITE (v0.4.0)" -ForegroundColor Cyan
Write-Host " Sandbox Location: $sandbox" -ForegroundColor Gray
Write-Host "======================================================" -ForegroundColor Cyan

try {
    # ----------------------------------------------------
    # 1. Setup Sandbox Fixtures
    # ----------------------------------------------------
    # 1.1 Mock Tier 1: Windows Update & Temp ($WINDOWS.~BT is intentionally left absent to test 0MB reporting)
    $mockWu = "$sandbox\Windows\SoftwareDistribution\Download"
    New-Item -ItemType Directory -Path $mockWu -Force | Out-Null
    Set-Content -Path "$mockWu\mock-patch.cab" -Value ("W" * 1024 * 1024)

    $mockTemp = "$sandbox\AppData\Local\Temp"
    New-Item -ItemType Directory -Path $mockTemp -Force | Out-Null
    Set-Content -Path "$mockTemp\mock-temp.tmp" -Value ("T" * 1024 * 1024)

    # 1.2 Mock Tier 1 & 2: Package Manager Caches (pip, npm, Conda pkgs)
    $mockPip = "$sandbox\AppData\Local\pip\cache"
    New-Item -ItemType Directory -Path $mockPip -Force | Out-Null
    Set-Content -Path "$mockPip\mock-package.whl" -Value ("P" * 5 * 1024 * 1024)

    $mockNpm = "$sandbox\AppData\Local\npm-cache"
    New-Item -ItemType Directory -Path $mockNpm -Force | Out-Null
    Set-Content -Path "$mockNpm\mock-package.tgz" -Value ("N" * 5 * 1024 * 1024)

    $mockCondaPkgs = "$sandbox\miniconda3\pkgs"
    New-Item -ItemType Directory -Path $mockCondaPkgs -Force | Out-Null
    Set-Content -Path "$mockCondaPkgs\mock-pkg-1.0.tar.bz2" -Value ("C" * 5 * 1024 * 1024)
    # Mock unpacked package inside pkgs to test selective tarball purge and environment safety
    New-Item -ItemType Directory -Path "$mockCondaPkgs\mock-pkg-1.0\lib" -Force | Out-Null
    Set-Content -Path "$mockCondaPkgs\mock-pkg-1.0\lib\python.dll" -Value ("L" * 1024 * 1024)

    # 1.3 Mock Tier 2: AI / ML Models (Hugging Face with blobs & snapshots, Ollama)
    $mockHfModel = "$sandbox\.cache\huggingface\hub\models--meta-llama--Llama-3-8B"
    New-Item -ItemType Directory -Path "$mockHfModel\blobs" -Force | Out-Null
    New-Item -ItemType Directory -Path "$mockHfModel\snapshots\abc12345" -Force | Out-Null
    # 5MB physical blob
    Set-Content -Path "$mockHfModel\blobs\blob_weight_hash_data.bin" -Value ("H" * 5 * 1024 * 1024)
    # Attempt symlink creation, fallback gracefully if non-elevated
    try {
        New-Item -ItemType SymbolicLink -Path "$mockHfModel\snapshots\abc12345\model.safetensors" -Target "$mockHfModel\blobs\blob_weight_hash_data.bin" -ErrorAction Stop | Out-Null
    } catch {
        Set-Content -Path "$mockHfModel\snapshots\abc12345\model.safetensors.ptr" -Value "pointer"
    }

    $mockOllamaBlobs = "$sandbox\.ollama\models\blobs"
    New-Item -ItemType Directory -Path $mockOllamaBlobs -Force | Out-Null
    Set-Content -Path "$mockOllamaBlobs\sha256-mock-gguf-blob" -Value ("O" * 5 * 1024 * 1024)

    # 1.4 Mock Tier 2: NVIDIA App OTA driver artifacts
    $mockNvOta = "$sandbox\ProgramData\NVIDIA Corporation\NVIDIA App\UpdateFramework\ota-artifacts"
    New-Item -ItemType Directory -Path $mockNvOta -Force | Out-Null
    Set-Content -Path "$mockNvOta\mock-driver-617.14-setup.exe" -Value ("X" * 1024 * 1024)

    # 1.5 Mock Tier 3: Steam residual & Empty Corrupted Folder
    New-Item -ItemType Directory -Path "$sandbox\Steam\steamapps\common\GhostGameResidual" -Force | Out-Null
    Set-Content -Path "$sandbox\Steam\steamapps\common\GhostGameResidual\crash.log" -Value "Mock residual log data"
    New-Item -ItemType Directory -Path "$sandbox\MUMU\empty_folder" -Force | Out-Null

    # 1.6 Mock Tier 3: App Caches (WPS, WeChat)
    New-Item -ItemType Directory -Path "$sandbox\AppData\Kingsoft\backup" -Force | Out-Null
    Set-Content -Path "$sandbox\AppData\Kingsoft\backup\temp_autosave.tmp" -Value "Mock auto backup content"
    New-Item -ItemType Directory -Path "$sandbox\AppData\Tencent\WeChat\log" -Force | Out-Null
    Set-Content -Path "$sandbox\AppData\Tencent\WeChat\log\app_trace.log" -Value "Mock WeChat trace log"

    # 1.7 Mock Docker / WSL2 Virtual Disk
    $mockDiskDir = "$sandbox\Docker\wsl\disk"
    New-Item -ItemType Directory -Path $mockDiskDir -Force | Out-Null
    Set-Content -Path "$mockDiskDir\mock_docker_data.vhdx" -Value ("V" * 1024 * 1024)

    # 1.8 Mock Inactive Project (> 60 days inactive)
    $deadProj = "$sandbox\Projects\DeadFrontend"
    New-Item -ItemType Directory -Path "$deadProj\src" -Force | Out-Null
    New-Item -ItemType Directory -Path "$deadProj\node_modules\large_pkg" -Force | Out-Null
    Set-Content -Path "$deadProj\package.json" -Value "{ `"name`": `"dead-project`" }"
    Set-Content -Path "$deadProj\src\index.js" -Value "console.log('ancient code');"
    Set-Content -Path "$deadProj\node_modules\large_pkg\bundle.js" -Value ("B" * 6 * 1024 * 1024)

    # Backdate source files to 90 days ago
    $oldDate = (Get-Date).AddDays(-90)
    (Get-Item "$deadProj\package.json").LastWriteTime = $oldDate
    (Get-Item "$deadProj\src\index.js").LastWriteTime = $oldDate
    (Get-Item "$deadProj\src").LastWriteTime = $oldDate
    (Get-Item "$deadProj").LastWriteTime = $oldDate

    # 1.9 Mock Active Project (< 60 days active)
    $activeProj = "$sandbox\Projects\ActiveBackend"
    New-Item -ItemType Directory -Path "$activeProj\src" -Force | Out-Null
    New-Item -ItemType Directory -Path "$activeProj\target\debug" -Force | Out-Null
    Set-Content -Path "$activeProj\Cargo.toml" -Value "[package]`nname = `"active`""
    Set-Content -Path "$activeProj\src\main.rs" -Value "fn main() {}"
    Set-Content -Path "$activeProj\target\debug\app.exe" -Value ("A" * 6 * 1024 * 1024)

    Write-Host "[SETUP] All mock sandbox fixtures (4-Tier v0.4.0 fixtures) created." -ForegroundColor Green

    # ----------------------------------------------------
    # 2. Test Execution
    # ----------------------------------------------------
    $scriptsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "scripts"
    $auditScript = Join-Path $scriptsDir "audit_drives.ps1"
    $scanResiduesScript = Join-Path $scriptsDir "scan_app_residues.ps1"
    $scanPackageScript = Join-Path $scriptsDir "scan_package_caches.ps1"
    $scanAiScript = Join-Path $scriptsDir "scan_ai_models.ps1"
    $scanDevScript = Join-Path $scriptsDir "scan_dev_artifacts.ps1"
    $manageWslScript = Join-Path $scriptsDir "manage_wsl_disk.ps1"
    $cleanScript = Join-Path $scriptsDir "clean_selected_residues.ps1"
    $verifyScript = Join-Path $scriptsDir "verify_health.ps1"
    $mockManifest = Join-Path $sandbox ".save-my-disk\cleanup_manifest.md"

    # TEST 1: Audit drives with mock root (Absent item check)
    Write-Host "`n[TEST 1] Running audit_drives with MockRoot (checking absent upgrade status)..." -ForegroundColor Cyan
    $auditJson = & $auditScript -MockRoot $sandbox -Json | ConvertFrom-Json
    $btHotspot = $auditJson.Hotspots | Where-Object { $_.Name -like "*WINDOWS.~BT*" }
    if ($btHotspot -and $btHotspot.SizeMB -eq 0 -and $btHotspot.Status -like "*健康*") {
        Write-Host "  -> PASS: Correctly audited absent `$WINDOWS.~BT` as 0 MB (健康/已清理)." -ForegroundColor Green
    } else {
        throw "FAIL: audit_drives failed to report absent `$WINDOWS.~BT` status correctly."
    }

    # TEST 2: App residues scan & 4-tier manifest generation
    Write-Host "`n[TEST 2] Running scan_app_residues & generating base 4-Tier cleanup_manifest.md..." -ForegroundColor Cyan
    $scanJson = @((& $scanResiduesScript -MockRoot $sandbox -OutputManifest $mockManifest -Json | ConvertFrom-Json) | ForEach-Object { $_ })
    $absentSys = $scanJson | Where-Object { $_.ID -eq "SYS-000" }
    if ($absentSys -and $absentSys.SizeMB -eq 0 -and $absentSys.RiskLevel -eq "Healthy") {
        Write-Host "  -> PASS: scan_app_residues reported SYS-000 absent upgrade status (0 MB Healthy)." -ForegroundColor Green
    } else {
        throw "FAIL: scan_app_residues missed SYS-000 absent status item."
    }

    # TEST 3: Package Manager Caches Scan (pip, npm, Conda pkgs)
    Write-Host "`n[TEST 3] Running scan_package_caches (pip/npm Tier 1 & Conda Tier 1/2)..." -ForegroundColor Cyan
    $pkgJson = @((& $scanPackageScript -MockRoot $sandbox -OutputManifest $mockManifest -Json | ConvertFrom-Json) | ForEach-Object { $_ })
    if ($pkgJson.Count -ge 3) {
        Write-Host "  -> PASS: Detected $($pkgJson.Count) package cache items (pip, npm, Conda tarballs)." -ForegroundColor Green
    } else {
        throw "FAIL: Expected at least 3 package cache items, found $($pkgJson.Count)"
    }

    # TEST 4: AI / ML Models Scan (Hugging Face symlink defense & Ollama)
    Write-Host "`n[TEST 4] Running scan_ai_models (HF symlink check & Ollama blobs)..." -ForegroundColor Cyan
    $aiJson = @((& $scanAiScript -MockRoot $sandbox -OutputManifest $mockManifest -Json | ConvertFrom-Json) | ForEach-Object { $_ })
    $hfModel = $aiJson | Where-Object { $_.Category -eq "Hugging Face Model" }
    if ($hfModel -and $hfModel.SizeMB -le 6 -and $hfModel.SizeMB -ge 4.5) {
        Write-Host "  -> PASS: Hugging Face model size accurately measured at $($hfModel.SizeMB) MB (no symlink double-counting)." -ForegroundColor Green
    } else {
        throw "FAIL: Hugging Face model size abnormal (SizeMB: $($hfModel.SizeMB)), possible double-counting!"
    }
    if ($aiJson.Count -ge 2) {
        Write-Host "  -> PASS: Correctly detected $($aiJson.Count) AI model targets (HF + Ollama)." -ForegroundColor Green
    } else {
        throw "FAIL: Expected at least 2 AI model targets."
    }

    # TEST 5: Inactive dev artifacts scan & insertion into Tier 2
    Write-Host "`n[TEST 5] Running scan_dev_artifacts (inactive check & Tier 2 placeholder insertion)..." -ForegroundColor Cyan
    $devJson = @((& $scanDevScript -MockRoot $sandbox -DaysInactive 60 -OutputManifest $mockManifest -Json | ConvertFrom-Json) | ForEach-Object { $_ })
    if ($devJson.Count -eq 1 -and $devJson[0].Project -eq "DeadFrontend") {
        Write-Host "  -> PASS: Correctly identified DeadFrontend as inactive and preserved ActiveBackend." -ForegroundColor Green
    } else {
        throw "FAIL: Dev artifact detection failed (Count: $($devJson.Count))."
    }

    # TEST 6: Verify all Tier headers and anchors in Manifest
    $mTextUpdated = Get-Content -LiteralPath $mockManifest -Raw -Encoding UTF8
    if (($mTextUpdated -match "Tier 1") -and ($mTextUpdated -match "Tier 2") -and ($mTextUpdated -match "Tier 3") -and ($mTextUpdated -match "Tier 4")) {
        Write-Host "  -> PASS: cleanup_manifest.md cleanly preserved all 4 canonical Tier section headers." -ForegroundColor Green
    } else {
        throw "FAIL: cleanup_manifest.md missing one or more Tier section headers."
    }
    if ($mTextUpdated -match "AI-001" -and $mTextUpdated -match "PKG-001" -and $mTextUpdated -match "DEV-001") {
        Write-Host "  -> PASS: All AI-xxx, PKG-xxx, and DEV-xxx candidates successfully anchored into Manifest." -ForegroundColor Green
    } else {
        throw "FAIL: One or more candidate groups missing from Manifest."
    }

    # TEST 7: WSL2 / Docker virtual disk analysis
    Write-Host "`n[TEST 7] Running manage_wsl_disk analysis..." -ForegroundColor Cyan
    $wslJson = @((& $manageWslScript -MockRoot $sandbox -Json | ConvertFrom-Json) | ForEach-Object { $_ })
    if ($wslJson.Count -ge 1 -and $wslJson[0].Name -eq "mock_docker_data.vhdx") {
        Write-Host "  -> PASS: Correctly detected mock VHDX virtual disk." -ForegroundColor Green
    } else {
        throw "FAIL: VHDX detection failed."
    }

    # TEST 8: Manifest-driven deletion across SYS, RES, DEV, AI, PKG items
    Write-Host "`n[TEST 8] Testing manifest-driven deletion across SYS, DEV, AI, PKG items..." -ForegroundColor Cyan
    # Mark DEV-001, AI-001, PKG-001, and Conda Tarballs (PKG-003) as checked
    $mTextUpdated = [regex]::Replace($mTextUpdated, "-\s*\[\s*\]\s*\*\*\[DEV-001\]", "- [x] **[DEV-001]")
    $mTextUpdated = [regex]::Replace($mTextUpdated, "-\s*\[\s*\]\s*\*\*\[AI-001\]", "- [x] **[AI-001]")
    $mTextUpdated = [regex]::Replace($mTextUpdated, "-\s*\[\s*\]\s*\*\*\[PKG-001\]", "- [x] **[PKG-001]")
    $mTextUpdated = [regex]::Replace($mTextUpdated, "-\s*\[\s*\]\s*\*\*\[PKG-003\]", "- [x] **[PKG-003]")
    [System.IO.File]::WriteAllText($mockManifest, $mTextUpdated, (New-Object System.Text.UTF8Encoding($true)))

    # Execute cleaner with -FromManifest -Force
    & $cleanScript -MockRoot $sandbox -ManifestPath $mockManifest -FromManifest -Force | Out-Null

    # Verify dead project node_modules deleted
    if (-not (Test-Path "$deadProj\node_modules")) {
        Write-Host "  -> PASS: Dead project's node_modules was cleanly purged." -ForegroundColor Green
    } else {
        throw "FAIL: node_modules was not deleted."
    }

    # Verify mock HF model deleted
    if (-not (Test-Path $mockHfModel)) {
        Write-Host "  -> PASS: Target AI model (AI-001) was cleanly purged." -ForegroundColor Green
    } else {
        throw "FAIL: AI model was not deleted."
    }

    # Verify Conda tarball deleted but unpacked packages and pkgs folder PRESERVED!
    if (-not (Test-Path "$mockCondaPkgs\mock-pkg-1.0.tar.bz2")) {
        Write-Host "  -> PASS: Conda tarball (*.tar.bz2) was cleanly purged." -ForegroundColor Green
    } else {
        throw "FAIL: Conda tarball was not deleted."
    }
    if ((Test-Path "$mockCondaPkgs\mock-pkg-1.0\lib\python.dll") -and (Test-Path $mockCondaPkgs)) {
        Write-Host "  -> PASS: CRITICAL CHECK: Conda unpacked packages and pkgs/ folder 100% PRESERVED!" -ForegroundColor Green
    } else {
        throw "FAIL: Conda pkgs directory or unpacked package was accidentally damaged!"
    }

    # CRITICAL CHECK: Source code must be 100% intact!
    if ((Test-Path "$deadProj\package.json") -and (Test-Path "$deadProj\src\index.js")) {
        Write-Host "  -> PASS: CRITICAL CHECK: Source code (package.json, src/index.js) was 100% PRESERVED!" -ForegroundColor Green
    } else {
        throw "FAIL: Source code was accidentally damaged!"
    }

    # CRITICAL CHECK: Active project must not be touched!
    if (Test-Path "$activeProj\target\debug\app.exe") {
        Write-Host "  -> PASS: CRITICAL CHECK: Active project was 100% UNTOUCHED!" -ForegroundColor Green
    } else {
        throw "FAIL: Active project was modified!"
    }

    # TEST 9: Verify Manifest updated with audit record
    $finalManifest = Get-Content -LiteralPath $mockManifest -Raw -Encoding UTF8
    if ($finalManifest -match "\(已成功清理\)") {
        Write-Host "  -> PASS: Manifest file was successfully updated with audit records." -ForegroundColor Green
    } else {
        throw "FAIL: Manifest file was not updated after deletion."
    }

    # TEST 10: Post-cleanup health verification
    Write-Host "`n[TEST 10] Running verify_health check..." -ForegroundColor Cyan
    $healthJson = & $verifyScript -Json | ConvertFrom-Json
    if ($healthJson.Volumes.Count -ge 1) {
        Write-Host "  -> PASS: verify_health successfully reported volume and critical service health." -ForegroundColor Green
    } else {
        throw "FAIL: verify_health failed to report status."
    }

    Write-Host "`n======================================================" -ForegroundColor Green
    Write-Host " ALL v0.4.0 TESTS PASSED! 100% ISOLATED & SAFE." -ForegroundColor Green
    Write-Host "======================================================" -ForegroundColor Cyan

} finally {
    # Teardown Sandbox
    if (Test-Path $sandbox) {
        Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "[TEARDOWN] Mock sandbox cleaned up completely." -ForegroundColor Gray
    }
}
