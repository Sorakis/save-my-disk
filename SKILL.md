---
name: save-my-disk
description: >-
  Sensitive high-stakes disk optimization runbook.
  ONLY activate this skill when the user EXPLICITLY requests "save-my-disk",
  specifically asks to invoke the "save-my-disk" skill, or issues a direct
  command to audit/clean disk space.
  NEVER trigger implicitly during unrelated coding or conversation turns.
---

# Save My Disk (save-my-disk) Skill 🚀 (v0.3.0)

> **安全准则**：本技能属于敏感运维操作。**必须在用户显式呼叫时才启动**。任何阶段严禁暗中执行删除动作，所有清理步骤均须呈批候选清单并获得用户靶向授权。

## Core Rules for Any Agent

1. **Explicit Call Only (显式触发)**: Do not trigger or suggest disk cleanup unless the user explicitly mentions `save-my-disk` or specifically requests a storage audit.
2. **Read-Only First (只读体检)**: Never delete, move, or modify any file during the initial audit phase.
3. **Itemize Before Clean (清单呈批)**: Present an itemized list with unique IDs (e.g. `RES-001`, `DEV-001`) and paths in `.save-my-disk/cleanup_manifest.md`.
4. **Preserve Source Code (绝不误伤源码)**: When cleaning inactive dev artifacts (e.g. `node_modules`, `target`), NEVER delete project root or source files.
5. **Explicit Confirmation (靶向授权)**: Only execute deletion for targets explicitly confirmed by the user.
6. **Post-Cleanup Verification (战果自愈)**: Always verify volume capacity and critical service health after any deletion using [scripts/verify_health.ps1](./scripts/verify_health.ps1).

---

## Standard Workflow

### Phase 1: Non-Invasive Audit (只读体检)
1. Volume & Hotspot Scan:
   ```powershell
   powershell -ExecutionPolicy Bypass -File ./scripts/audit_drives.ps1 -Json
   ```
2. Application Residues & Safe Caches Scan:
   ```powershell
   powershell -ExecutionPolicy Bypass -File ./scripts/scan_app_residues.ps1 -Json
   ```
3. Inactive Developer Build Artifacts Scan (> 60 days inactive):
   ```powershell
   powershell -ExecutionPolicy Bypass -File ./scripts/scan_dev_artifacts.ps1 -DaysInactive 60 -OutputManifest ./.save-my-disk/cleanup_manifest.md -Json
   ```
4. WSL2 & Docker VHDX Analysis:
   ```powershell
   powershell -ExecutionPolicy Bypass -File ./scripts/manage_wsl_disk.ps1 -Json
   ```

### Phase 2: Manifest Review & User Decision (清单呈批)
Point user to `.save-my-disk/cleanup_manifest.md`. The user can:
- Mark desired checkboxes `- [x]` directly in their editor; OR
- Reply with IDs in chat (e.g. "清理 RES-001 和 DEV-001").

### Phase 3: Controlled Execution (受控执行)
1. **Targeted Residues / Dev Artifacts**:
   ```powershell
   # Via checked boxes in manifest
   powershell -ExecutionPolicy Bypass -File ./scripts/clean_selected_residues.ps1 -FromManifest -Force
   # Or via explicit IDs
   powershell -ExecutionPolicy Bypass -File ./scripts/clean_selected_residues.ps1 -TargetIds RES-001,DEV-001 -Force
   ```
2. **WSL2 / Docker VHDX Compaction (Requires Admin & User Consent)**:
   ```powershell
   powershell -ExecutionPolicy Bypass -File ./scripts/manage_wsl_disk.ps1 -Compact -Force
   ```
3. **Windows Update Cache (Requires Admin & User Consent)**:
   ```powershell
   powershell -ExecutionPolicy Bypass -File ./scripts/clean_windows_update.ps1
   ```

### Phase 4: Post-Cleanup Verification (自愈核验)
```powershell
powershell -ExecutionPolicy Bypass -File ./scripts/verify_health.ps1
```
