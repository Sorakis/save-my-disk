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
Write-Host " STARTING ISOLATED MOCK SANDBOX TEST SUITE (v0.5.3)" -ForegroundColor Cyan
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

    # 1.10 Mock Domestic IM & Heavyweight Office (v0.5.1 fixtures)
    # WeChat 3.x
    $mockWx3 = "$sandbox\Documents\WeChat Files\wxid_alice123"
    New-Item -ItemType Directory -Path "$mockWx3\FileStorage\Video" -Force | Out-Null
    Set-Content -Path "$mockWx3\FileStorage\Video\mock_video.mp4" -Value ("V" * 5 * 1024 * 1024)
    New-Item -ItemType Directory -Path "$mockWx3\FileStorage\Cache" -Force | Out-Null
    Set-Content -Path "$mockWx3\FileStorage\Cache\mock_thumb.dat" -Value ("C" * 3 * 1024 * 1024)
    New-Item -ItemType Directory -Path "$mockWx3\FileStorage\File\2024-01" -Force | Out-Null
    Set-Content -Path "$mockWx3\FileStorage\File\2024-01\ancient_report.pdf" -Value ("F" * 5 * 1024 * 1024)
    (Get-Item "$mockWx3\FileStorage\File\2024-01\ancient_report.pdf").LastWriteTime = (Get-Date).AddDays(-100)
    # WeChat 3.x CRITICAL CHAT DATABASE (Must be 100% immune!)
    New-Item -ItemType Directory -Path "$mockWx3\Msg\Multi" -Force | Out-Null
    Set-Content -Path "$mockWx3\Msg\Multi\MSG0.db" -Value ("D" * 10 * 1024 * 1024)

    # WeChat 4.0
    $mockWx4 = "$sandbox\Documents\xwechat_files\bob_alias_4a1b"
    New-Item -ItemType Directory -Path "$mockWx4\cache\2024-05\Emoticon" -Force | Out-Null
    Set-Content -Path "$mockWx4\cache\2024-05\Emoticon\sticker.bin" -Value ("E" * 3 * 1024 * 1024)
    New-Item -ItemType Directory -Path "$mockWx4\msg\video" -Force | Out-Null
    Set-Content -Path "$mockWx4\msg\video\stream.mp4" -Value ("S" * 4 * 1024 * 1024)
    # WeChat 4.0 CRITICAL DATABASE
    New-Item -ItemType Directory -Path "$mockWx4\db_storage\message" -Force | Out-Null
    Set-Content -Path "$mockWx4\db_storage\message\message_0.db" -Value ("M" * 8 * 1024 * 1024)
    Set-Content -Path "$mockWx4\db_storage\message\message_0.db-wal" -Value ("W" * 2 * 1024 * 1024)

    # WXWork
    $mockWxw = "$sandbox\Documents\WXWork\corp_enterprise_99"
    New-Item -ItemType Directory -Path "$mockWxw\Storage\Video" -Force | Out-Null
    Set-Content -Path "$mockWxw\Storage\Video\work_meeting.mp4" -Value ("K" * 4 * 1024 * 1024)
    New-Item -ItemType Directory -Path "$mockWxw\Data" -Force | Out-Null
    Set-Content -Path "$mockWxw\Data\chat.db" -Value ("Z" * 5 * 1024 * 1024)

    # Feishu & DingTalk
    New-Item -ItemType Directory -Path "$sandbox\AppData\Local\Feishu\app_data\logs" -Force | Out-Null
    Set-Content -Path "$sandbox\AppData\Local\Feishu\app_data\logs\feishu_crash.log" -Value ("L" * 2 * 1024 * 1024)
    New-Item -ItemType Directory -Path "$sandbox\AppData\Roaming\DingTalk\logs" -Force | Out-Null
    Set-Content -Path "$sandbox\AppData\Roaming\DingTalk\logs\ding_error.log" -Value ("G" * 2 * 1024 * 1024)

    # 1.11 Mock Browser & GPU Shader Caches (v0.5.2 fixtures)
    # Google Chrome (Default profile)
    $mockChrome = "$sandbox\AppData\Local\Google\Chrome\User Data\Default"
    New-Item -ItemType Directory -Path "$mockChrome\Code Cache\js" -Force | Out-Null
    Set-Content -Path "$mockChrome\Code Cache\js\v8_compiled_chunk.bin" -Value ("C" * 5 * 1024 * 1024)
    New-Item -ItemType Directory -Path "$mockChrome\GPUCache" -Force | Out-Null
    Set-Content -Path "$mockChrome\GPUCache\data_0" -Value ("G" * 3 * 1024 * 1024)
    # Chrome CRITICAL CREDENTIALS (Must be 100% immune!)
    Set-Content -Path "$mockChrome\Login Data" -Value ("P" * 10 * 1024 * 1024)
    New-Item -ItemType Directory -Path "$mockChrome\Network" -Force | Out-Null
    Set-Content -Path "$mockChrome\Network\Cookies" -Value ("K" * 2 * 1024 * 1024)

    # Microsoft Edge (Profile 1)
    $mockEdge = "$sandbox\AppData\Local\Microsoft\Edge\User Data\Profile 1"
    New-Item -ItemType Directory -Path "$mockEdge\Code Cache\js" -Force | Out-Null
    Set-Content -Path "$mockEdge\Code Cache\js\edge_chunk.bin" -Value ("E" * 4 * 1024 * 1024)
    Set-Content -Path "$mockEdge\Cookies" -Value ("K" * 2 * 1024 * 1024)

    # Mozilla Firefox
    $mockFirefox = "$sandbox\AppData\Local\Mozilla\Firefox\Profiles\xyz.default-release"
    New-Item -ItemType Directory -Path "$mockFirefox\cache2\entries" -Force | Out-Null
    Set-Content -Path "$mockFirefox\cache2\entries\ff_cache_entry.bin" -Value ("M" * 4 * 1024 * 1024)

    # NVIDIA DXCache
    $mockDxCache = "$sandbox\AppData\Local\NVIDIA\DXCache"
    New-Item -ItemType Directory -Path $mockDxCache -Force | Out-Null
    Set-Content -Path "$mockDxCache\shader_hash.bin" -Value ("N" * 6 * 1024 * 1024)

    # Windows CrashDumps
    $mockCrashDumps = "$sandbox\AppData\Local\CrashDumps"
    New-Item -ItemType Directory -Path $mockCrashDumps -Force | Out-Null
    Set-Content -Path "$mockCrashDumps\app_crash.dmp" -Value ("D" * 5 * 1024 * 1024)

    Write-Host "[SETUP] All mock sandbox fixtures (4-Tier v0.5.2 fixtures) created." -ForegroundColor Green

    # ----------------------------------------------------
    # 2. Test Execution
    # ----------------------------------------------------
    $scriptsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "scripts"
    $auditScript = Join-Path $scriptsDir "audit_drives.ps1"
    $scanResiduesScript = Join-Path $scriptsDir "scan_app_residues.ps1"
    $scanPackageScript = Join-Path $scriptsDir "scan_package_caches.ps1"
    $scanAiScript = Join-Path $scriptsDir "scan_ai_models.ps1"
    $scanDevScript = Join-Path $scriptsDir "scan_dev_artifacts.ps1"
    $scanImScript = Join-Path $scriptsDir "scan_im_office_residues.ps1"
    $scanBrwScript = Join-Path $scriptsDir "scan_browser_system_caches.ps1"
    $manageWslScript = Join-Path $scriptsDir "manage_wsl_disk.ps1"
    $cleanScript = Join-Path $scriptsDir "clean_selected_residues.ps1"
    $verifyScript = Join-Path $scriptsDir "verify_health.ps1"
    $exportDashScript = Join-Path $scriptsDir "export_dashboard.ps1"
    $menuTuiScript = Join-Path $scriptsDir "menu_tui.ps1"
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

    # TEST 5.5: Domestic IM & Heavyweight Office Caches Scan (v0.5.1)
    Write-Host "`n[TEST 5.5] Running scan_im_office_residues (WeChat 3.x/4.0, WXWork, Feishu, DingTalk)..." -ForegroundColor Cyan
    $imJson = @((& $scanImScript -MockRoot $sandbox -OutputManifest $mockManifest -DaysInactive 90 -Json | ConvertFrom-Json) | ForEach-Object { $_ })
    if ($imJson.Count -ge 4) {
        Write-Host "  -> PASS: Correctly detected $($imJson.Count) domestic IM/office cache targets." -ForegroundColor Green
    } else {
        throw "FAIL: Expected at least 4 IM cache items, found $($imJson.Count)"
    }
    # Verify NO database file was ever listed as a cleanup candidate!
    $leakedDb = $imJson | Where-Object { $_.Path -like "*.db*" -or $_.Path -like "*WeChat Files*\Msg*" -or $_.Path -like "*\db_storage\*" }
    if ($leakedDb) {
        throw "CRITICAL SECURITY FAIL: Chat database was leaked into candidate list! $($leakedDb.Path)"
    } else {
        Write-Host "  -> PASS: CRITICAL CHECK: Chat history databases were 100% EXCLUDED from scan candidates!" -ForegroundColor Green
    }

    # TEST 5.6: Browser & GPU Shader Caches Scan (v0.5.2)
    Write-Host "`n[TEST 5.6] Running scan_browser_system_caches (Chrome, Edge, DXCache, CrashDumps)..." -ForegroundColor Cyan
    $brwJson = @((& $scanBrwScript -MockRoot $sandbox -OutputManifest $mockManifest -Json | ConvertFrom-Json) | ForEach-Object { $_ })
    if ($brwJson.Count -ge 4) {
        Write-Host "  -> PASS: Correctly detected $($brwJson.Count) browser/shader cache targets." -ForegroundColor Green
    } else {
        throw "FAIL: Expected at least 4 browser/shader cache items, found $($brwJson.Count)"
    }
    # Verify NO credentials or cookies were ever listed as candidates!
    $leakedCred = $brwJson | Where-Object { $_.Path -match "Login Data|Cookies|History|Bookmarks" }
    if ($leakedCred) {
        throw "CRITICAL SECURITY FAIL: Browser credentials were leaked into candidate list! $($leakedCred.Path)"
    } else {
        Write-Host "  -> PASS: CRITICAL CHECK: Browser passwords, cookies, and history 100% EXCLUDED from scan candidates!" -ForegroundColor Green
    }

    # TEST 6: Verify all Tier headers and anchors in Manifest
    $mTextUpdated = Get-Content -LiteralPath $mockManifest -Raw -Encoding UTF8
    if (($mTextUpdated -match "Tier 1") -and ($mTextUpdated -match "Tier 2") -and ($mTextUpdated -match "Tier 3") -and ($mTextUpdated -match "Tier 4")) {
        Write-Host "  -> PASS: cleanup_manifest.md cleanly preserved all 4 canonical Tier section headers." -ForegroundColor Green
    } else {
        throw "FAIL: cleanup_manifest.md missing one or more Tier section headers."
    }
    if ($mTextUpdated -match "AI-001" -and $mTextUpdated -match "PKG-001" -and $mTextUpdated -match "DEV-001" -and $mTextUpdated -match "IM-001" -and $mTextUpdated -match "BRW-001") {
        Write-Host "  -> PASS: All AI-xxx, PKG-xxx, DEV-xxx, IM-xxx, and BRW-xxx candidates successfully anchored into Manifest." -ForegroundColor Green
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

    # TEST 8: Manifest-driven deletion across SYS, RES, DEV, AI, PKG, IM, BRW items
    Write-Host "`n[TEST 8] Testing manifest-driven deletion across SYS, DEV, AI, PKG, IM, BRW items..." -ForegroundColor Cyan
    # Mark DEV-001, AI-001, PKG-001, PKG-003, IM-001, and BRW-001 as checked
    $mTextUpdated = [regex]::Replace($mTextUpdated, "-\s*\[\s*\]\s*\*\*\[DEV-001\]", "- [x] **[DEV-001]")
    $mTextUpdated = [regex]::Replace($mTextUpdated, "-\s*\[\s*\]\s*\*\*\[AI-001\]", "- [x] **[AI-001]")
    $mTextUpdated = [regex]::Replace($mTextUpdated, "-\s*\[\s*\]\s*\*\*\[PKG-001\]", "- [x] **[PKG-001]")
    $mTextUpdated = [regex]::Replace($mTextUpdated, "-\s*\[\s*\]\s*\*\*\[PKG-003\]", "- [x] **[PKG-003]")
    $mTextUpdated = [regex]::Replace($mTextUpdated, "-\s*\[\s*\]\s*\*\*\[IM-001\]", "- [x] **[IM-001]")
    $mTextUpdated = [regex]::Replace($mTextUpdated, "-\s*\[\s*\]\s*\*\*\[BRW-001\]", "- [x] **[BRW-001]")
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

    # Verify WeChat video cache deleted
    if (-not (Test-Path "$mockWx3\FileStorage\Video\mock_video.mp4")) {
        Write-Host "  -> PASS: WeChat 3.x video cache (IM-001) was cleanly purged." -ForegroundColor Green
    } else {
        throw "FAIL: WeChat video cache was not deleted."
    }

    # Verify Chrome Code Cache files deleted, container directory preserved, credentials intact
    if (-not (Test-Path "$mockChrome\Code Cache\js\v8_compiled_chunk.bin")) {
        Write-Host "  -> PASS: Chrome Code Cache (BRW-001) contents cleanly purged." -ForegroundColor Green
    } else {
        throw "FAIL: Chrome Code Cache was not deleted."
    }
    if (Test-Path "$mockChrome\Code Cache") {
        Write-Host "  -> PASS: Chrome Code Cache container directory 100% PRESERVED!" -ForegroundColor Green
    } else {
        throw "FAIL: Chrome Code Cache container directory was deleted!"
    }
    if ((Test-Path "$mockChrome\Login Data") -and (Test-Path "$mockChrome\Network\Cookies")) {
        Write-Host "  -> PASS: CRITICAL CHECK: Chrome Login Data and Cookies 100% PRESERVED!" -ForegroundColor Green
    } else {
        throw "FAIL: Chrome Login Data or Cookies was damaged!"
    }

    # TEST 8.1: CRITICAL ADVERSARIAL TEST: Attempt direct deletion on chat databases & browser credentials
    Write-Host "`n[TEST 8.1] Running ADVERSARIAL TEST: Attempting direct deletion on chat databases & browser credentials..." -ForegroundColor Cyan
    $attackOutput1 = & $cleanScript -MockRoot $sandbox -TargetPaths "$mockWx3\Msg\Multi" -Force 2>&1 | Out-String
    $attackOutput2 = & $cleanScript -MockRoot $sandbox -TargetPaths "$mockWx4\db_storage\message" -Force 2>&1 | Out-String
    $attackOutput3 = & $cleanScript -MockRoot $sandbox -TargetPaths "$mockChrome\Login Data" -Force 2>&1 | Out-String
    $attackOutput4 = & $cleanScript -MockRoot $sandbox -TargetPaths "$mockChrome" -Force 2>&1 | Out-String
    $attackOutput5 = & $cleanScript -MockRoot $sandbox -TargetPaths "$mockFirefox" -Force 2>&1 | Out-String
    if ($attackOutput1 -match "SECURITY BLOCKED" -and $attackOutput2 -match "SECURITY BLOCKED" -and $attackOutput3 -match "SECURITY BLOCKED" -and $attackOutput4 -match "SECURITY BLOCKED" -and $attackOutput5 -match "SECURITY BLOCKED") {
        Write-Host "  -> PASS: ADVERSARIAL TEST: Cleaner strictly BLOCKED attempts to delete WeChat databases, Chrome credentials, and Profile roots!" -ForegroundColor Green
    } else {
        throw "FAIL: ADVERSARIAL TEST FAILED: Cleaner did not block credential or database deletion!"
    }
    if ((Test-Path "$mockWx3\Msg\Multi\MSG0.db") -and (Test-Path "$mockWx4\db_storage\message\message_0.db") -and (Test-Path "$mockChrome\Login Data")) {
        Write-Host "  -> PASS: CRITICAL CHECK: All chat history databases and browser credentials are 100% UNTOUCHED and PRESERVED!" -ForegroundColor Green
    } else {
        throw "FAIL: Database or credential was destroyed during adversarial test!"
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

    # TEST 10: Post-cleanup health verification with HTML export
    Write-Host "`n[TEST 10] Running verify_health check with MockRoot & ExportHtml..." -ForegroundColor Cyan
    $healthJson = & $verifyScript -MockRoot $sandbox -ManifestPath $mockManifest -ExportHtml -Json | ConvertFrom-Json
    if ($healthJson.Volumes.Count -ge 1 -and $healthJson.Services.wuauserv -eq "Running") {
        Write-Host "  -> PASS: verify_health successfully reported volume and critical service health." -ForegroundColor Green
    } else {
        throw "FAIL: verify_health failed to report status."
    }

    # TEST 11: Standalone HTML Visual Dashboard generation
    Write-Host "`n[TEST 11] Running export_dashboard..." -ForegroundColor Cyan
    $mockReportPath = Join-Path $sandbox ".save-my-disk\disk_triage_report.html"
    $dashJson = & $exportDashScript -MockRoot $sandbox -ManifestPath $mockManifest -OutputPath $mockReportPath -Json | ConvertFrom-Json
    if ((Test-Path -LiteralPath $mockReportPath) -and (Get-Item $mockReportPath).Length -gt 2000) {
        Write-Host "  -> PASS: Standalone HTML report generated successfully (Size: $((Get-Item $mockReportPath).Length) bytes)." -ForegroundColor Green
    } else {
        throw "FAIL: HTML report was not created or empty!"
    }
    if ($dashJson.TotalCandidates -lt 5 -or ($dashJson.TotalPendingGB + $dashJson.TotalCleanedGB) -le 0) {
        throw "FAIL: HTML dashboard parsed zero candidates or zero space! Candidates=$($dashJson.TotalCandidates), Cleaned=$($dashJson.TotalCleanedGB), Pending=$($dashJson.TotalPendingGB)"
    } else {
        Write-Host "  -> PASS: HTML dashboard accurately extracted $($dashJson.TotalCandidates) candidates (Cleaned: $($dashJson.TotalCleanedGB) GB, Pending: $($dashJson.TotalPendingGB) GB)." -ForegroundColor Green
    }
    $reportHtml = Get-Content -LiteralPath $mockReportPath -Raw -Encoding UTF8
    if ($reportHtml -match "<svg" -and $reportHtml -match "Tier 1" -and $reportHtml -match "v0.5.3") {
        Write-Host "  -> PASS: HTML report contains embedded SVG charts, Tier breakdowns, and v0.5.3 branding." -ForegroundColor Green
    } else {
        throw "FAIL: HTML report missing SVG or Tier content."
    }

    # TEST 12: Terminal Menu Non-Interactive Mode
    Write-Host "`n[TEST 12] Testing menu_tui in non-interactive & test mode..." -ForegroundColor Cyan
    $menuOutput = & $menuTuiScript -MockRoot $sandbox -TestMenu *>&1 | Out-String
    if ($menuOutput -match "SAVE-MY-DISK \(v0.5.3\)" -and $menuOutput -match "TEST MODE") {
        Write-Host "  -> PASS: Interactive menu initialized and cleanly exited in test mode without hanging." -ForegroundColor Green
    } else {
        throw "FAIL: Menu failed in test mode: $menuOutput"
    }
    $nonInterOutput = & $menuTuiScript -MockRoot $sandbox -NonInteractive *>&1 | Out-String
    if ($nonInterOutput -match "NON-INTERACTIVE") {
        Write-Host "  -> PASS: Menu correctly detected -NonInteractive mode and exited cleanly without hanging." -ForegroundColor Green
    } else {
        throw "FAIL: Menu failed in -NonInteractive mode: $nonInterOutput"
    }

    Write-Host "`n======================================================" -ForegroundColor Green
    Write-Host " ALL v0.5.3 TESTS PASSED! 100% ISOLATED & SAFE." -ForegroundColor Green
    Write-Host "======================================================" -ForegroundColor Cyan

} finally {
    # Teardown Sandbox
    if (Test-Path $sandbox) {
        Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "[TEARDOWN] Mock sandbox cleaned up completely." -ForegroundColor Gray
    }
}
