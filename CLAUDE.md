# CLAUDE.md - Save My Disk (save-my-disk) Guidelines 🚀

This file configures Claude Code when working in this project or utilizing this skill.

## Commands
- **Audit Storage**: `powershell -ExecutionPolicy Bypass -File ./scripts/audit_drives.ps1`
- **Audit Storage (JSON)**: `powershell -ExecutionPolicy Bypass -File ./scripts/audit_drives.ps1 -Json`
- **Clean Update Cache (Requires Admin & User Confirmation)**: `powershell -ExecutionPolicy Bypass -File ./scripts/clean_windows_update.ps1`
- **Clean Temp Files**: `powershell -ExecutionPolicy Bypass -File ./scripts/clean_user_temp.ps1`
- **Verify Status**: `powershell -ExecutionPolicy Bypass -File ./scripts/verify_health.ps1`

## Operational Guidelines
- **Always Run Audit First**: Never attempt deletions before scanning with `audit_drives.ps1`.
- **Require User Consent**: Always prompt the user before executing `clean_windows_update.ps1` or `clean_user_temp.ps1`.
- **Reference Safety Matrix**: Consult `references/safety_matrix.md` when recommending actions for unknown paths.
- **Service Verification**: Check that `wuauserv` service is `Running` after update cache purges.
