# CLAUDE.md - Save My Disk (save-my-disk) Guidelines 🚀 (v0.5.1)

This file configures Claude Code when working in this project or utilizing this skill.

## 🚨 Security Policy: Explicit Invocation Only
- **Do NOT trigger implicitly**: Only execute when user explicitly mentions `save-my-disk` or directly requests disk triage.
- **Always Run Audit First**: Never attempt deletions before scanning with `audit_drives.ps1` and `scan_app_residues.ps1`.
- **Dual-Channel Reporting (Mandatory)**:
  1. Print the full 4-Tier candidate table directly into the chat response (including 0 MB healthy status for Windows upgrade files `$WINDOWS.~BT` / `Windows.old`).
  2. Provide the clickable local file link to `[.save-my-disk/cleanup_manifest.md](file:///path/to/.save-my-disk/cleanup_manifest.md)`.
  3. Inform the user of both confirmation methods: chat reply (e.g. "清理 SYS-001 和 IM-001") or marking `[x]` in the manifest file.
- **Require User Consent**: Always require explicit confirmation before executing `clean_selected_residues.ps1` or `clean_windows_update.ps1`.
- **Absolute Chat Database Immunity**: Never list or delete any `*.db`, `*.kvdb`, `Msg`, or `db_storage` chat history database.
- **Reference Safety Matrix**: Consult `references/safety_matrix.md` when recommending actions for unknown paths.
- **Service Verification**: Check that `wuauserv` service is `Running` after update cache purges.

## Commands
- **Audit Storage (Read-Only)**: `powershell -ExecutionPolicy Bypass -File ./scripts/audit_drives.ps1`
- **Audit Storage (JSON)**: `powershell -ExecutionPolicy Bypass -File ./scripts/audit_drives.ps1 -Json`
- **Scan 4-Tier Residues**: `powershell -ExecutionPolicy Bypass -File ./scripts/scan_app_residues.ps1 -OutputManifest ./.save-my-disk/cleanup_manifest.md -Json`
- **Scan Package Caches**: `powershell -ExecutionPolicy Bypass -File ./scripts/scan_package_caches.ps1 -OutputManifest ./.save-my-disk/cleanup_manifest.md -Json`
- **Scan AI Models**: `powershell -ExecutionPolicy Bypass -File ./scripts/scan_ai_models.ps1 -OutputManifest ./.save-my-disk/cleanup_manifest.md -Json`
- **Scan IM & Office Caches**: `powershell -ExecutionPolicy Bypass -File ./scripts/scan_im_office_residues.ps1 -OutputManifest ./.save-my-disk/cleanup_manifest.md -Json`
- **Scan Inactive Dev Artifacts**: `powershell -ExecutionPolicy Bypass -File ./scripts/scan_dev_artifacts.ps1 -DaysInactive 60 -OutputManifest ./.save-my-disk/cleanup_manifest.md -Json`
- **Analyze WSL2 / Docker Disk**: `powershell -ExecutionPolicy Bypass -File ./scripts/manage_wsl_disk.ps1 -Json`
- **Clean Confirmed Targets**: `powershell -ExecutionPolicy Bypass -File ./scripts/clean_selected_residues.ps1 -FromManifest -Force`
- **Compact WSL2 / Docker Disk (Requires Admin)**: `powershell -ExecutionPolicy Bypass -File ./scripts/manage_wsl_disk.ps1 -Compact -Force`
- **Clean Update Cache (Requires Admin & User Consent)**: `powershell -ExecutionPolicy Bypass -File ./scripts/clean_windows_update.ps1`
- **Clean Temp Files**: `powershell -ExecutionPolicy Bypass -File ./scripts/clean_user_temp.ps1`
- **Verify Status**: `powershell -ExecutionPolicy Bypass -File ./scripts/verify_health.ps1`
