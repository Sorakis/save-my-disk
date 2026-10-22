<#
.SYNOPSIS
    WSL2 & Docker Desktop virtual disk (.vhdx) analysis and safe compaction engine.
.DESCRIPTION
    Analyzes virtual disk sizes, checks running state of WSL instances,
    and safely compacts virtual disks using diskpart to reclaim unused space.
.PARAMETER MockRoot
    Used for unit testing in an isolated mock sandbox.
.PARAMETER TargetVhdx
    Specific path to a .vhdx file. If omitted, auto-detects Docker Desktop and WSL distros.
.PARAMETER Compact
    Executes compaction routine. Requires Administrator rights and WSL shutdown.
.PARAMETER DryRun
    Simulates the action without shutting down WSL or running diskpart.
.PARAMETER Force
    Must be specified to actually execute compaction.
.PARAMETER Json
    Outputs structured JSON.
#>
param(
    [string]$MockRoot,
    [string]$TargetVhdx,
    [switch]$Compact,
    [switch]$DryRun,
    [switch]$Force,
    [switch]$Json
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$vhdxList = @()

if ($MockRoot) {
    $mockDiskDir = Join-Path $MockRoot "Docker\wsl\disk"
    if (Test-Path $mockDiskDir) {
        $files = Get-ChildItem -LiteralPath $mockDiskDir -Filter "*.vhdx" -ErrorAction SilentlyContinue
        foreach ($f in $files) {
            $vhdxList += [PSCustomObject]@{
                Name = $f.Name
                Path = $f.FullName
                SizeMB = [math]::Round($f.Length / 1MB, 2)
                SizeGB = [math]::Round($f.Length / 1GB, 2)
                Type = "Mock WSL2 Disk"
            }
        }
    }
} elseif ($TargetVhdx) {
    if (Test-Path -LiteralPath $TargetVhdx) {
        $item = Get-Item -LiteralPath $TargetVhdx -Force
        $vhdxList += [PSCustomObject]@{
            Name = $item.Name
            Path = $item.FullName
            SizeMB = [math]::Round($item.Length / 1MB, 2)
            SizeGB = [math]::Round($item.Length / 1GB, 2)
            Type = "Custom Target"
        }
    }
} else {
    # Auto-detect Docker Desktop WSL2 disk
    $dockerVhdx = "$env:LOCALAPPDATA\Docker\wsl\disk\docker_data.vhdx"
    if (Test-Path $dockerVhdx) {
        $item = Get-Item -LiteralPath $dockerVhdx -Force
        $vhdxList += [PSCustomObject]@{
            Name = "Docker Desktop Data (docker_data.vhdx)"
            Path = $item.FullName
            SizeMB = [math]::Round($item.Length / 1MB, 2)
            SizeGB = [math]::Round($item.Length / 1GB, 2)
            Type = "Docker Desktop WSL2"
        }
    }

    # Auto-detect Default WSL distros in LocalAppData\Packages
    $wslPackages = "$env:LOCALAPPDATA\Packages"
    if (Test-Path $wslPackages) {
        $foundVhdx = Get-ChildItem -LiteralPath $wslPackages -Filter "ext4.vhdx" -Recurse -File -Force -ErrorAction SilentlyContinue
        foreach ($v in $foundVhdx) {
            $vhdxList += [PSCustomObject]@{
                Name = "WSL Distro (" + $v.Directory.Parent.Name + ")"
                Path = $v.FullName
                SizeMB = [math]::Round($v.Length / 1MB, 2)
                SizeGB = [math]::Round($v.Length / 1GB, 2)
                Type = "Generic WSL2 Distro"
            }
        }
    }
}

if (-not $Compact) {
    if ($Json) {
        $vhdxList | ConvertTo-Json -Depth 3
    } else {
        Write-Host "`n=== DETECTED WSL2 / DOCKER VIRTUAL DISKS ===" -ForegroundColor Cyan
        if ($vhdxList.Count -eq 0) {
            Write-Host "No WSL2 or Docker virtual disks detected." -ForegroundColor Green
        } else {
            $vhdxList | Select-Object Name, SizeGB, SizeMB, Path | Format-Table -AutoSize
            Write-Host "Recommendation: If disk is bloated, shut down containers and run with -Compact -Force to shrink." -ForegroundColor Yellow
        }
    }
    exit 0
}

# --- Compaction Workflow ---
Write-Host "`n=== WSL2 / DOCKER VHDX COMPACTION ROUTINE ===" -ForegroundColor Yellow

if ($vhdxList.Count -eq 0) {
    Write-Warning "No virtual disks found to compact."
    exit 0
}

if ($DryRun -or (-not $Force)) {
    Write-Host "[DRY RUN MODE] -Force was not specified. No actions executed." -ForegroundColor Cyan
    Write-Host "Would perform the following safety steps:" -ForegroundColor Gray
    Write-Host "  1. Execute 'wsl --shutdown' to cleanly unmount disks" -ForegroundColor Gray
    Write-Host "  2. Run diskpart script on target vhdx (attach readonly -> compact vdisk -> detach)" -ForegroundColor Gray
    Write-Host "To execute after user confirmation, re-run with -Compact -Force." -ForegroundColor Yellow
    exit 0
}

# Check Admin Privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "COMPACT FAILED: Diskpart compaction requires Administrator privileges. Run PowerShell as Administrator."
    exit 1
}

# Real execution (skipped if MockRoot)
if ($MockRoot) {
    Write-Host "[MOCK SANDBOX] Simulated diskpart compact on mock vhdx." -ForegroundColor Green
    exit 0
}

Write-Host "Step 1/3: Shutting down WSL instances safely..." -ForegroundColor Cyan
wsl --shutdown
Start-Sleep -Seconds 3

foreach ($target in $vhdxList) {
    $vPath = $target.Path
    Write-Host "Step 2/3: Compacting virtual disk: $vPath ..." -ForegroundColor Cyan

    $diskpartScript = "$env:TEMP\diskpart_compact_$((Get-Random)).txt"
    $scriptContent = @"
select vdisk file="$vPath"
attach vdisk readonly
compact vdisk
detach vdisk
exit
"@
    Set-Content -LiteralPath $diskpartScript -Value $scriptContent -Encoding ASCII

    try {
        diskpart /s $diskpartScript | Out-Null
        Write-Host "Compaction completed for: $($target.Name)" -ForegroundColor Green
    } catch {
        Write-Warning "Diskpart error on $vPath : $($_.Exception.Message)"
    } finally {
        if (Test-Path $diskpartScript) {
            Remove-Item -LiteralPath $diskpartScript -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Host "`nStep 3/3: Re-evaluating compacted sizes..." -ForegroundColor Cyan
& $PSCommandPath -Json
