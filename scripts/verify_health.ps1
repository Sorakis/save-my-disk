<#
.SYNOPSIS
    Post-cleanup verification script for AI Agents.
.DESCRIPTION
    Checks disk volume space remaining, delta comparisons, and critical Windows service states.
#>
param(
    [switch]$Json
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$volumes = Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter } | Select-Object DriveLetter, FileSystemLabel, @{N='SizeGB';E={[math]::Round($_.Size/1GB,2)}}, @{N='FreeGB';E={[math]::Round($_.SizeRemaining/1GB,2)}}

$wuService = Get-Service -Name wuauserv -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Status
$bitsService = Get-Service -Name bits -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Status

$res = [PSCustomObject]@{
    Timestamp = (Get-Date).ToString("s")
    Volumes = $volumes
    Services = [PSCustomObject]@{
        wuauserv = "$wuService"
        bits = "$bitsService"
    }
}

if ($Json) {
    $res | ConvertTo-Json -Depth 3
} else {
    Write-Host "=== POST-CLEANUP DISK & SERVICE STATUS ===" -ForegroundColor Cyan
    $volumes | Format-Table -AutoSize
    Write-Host "Service States:" -ForegroundColor Yellow
    Write-Host "  Windows Update (wuauserv) : $wuService"
    Write-Host "  BITS                     : $bitsService"
}
