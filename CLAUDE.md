# CLAUDE.md - Save My Disk (save-my-disk) Guidelines 🚀

This file configures Claude Code when working in this project or utilizing this skill.

## 🚨 Security Policy: Explicit Invocation Only
- **Do NOT trigger implicitly**: Only execute when user explicitly mentions `save-my-disk` or directly requests disk triage.
- **Always Run Audit First**: Never attempt deletions before scanning with `audit_drives.ps1`.
- **Require User Consent**: Always output candidate IDs (e.g. `RES-001`) and prompt the user before executing `clean_selected_residues.ps1` or `clean_windows_update.ps1`.
- **Reference Safety Matrix**: Consult `references/safety_matrix.md` when recommending actions for unknown paths.
- **Service Verification**: Check that `wuauserv` service is `Running` after update cache purges.

## Commands
- **Audit Storage (Read-Only)**: `powershell -ExecutionPolicy Bypass -File ./scripts/audit_drives.ps1`
- **Audit Storage (JSON)**: `powershell -ExecutionPolicy Bypass -File ./scripts/audit_drives.ps1 -Json`
- **Scan Residues & Caches**: `powershell -ExecutionPolicy Bypass -File ./scripts/scan_app_residues.ps1`
- **Scan Inactive Dev Artifacts**: `powershell -ExecutionPolicy Bypass -File ./scripts/scan_dev_artifacts.ps1 -DaysInactive 60`
- **Analyze WSL2 / Docker Disk**: `powershell -ExecutionPolicy Bypass -File ./scripts/manage_wsl_disk.ps1`
- **Clean Confirmed Targets**: `powershell -ExecutionPolicy Bypass -File ./scripts/clean_selected_residues.ps1 -FromManifest -Force`
- **Compact WSL2 / Docker Disk (Requires Admin)**: `powershell -ExecutionPolicy Bypass -File ./scripts/manage_wsl_disk.ps1 -Compact -Force`
- **Clean Update Cache (Requires Admin & User Consent)**: `powershell -ExecutionPolicy Bypass -File ./scripts/clean_windows_update.ps1`
- **Clean Temp Files**: `powershell -ExecutionPolicy Bypass -File ./scripts/clean_user_temp.ps1`
- **Verify Status**: `powershell -ExecutionPolicy Bypass -File ./scripts/verify_health.ps1`
