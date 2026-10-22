# Universal Multi-Agent Specification: Save My Disk (save-my-disk) 🚀 (v0.5.1)

This specification defines how **ANY AI Agent framework** (WorkBuddy, Cursor, Windsurf, AutoGen, CrewAI, LangChain, OpenAI Codex, Claude Code, OpenCode, DeepSeek Harness, etc.) should discover, expose, and safely execute this toolset.

---

## 🚨 Explicit Invocation Policy (必须显式调用)

> **CRITICAL SECURITY GUARDRAIL FOR ALL AGENTS**:
> 磁盘运维属于系统高危敏感操作。
> 1. **严禁隐式触发**：在用户进行普通写代码、日常问答时，AI 严禁擅自启动本技能或自作主张执行磁盘清理。
> 2. **必须显式唤起**：只有当用户在提示词中明确提到 `save-my-disk`，或直接要求对磁盘进行体检与清理时，方可激活本规范。
> 3. **清单呈批与双轨直呈**：任何删除命令前，必须先生成结构化 4-Tier 候选清单（带 `SYS-xxx`, `RES-xxx`, `DEV-xxx`, `PKG-xxx`, `AI-xxx`, `IM-xxx` 独立编号），**既要在聊天窗口完整直呈表格，也要提供本地清单文件链接**，获得用户明确授权确认后方可执行。

---

## Agent Detection & Activation Triggers
Only activate this runbook when user prompt explicitly matches:
* "save-my-disk", "调用 save-my-disk", "运行 save-my-disk 技能"
* "系统盘清理体检", "检查磁盘空间残留" (Explicit storage intent)

---

## Tool & Function Calling Schemas
For agents that support OpenAI-compatible function calling or MCP (such as WorkBuddy, Cursor, Claude Desktop, AutoGen):
* See [`tools/tool_definitions.json`](./tools/tool_definitions.json) for standard JSON Schema declarations.
* See [`tools/mcp.json`](./tools/mcp.json) for Model Context Protocol configuration.

---

## CLI Command Registry for Agents

All scripts reside in `./scripts/` with zero external dependencies and support standard exit codes and structured JSON output.

| Capability | Command | Mode | Safe to Auto-Run? |
| :--- | :--- | :--- | :--- |
| **Audit Drives** | `powershell -ExecutionPolicy Bypass -File ./scripts/audit_drives.ps1 -Json` | Read-Only | **YES** |
| **Scan 4-Tier Residues** | `powershell -ExecutionPolicy Bypass -File ./scripts/scan_app_residues.ps1 -OutputManifest ./.save-my-disk/cleanup_manifest.md -Json` | Read-Only | **YES** |
| **Scan Package Caches** | `powershell -ExecutionPolicy Bypass -File ./scripts/scan_package_caches.ps1 -OutputManifest ./.save-my-disk/cleanup_manifest.md -Json` | Read-Only | **YES** |
| **Scan AI Models** | `powershell -ExecutionPolicy Bypass -File ./scripts/scan_ai_models.ps1 -OutputManifest ./.save-my-disk/cleanup_manifest.md -Json` | Read-Only | **YES** |
| **Scan IM & Office Caches** | `powershell -ExecutionPolicy Bypass -File ./scripts/scan_im_office_residues.ps1 -OutputManifest ./.save-my-disk/cleanup_manifest.md -Json` | Read-Only | **YES** |
| **Scan Inactive Dev Artifacts** | `powershell -ExecutionPolicy Bypass -File ./scripts/scan_dev_artifacts.ps1 -DaysInactive 60 -OutputManifest ./.save-my-disk/cleanup_manifest.md -Json` | Read-Only | **YES** |
| **Analyze WSL2 / Docker Disk** | `powershell -ExecutionPolicy Bypass -File ./scripts/manage_wsl_disk.ps1 -Json` | Read-Only | **YES** |
| **Clean Confirmed Targets** | `powershell -ExecutionPolicy Bypass -File ./scripts/clean_selected_residues.ps1 -FromManifest -Force` | Modifying | **NO** (Must confirm with user first) |
| **Compact WSL2 / Docker Disk** | `powershell -ExecutionPolicy Bypass -File ./scripts/manage_wsl_disk.ps1 -Compact -Force` | Modifying | **NO** (Requires admin & user confirmation) |
| **Clean Update Cache** | `powershell -ExecutionPolicy Bypass -File ./scripts/clean_windows_update.ps1` | Modifying | **NO** (Requires admin & user confirmation) |
| **Clean User Temp** | `powershell -ExecutionPolicy Bypass -File ./scripts/clean_user_temp.ps1` | Modifying | **NO** (Must confirm with user first) |
| **Post-Check Health** | `powershell -ExecutionPolicy Bypass -File ./scripts/verify_health.ps1 -Json` | Read-Only | **YES** |

---

## Standard Multi-Agent Protocol & Dual-Channel Rule

1. **Step 1: Discover & Audit (只读体检)**
   Run `audit_drives.ps1 -Json`, `scan_app_residues.ps1 -OutputManifest ./.save-my-disk/cleanup_manifest.md -Json`, `scan_package_caches.ps1 -OutputManifest ./.save-my-disk/cleanup_manifest.md -Json`, `scan_ai_models.ps1 -OutputManifest ./.save-my-disk/cleanup_manifest.md -Json`, `scan_im_office_residues.ps1 -OutputManifest ./.save-my-disk/cleanup_manifest.md -Json`, and `scan_dev_artifacts.ps1 -DaysInactive 60 -OutputManifest ./.save-my-disk/cleanup_manifest.md -Json`.

2. **Step 2: Dual-Channel Presentation (双轨直呈呈批 - 必须执行)**
   * **通道一 (对话框直呈)**：Agent 必须在聊天框中输出清晰的 4-Tier 分类 Markdown 表格：
     * 🟢 **Tier 1 (零风险系统与日志项)**：包含 Windows 升级备份状态（若为 0 MB 明确提示“已由系统自动清理/健康”）、Windows Update 补丁缓存、Temp 文件、pip/npm/Gradle 临时下载缓存、飞书/钉钉排错日志。
     * 🟡 **Tier 2 (开发者权衡、AI大模型与沉睡文档)**：NVIDIA 驱动离线安装包、沉睡工程构建产物 (`DEV-xxx`)、WSL2/Docker 虚拟磁盘、Hugging Face/Ollama/PyTorch 模型快照 (`AI-xxx`)、微信 3.x/4.0 历史接收文档与聊天图片 (`IM-xxx`)。
     * 🟠 **Tier 3 (应用残留与流媒体缓存)**：Steam 卸载空壳、微信 3.x/4.0/企微/QQ 视频播放缓存与表情缩略图 (`IM-xxx`)、办公/通讯软件诊断日志 (`RES-xxx`)。
     * 🔴 **Tier 4 (保护红线)**：声明系统核心、Conda 激活环境 (`envs/`)、**所有微信/QQ聊天记录核心数据库 (`*.db`, `*.kvdb`, `db_storage`, `Msg`)** 与正在工作的项目源码绝对安全免疫。
   * **通道二 (可点击清单路径)**：明确给出本地清单文件路径链接：`[.save-my-disk/cleanup_manifest.md](file:///绝对路径/.save-my-disk/cleanup_manifest.md)`。
   * **确认指引**：明确说明两种确认清理方式：
     * 方式 A：在对话框回复想要清理的编号（如：“清理 SYS-001 和 IM-001”）；
     * 方式 B：在本地 `cleanup_manifest.md` 文件中将 `[ ]` 改为 `[x]` 保存后回复：“已勾选，按清单清理”。

3. **Step 3: Guarded Execution (受控执行)**
   Only pass the user-confirmed IDs to `clean_selected_residues.ps1 -TargetIds ... -Force` or run with `-FromManifest -Force`.

4. **Step 4: Verify & Report (战果自愈)**
   Run `verify_health.ps1 -Json` to confirm recovered space and ensure system services are healthy.
