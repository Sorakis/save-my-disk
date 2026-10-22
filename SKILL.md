---
name: save-my-disk
description: >-
  Sensitive high-stakes disk optimization runbook.
  ONLY activate this skill when the user EXPLICITLY requests "save-my-disk",
  specifically asks to invoke the "save-my-disk" skill, or issues a direct
  command to audit/clean disk space.
  NEVER trigger implicitly during unrelated coding or conversation turns.
---

# Save My Disk (save-my-disk) Skill 🚀

> **安全准则**：本技能属于敏感运维操作。**必须在用户显式呼叫时才启动**。任何阶段严禁暗中执行删除动作，所有清理步骤均须呈批候选清单并获得用户靶向授权。

## Core Rules for Any Agent

1. **Explicit Call Only (显式触发)**: Do not trigger or suggest disk cleanup unless the user explicitly mentions `save-my-disk` or specifically requests a storage audit.
2. **Read-Only First (只读体检)**: Never delete, move, or modify any file during the initial audit phase.
3. **Itemize Before Clean (清单呈批)**: When scanning app residues or caches, present an itemized list with unique IDs (e.g. `RES-001`) and paths to the user.
4. **Explicit Confirmation (靶向授权)**: Only execute deletion for targets explicitly confirmed by the user.
5. **Post-Cleanup Verification (战果自愈)**: Always verify volume capacity and critical service health after any deletion using [scripts/verify_health.ps1](./scripts/verify_health.ps1).

---

## Standard 4-Phase Workflow

### Phase 1: Non-Invasive Audit (只读体检)
Run the read-only audit script to collect volume metrics and hotspot sizes:
```powershell
powershell -ExecutionPolicy Bypass -File ./scripts/audit_drives.ps1 -Json
```

To scan for specific software residues (Steam uninstalled game remnants, empty dirs, WPS/QQ/WeChat caches):
```powershell
powershell -ExecutionPolicy Bypass -File ./scripts/scan_app_residues.ps1 -Json
```

### Phase 2: Risk-Tiered Triage & Candidate Listing (风险分级与清单呈现)
Consult [references/safety_matrix.md](./references/safety_matrix.md):
- **Tier 1 (Zero Risk / Hotspots)**: Windows Update cache, `$WINDOWS.~BT`, Temp files, Recycle Bin.
- **Tier 2 (Developer Caches)**: Docker `docker_data.vhdx`, Conda package cache, `.cache` runtimes, `npm-cache`.
- **Tier 3 (App Residues & Safe Caches)**: Steam uninstalled game leftovers, WPS backup cache, QQ/WeChat crash dumps, Feishu logs.
- **Tier 4 (Forbidden Red Line)**: `System32`, `WinSxS`, user project directories, `pagefile.sys`.

**IMPORTANT**: Present Tier 3 items in a clear Markdown table with their `ID`, `Name`, `SizeMB`, and `Path`. Ask the user which items they want to clean.

### Phase 3: Dual-Track Execution (双轨清理执行)

#### Track A: Automated Execution (Agent executes upon user confirmation)
1. **Windows Update Cache Cleanup**:
   ```powershell
   powershell -ExecutionPolicy Bypass -File ./scripts/clean_windows_update.ps1
   ```
2. **Selective App Residue Cleanup** (Only cleans user-confirmed IDs):
   ```powershell
   powershell -ExecutionPolicy Bypass -File ./scripts/clean_selected_residues.ps1 -TargetIds RES-001,RES-002 -Force
   ```
3. **User Temp Directory Cleanup**:
   ```powershell
   powershell -ExecutionPolicy Bypass -File ./scripts/clean_user_temp.ps1
   ```

#### Track B: Guided Human Execution (Agent provides step-by-step instructions)
1. **System Upgrade Residuals ($WINDOWS.~BT)**: Follow [references/cleanmgr_guide.md](./references/cleanmgr_guide.md).
2. **Docker WSL Virtual Disk Migration**: Follow [references/dev_cache_guide.md](./references/dev_cache_guide.md).
3. **Major Chat Storage**: Guide user to in-app settings (WeChat/Feishu).

### Phase 4: Post-Cleanup Verification (自愈与战果核验)
Execute the verification script:
```powershell
powershell -ExecutionPolicy Bypass -File ./scripts/verify_health.ps1
```
Report the exact delta (space reclaimed in GB) and verify that the `wuauserv` service is `Running`.
