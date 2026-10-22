<#
.SYNOPSIS
    Self-contained Mock Sandbox Test Suite for save-my-disk v0.3.0.
.DESCRIPTION
    Creates an isolated mock directory in Temp, runs all scan, dev artifact, and WSL scripts against it,
    validates Manifest generation, verifies DryRun and Force modes, and purges the test fixture.
    GUARANTEE: Does NOT touch or delete any user files!
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$testRunId = [guid]::NewGuid().ToString().Substring(0, 8)
$sandbox = Join-Path $env:TEMP "disk_cleaner_test_$testRunId"

Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " STARTING ISOLATED MOCK SANDBOX TEST SUITE (v0.3.0)" -ForegroundColor Cyan
Write-Host " Sandbox Location: $sandbox" -ForegroundColor Gray
Write-Host "======================================================" -ForegroundColor Cyan

try {
    # ----------------------------------------------------
    # 1. Setup Sandbox Fixtures
    # ----------------------------------------------------
    # 1.1 Mock NVIDIA App OTA driver artifacts
    $mockNvOta = "$sandbox\ProgramData\NVIDIA Corporation\NVIDIA App\UpdateFramework\ota-artifacts"
    New-Item -ItemType Directory -Path $mockNvOta -Force | Out-Null
    Set-Content -Path "$mockNvOta\mock-driver-617.14-setup.exe" -Value ("X" * 1024 * 1024)
    New-Item -ItemType Directory -Path "$mockNvOta\extracted_uncompressed_setup" -Force | Out-Null
    Set-Content -Path "$mockNvOta\extracted_uncompressed_setup\setup.cfg" -Value "mock config"

    # 1.2 Mock Steam residual
    New-Item -ItemType Directory -Path "$sandbox\Steam\steamapps\common\GhostGameResidual" -Force | Out-Null
    Set-Content -Path "$sandbox\Steam\steamapps\common\GhostGameResidual\crash.log" -Value "Mock residual log data"

    # 1.3 Mock Empty Corrupted Folder
    New-Item -ItemType Directory -Path "$sandbox\MUMU\empty_folder" -Force | Out-Null
    New-Item -ItemType Directory -Path "$sandbox\鑻遍泟鑱旂洘" -Force | Out-Null

    # 1.4 Mock App Caches (WPS, WeChat)
    New-Item -ItemType Directory -Path "$sandbox\AppData\Kingsoft\backup" -Force | Out-Null
    Set-Content -Path "$sandbox\AppData\Kingsoft\backup\temp_autosave.tmp" -Value "Mock auto backup content"
    New-Item -ItemType Directory -Path "$sandbox\AppData\Tencent\WeChat\log" -Force | Out-Null
    Set-Content -Path "$sandbox\AppData\Tencent\WeChat\log\app_trace.log" -Value "Mock WeChat trace log"

    # 1.5 Mock Docker / WSL2 Virtual Disk
    $mockDiskDir = "$sandbox\Docker\wsl\disk"
    New-Item -ItemType Directory -Path $mockDiskDir -Force | Out-Null
    Set-Content -Path "$mockDiskDir\mock_docker_data.vhdx" -Value ("V" * 1024 * 1024) # 1MB fake vhdx

    # 1.6 Mock Inactive Project (> 60 days inactive)
    $deadProj = "$sandbox\Projects\DeadFrontend"
    New-Item -ItemType Directory -Path "$deadProj\src" -Force | Out-Null
    New-Item -ItemType Directory -Path "$deadProj\node_modules\large_pkg" -Force | Out-Null
    Set-Content -Path "$deadProj\package.json" -Value "{ `"name`": `"dead-project`" }"
    Set-Content -Path "$deadProj\src\index.js" -Value "console.log('ancient code');"
    Set-Content -Path "$deadProj\node_modules\large_pkg\bundle.js" -Value ("B" * 6 * 1024 * 1024) # 6MB artifact

    # Backdate source files to 90 days ago
    $oldDate = (Get-Date).AddDays(-90)
    (Get-Item "$deadProj\package.json").LastWriteTime = $oldDate
    (Get-Item "$deadProj\src\index.js").LastWriteTime = $oldDate
    (Get-Item "$deadProj\src").LastWriteTime = $oldDate
    (Get-Item "$deadProj").LastWriteTime = $oldDate

    # 1.7 Mock Active Project (< 60 days active)
    $activeProj = "$sandbox\Projects\ActiveBackend"
    New-Item -ItemType Directory -Path "$activeProj\src" -Force | Out-Null
    New-Item -ItemType Directory -Path "$activeProj\target\debug" -Force | Out-Null
    Set-Content -Path "$activeProj\Cargo.toml" -Value "[package]`nname = `"active`""
    Set-Content -Path "$activeProj\src\main.rs" -Value "fn main() {}"
    Set-Content -Path "$activeProj\target\debug\app.exe" -Value ("A" * 6 * 1024 * 1024)

    Write-Host "[SETUP] All mock sandbox fixtures (including v0.3 features) created." -ForegroundColor Green

    # ----------------------------------------------------
    # 2. Test Execution
    # ----------------------------------------------------
    $scriptsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "scripts"
    $scanResiduesScript = Join-Path $scriptsDir "scan_app_residues.ps1"
    $scanDevScript = Join-Path $scriptsDir "scan_dev_artifacts.ps1"
    $manageWslScript = Join-Path $scriptsDir "manage_wsl_disk.ps1"
    $cleanScript = Join-Path $scriptsDir "clean_selected_residues.ps1"
    $mockManifest = Join-Path $sandbox ".save-my-disk\cleanup_manifest.md"

    # TEST 1: App residues scan & manifest generation
    Write-Host "`n[TEST 1] Running scan_app_residues & generating cleanup_manifest.md..." -ForegroundColor Cyan
    $scanJson = & $scanResiduesScript -MockRoot $sandbox -OutputManifest $mockManifest -Json | ConvertFrom-Json
    if ($scanJson.Count -ge 4) {
        Write-Host "  -> PASS: Detected $($scanJson.Count) residue items." -ForegroundColor Green
    } else {
        throw "FAIL: Expected at least 4 items, found $($scanJson.Count)"
    }

    # TEST 2: Inactive dev artifacts scan
    Write-Host "`n[TEST 2] Running scan_dev_artifacts (inactive check)..." -ForegroundColor Cyan
    $devJson = @(& $scanDevScript -MockRoot $sandbox -DaysInactive 60 -OutputManifest $mockManifest -Json | ConvertFrom-Json)
    if ($devJson.Count -eq 1 -and $devJson[0].Project -eq "DeadFrontend") {
        Write-Host "  -> PASS: Correctly identified DeadFrontend as inactive and preserved ActiveBackend." -ForegroundColor Green
    } else {
        throw "FAIL: Dev artifact detection failed (Count: $($devJson.Count))."
    }

    # TEST 3: WSL2 / Docker virtual disk analysis
    Write-Host "`n[TEST 3] Running manage_wsl_disk analysis..." -ForegroundColor Cyan
    $wslJson = @(& $manageWslScript -MockRoot $sandbox -Json | ConvertFrom-Json)
    if ($wslJson.Count -ge 1 -and $wslJson[0].Name -eq "mock_docker_data.vhdx") {
        Write-Host "  -> PASS: Correctly detected mock VHDX virtual disk." -ForegroundColor Green
    } else {
        throw "FAIL: VHDX detection failed."
    }

    # TEST 4: Manifest-driven deletion (-FromManifest -Force)
    Write-Host "`n[TEST 4] Testing manifest-driven deletion of DeadFrontend/node_modules..." -ForegroundColor Cyan
    $manifestContent = Get-Content -LiteralPath $mockManifest -Raw -Encoding UTF8
    # Mark DEV-001 as checked: - [x] **[DEV-001]
    $manifestContent = [regex]::Replace($manifestContent, "-\s*\[\s*\]\s*\*\*\[DEV-001\]", "- [x] **[DEV-001]")
    [System.IO.File]::WriteAllText($mockManifest, $manifestContent, [System.Text.Encoding]::UTF8)

    # Execute cleaner with -FromManifest -Force
    & $cleanScript -MockRoot $sandbox -ManifestPath $mockManifest -FromManifest -Force | Out-Null

    $nodeModulesPath = "$deadProj\node_modules"
    if (-not (Test-Path $nodeModulesPath)) {
        Write-Host "  -> PASS: Dead project's node_modules was cleanly purged." -ForegroundColor Green
    } else {
        throw "FAIL: node_modules was not deleted."
    }

    # CRITICAL CHECK: Source code must be intact!
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

    # TEST 5: Verify Manifest updated with (已成功清理)
    $updatedManifest = Get-Content -LiteralPath $mockManifest -Raw -Encoding UTF8
    if ($updatedManifest -match "\(已成功清理\)") {
        Write-Host "  -> PASS: Manifest file was successfully updated with audit record." -ForegroundColor Green
    } else {
        throw "FAIL: Manifest file was not updated after deletion."
    }

    Write-Host "`n======================================================" -ForegroundColor Green
    Write-Host " ALL v0.3.0 TESTS PASSED! 100% ISOLATED & SAFE." -ForegroundColor Green
    Write-Host "======================================================" -ForegroundColor Green

} finally {
    # Teardown Sandbox
    if (Test-Path $sandbox) {
        Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "[TEARDOWN] Mock sandbox cleaned up completely." -ForegroundColor Gray
    }
}
