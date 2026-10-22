# Universal Multi-Agent Specification: Save My Disk (save-my-disk) 🚀

This specification defines how **ANY AI Agent framework** (WorkBuddy, Cursor, Windsurf, AutoGen, CrewAI, LangChain, OpenAI Codex, Claude Code, OpenCode, DeepSeek Harness, etc.) should discover, expose, and safely execute this toolset.

---

## 🚨 Explicit Invocation Policy (必须显式调用)

> **CRITICAL SECURITY GUARDRAIL FOR ALL AGENTS**:
> 磁盘运维属于系统高危敏感操作。
> 1. **严禁隐式触发**：在用户进行普通写代码、日常问答时，AI 严禁擅自启动本技能或自作主张执行磁盘清理。
> 2. **必须显式唤起**：只有当用户在提示词中明确提到 `save-my-disk`，或直接要求对磁盘进行体检与清理时，方可激活本规范。
> 3. **清单呈批流**：任何删除命令前，必须先生成结构化候选清单（带 `RES-001` 等独立编号），获得用户明确授权确认后方可执行。

---

## Agent Detection & Activation Triggers
Only activate this runbook when user prompt explicitly matches:
* "save-my-disk", "调用 save-my-disk", "运行 save-my-disk 技能"
* "系统盘清理体检", "检查磁盘空间残留" (Explicit storage intent)

---

## Tool & Function Calling Schemas
For agents that support OpenAI-compatible function calling or MCP (such as WorkBuddy, Cursor, Claude Desktop, AutoGen):
* See [`tools/tool_definitions.json`](./tools/tool_definitions.json) for standard JSON Schema declarations.

---

## CLI Command Registry for Agents

All scripts reside in `./scripts/` with zero external dependencies and support standard exit codes and structured JSON output.

| Capability | Command | Mode | Safe to Auto-Run? |
| :--- | :--- | :--- | :--- |
| **Audit Drives** | `powershell -ExecutionPolicy Bypass -File ./scripts/audit_drives.ps1 -Json` | Read-Only | **YES** |
| **Scan Residues & Caches** | `powershell -ExecutionPolicy Bypass -File ./scripts/scan_app_residues.ps1 -Json` | Read-Only | **YES** |
| **Clean Confirmed Residues** | `powershell -ExecutionPolicy Bypass -File ./scripts/clean_selected_residues.ps1 -TargetIds RES-001,RES-002 -Force` | Modifying | **NO** (Must present itemized list and confirm with user first) |
| **Clean Update Cache** | `powershell -ExecutionPolicy Bypass -File ./scripts/clean_windows_update.ps1` | Modifying | **NO** (Requires admin & user confirmation) |
| **Clean User Temp** | `powershell -ExecutionPolicy Bypass -File ./scripts/clean_user_temp.ps1` | Modifying | **NO** (Must confirm with user first) |
| **Post-Check Health** | `powershell -ExecutionPolicy Bypass -File ./scripts/verify_health.ps1 -Json` | Read-Only | **YES** |

---

## Standard Multi-Agent Protocol

1. **Step 1: Discover & Audit (Zero Impact)**
   Run `audit_drives.ps1 -Json` and `scan_app_residues.ps1 -Json`.
2. **Step 2: Itemize & Present Candidates**
   Display the discovered residue items in a clean table:
   `| ID | Category | Name | Size (MB) | Path |`
   Ask the user: *"Here are the detected uninstalled remnants and safe caches. Please confirm which item IDs you would like to clean."*
3. **Step 3: Guarded Execution**
   Only pass the user-confirmed IDs to `clean_selected_residues.ps1 -TargetIds ... -Force`.
4. **Step 4: Verify & Report**
   Run `verify_health.ps1 -Json` to confirm recovered space and ensure system services are healthy.
