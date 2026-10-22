# Universal Multi-Agent Specification: Save My Disk (save-my-disk) 🚀

This specification defines how **ANY AI Agent framework** (WorkBuddy, Cursor, Windsurf, AutoGen, CrewAI, LangChain, OpenAI Codex, Claude Code, OpenCode, DeepSeek Harness, etc.) should discover, expose, and safely execute this toolset.

---

## Agent Detection & Activation Triggers
Activate this runbook whenever the user prompt mentions:
* "磁盘清理", "C盘爆满", "清理垃圾", "扫描硬盘", "释放空间", "软件残留", "Steam残留", "微信缓存", "QQ缓存", "WPS缓存"
* "clean disk", "disk full", "free up space", "inspect C drive", "steam remnants", "app caches"

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
