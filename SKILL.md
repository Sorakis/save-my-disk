---
name: save-my-disk
description: >-
  Sensitive high-stakes disk optimization runbook.
  ONLY activate this skill when the user EXPLICITLY requests "save-my-disk",
  specifically asks to invoke the "save-my-disk" skill, or issues a direct
  command to audit/clean disk space.
  NEVER trigger implicitly during unrelated coding or conversation turns.
---

# Save My Disk (save-my-disk) Skill 🚀 (v0.5.3)

> **安全准则**：本技能属于系统级敏感运维操作。**必须在用户显式呼叫时才启动**。任何阶段严禁暗中执行删除动作，所有清理步骤均须呈批候选清单并获得用户靶向授权。

## Core Rules for Any Agent

1. **Explicit Call Only (显式触发)**: Do not trigger or suggest disk cleanup unless the user explicitly mentions `save-my-disk` or specifically requests a storage audit.
2. **Read-Only First (只读体检)**: Never delete, move, or modify any file during the initial audit phase.
3. **Itemize Before Clean (清单呈批)**: Present an itemized list with unique IDs (`SYS-xxx`, `RES-xxx`, `DEV-xxx`, `PKG-xxx`, `AI-xxx`, `IM-xxx`, `BRW-xxx`) in `.save-my-disk/cleanup_manifest.md`.
4. **Preserve Source Code, Chat Databases & Browser Credentials (绝不误伤源码、聊天数据库与浏览器凭证)**: When cleaning inactive dev artifacts, IM caches, or browser/system caches, NEVER delete project root, source files, chat history databases (`*.db`, `*.kvdb`, `Msg`, `db_storage`), or browser credentials/user profiles (`Login Data`, `Cookies`, `History`, `Bookmarks`, `places.sqlite`, `key4.db`).
5. **Dual-Channel Reporting (双轨直呈与透明建档 - 必须严格执行)**:
   * **通道一 (对话框直报)**：体检完成后，Agent **必须**在对话框气泡中直接打印完整的 **4 级风险梯度 (4-Tier) Markdown 表格**，包括已清理项的状态（如 `$WINDOWS.~BT` 汇报 0 MB 健康状态，解答用户关于 cleanmgr 的疑问），让用户无需打开文件即可一览无余。
   * **通道二 (可点击清单)**：Agent **必须**在回复中提供本地清单文件的绝对路径可点击链接（`[.save-my-disk/cleanup_manifest.md](file:///绝对路径/.save-my-disk/cleanup_manifest.md)`），明确告知用户该文件是人机同步的单一真实事实来源（SSOT）。
   * **双轨决策确认指引**：明确向用户说明两种确认方式：
     * **方式 A (对话框直接回复)**：在聊天框回复编号（如“清理 SYS-001 和 IM-001”）；
     * **方式 B (清单文件打勾确认)**：直接打开 `cleanup_manifest.md` 将目标项改为 `[x]` 保存后回复“已勾选，按清单清理”。
6. **Explicit Confirmation (靶向授权)**: Only execute deletion for targets explicitly confirmed by the user.
7. **Post-Cleanup Verification (战果自愈)**: Always verify volume capacity and critical service health after any deletion using [scripts/verify_health.ps1](./scripts/verify_health.ps1).

---

## Standard Workflow

### Phase 1: Non-Invasive 4-Tier Audit (只读体检与建档)
1. Volume & Hotspot Scan:
   ```powershell
   powershell -ExecutionPolicy Bypass -File ./scripts/audit_drives.ps1 -Json
   ```
2. Application Residues & Safe Caches Scan (Generates 4-Tier Manifest base):
   ```powershell
   powershell -ExecutionPolicy Bypass -File ./scripts/scan_app_residues.ps1 -OutputManifest ./.save-my-disk/cleanup_manifest.md -Json
   ```
3. Browser & GPU Shader Caches Scan (Chrome, Edge, Brave, Firefox, DirectX/NVIDIA Shader Caches):
   ```powershell
   powershell -ExecutionPolicy Bypass -File ./scripts/scan_browser_system_caches.ps1 -OutputManifest ./.save-my-disk/cleanup_manifest.md -Json
   ```
4. Global Package Manager Caches Scan (pip, npm, Conda, Gradle):
   ```powershell
   powershell -ExecutionPolicy Bypass -File ./scripts/scan_package_caches.ps1 -OutputManifest ./.save-my-disk/cleanup_manifest.md -Json
   ```
5. AI/ML Model Storage Scan (Hugging Face, Ollama, PyTorch checkpoints):
   ```powershell
   powershell -ExecutionPolicy Bypass -File ./scripts/scan_ai_models.ps1 -OutputManifest ./.save-my-disk/cleanup_manifest.md -Json
   ```
6. Domestic IM & Office Caches Scan (WeChat 3.x/4.0, WXWork, QQ, Feishu, DingTalk):
   ```powershell
   powershell -ExecutionPolicy Bypass -File ./scripts/scan_im_office_residues.ps1 -OutputManifest ./.save-my-disk/cleanup_manifest.md -Json
   ```
7. Inactive Developer Build Artifacts Scan (> 60 days inactive, auto-inserts into Tier 2):
   ```powershell
   powershell -ExecutionPolicy Bypass -File ./scripts/scan_dev_artifacts.ps1 -DaysInactive 60 -OutputManifest ./.save-my-disk/cleanup_manifest.md -Json
   ```
8. WSL2 & Docker VHDX Analysis:
   ```powershell
   powershell -ExecutionPolicy Bypass -File ./scripts/manage_wsl_disk.ps1 -Json
   ```

### Phase 2: Dual-Channel Reporting & User Decision (双轨汇报与呈批)
Agent 必须在对话中向用户输出：
1. **直接在聊天框呈现 4-Tier 候选表格**（Tier 1 零风险系统项与包缓存、Tier 2 开发者权衡项与AI大模型、Tier 3 软件残留、Tier 4 保护红线）。
2. **给出本地清单文件的可点击链接**：`[.save-my-disk/cleanup_manifest.md](file:///绝对路径/.save-my-disk/cleanup_manifest.md)`。
3. **可选择提供单文件 HTML 可视化战报链接**（经由 `export_dashboard.ps1` 生成的 `[.save-my-disk/disk_triage_report.html](file:///绝对路径/.save-my-disk/disk_triage_report.html)`）。
4. **提示用户两种确认清理的方式**（对话框回复编号 / 清单打勾保存）。

### Phase 3: Controlled Execution (受控靶向执行)
1. **Targeted Residues / Dev Artifacts / Package Caches / AI Models / System Caches**:
   ```powershell
   # Via checked boxes in manifest
   powershell -ExecutionPolicy Bypass -File ./scripts/clean_selected_residues.ps1 -FromManifest -Force
   # Or via explicit IDs
   powershell -ExecutionPolicy Bypass -File ./scripts/clean_selected_residues.ps1 -TargetIds SYS-001,RES-001,PKG-001,DEV-001 -Force
   ```
2. **WSL2 / Docker VHDX Compaction (Requires Admin & User Consent)**:
   ```powershell
   powershell -ExecutionPolicy Bypass -File ./scripts/manage_wsl_disk.ps1 -Compact -Force
   ```
3. **Windows Update Cache (Requires Admin & User Consent)**:
   ```powershell
   powershell -ExecutionPolicy Bypass -File ./scripts/clean_windows_update.ps1
   ```

### Phase 4: Post-Cleanup Verification & Visual Dashboard (战果自愈与战报刷新)
```powershell
powershell -ExecutionPolicy Bypass -File ./scripts/verify_health.ps1 -ExportHtml
```
