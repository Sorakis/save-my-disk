# Save My Disk 🚀 (save-my-disk)

> **Universal AI Agent Skill & Runbook for Intelligent, Non-Invasive Disk Optimization.**  
> 面向 AI 编程助手（Antigravity, OpenAI Codex, Claude Code, WorkBuddy, OpenCode, DeepSeek Harness, Cursor 等）与广大开发者的智能磁盘诊断与安全瘦身工作流。

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Windows%20(v0.1)%20%7C%20Linux%20%26%20macOS%20(Planned)-0078D6.svg)]()
[![Compatibility](https://img.shields.io/badge/Agents-Antigravity%20%7C%20WorkBuddy%20%7C%20Codex%20%7C%20ClaudeCode%20%7C%20DeepSeek%20%7C%20Cursor-brightgreen.svg)]()

---

## 🌟 核心理念 (Core Philosophy)

1. **只读优先 (Read-Only First)**：初筛体检阶段严禁执行任何写操作，严格规避死循环与高 I/O 锁盘，前台进程丝滑不卡顿。
2. **四级风险决策矩阵 (Risk-Tiered Triage)**：
   * 🟢 **Tier 1 (无痛零风险)**：系统更新补丁、`$WINDOWS.~BT`、临时文件、传递优化。
   * 🟡 **Tier 2 (开发者缓存 / 可迁移项)**：Docker 虚拟磁盘、Conda/pip/npm 缓存、AI 模型临时运行库。
   * 🟠 **Tier 3 (应用内治理与残留)**：Steam 卸载空残留、办公/聊天日志转储、微信与飞书媒体数据。
   * 🔴 **Tier 4 (绝对红线禁区)**：`System32`、`WinSxS`、正在工作的项目源码。
3. **双轨闭环执行 (Dual-Track Engine)**：
   * **Agent 自动化执行**：对零风险补丁缓存，由 Agent 提供一键脚本（**必须先获用户明确授权**）。
   * **Agent 人机协作引导**：对需要 GUI 权限的操作（如 `cleanmgr` 清理系统文件、Docker 虚拟盘无损迁移到大容量盘），Agent 输出极简分步指引。
4. **自愈与战果核验 (Verification)**：任何清理操作完成后，自动回访核对磁盘剩余空间差值，并验证关键系统服务健康状态。

---

## 🏗️ 架构与工作流 (Architecture)

```mermaid
flowchart TD
    A["用户提出需求: 盘满了/清理空间"] --> B["Phase 1: 只读轻量体检 (audit_drives.ps1)"]
    B --> C["Phase 2: 智能风险分级与决策 (Safety Matrix)"]
    C --> D{"清理路径选择"}
    D -->|"Tier 1 缓存清理"| E["Track A: Agent 执行脚本 (需用户确认)"]
    D -->|"系统升级残留/Docker迁移"| F["Track B: Agent 指导用户执行 (cleanmgr/Docker设置)"]
    E --> G["Phase 4: 结果自愈核验 (verify_health.ps1)"]
    F --> G
    G --> H["输出战果报表: 释放空间量 + 服务健康确认"]
```

---

## 🤖 多 Agent 支持规范 (Multi-Agent Compatibility)

本项目专为各大主流 AI 助手设计，即插即用：

| 平台 / Agent | 适配配置文件 | 接入方式 |
| :--- | :--- | :--- |
| **Antigravity** | [`SKILL.md`](./SKILL.md) | 作为通用技能挂载（支持通过口令显式调用） |
| **WorkBuddy / Cursor** | [`tools/tool_definitions.json`](./tools/tool_definitions.json) | OpenAPI / Function Calling 标准工具声明或直接 `@save-my-disk` |
| **Claude Code** | [`CLAUDE.md`](./CLAUDE.md) | 作为项目级指令规则即时调用 |
| **OpenAI Codex** | [`AGENTS.md`](./AGENTS.md) | 自动读取指令与 CLI 注册表 |
| **OpenCode** | [`SKILL.md`](./SKILL.md) / [`AGENTS.md`](./AGENTS.md) | 标准 Runbook 兼容模式 |
| **DeepSeek Harness** | [`AGENTS.md`](./AGENTS.md) | 结构化任务与脚本执行支持 |

---

## 📖 如何使用 (How to Use)

> **🚨 显式调用原则 (Explicit Invocation First)**：  
> 磁盘运维属于系统高危敏感操作。为了确保您的开发环境与核心文件 100% 绝对安全，**本项目严禁 AI 在普通编程时隐式静默自发运行**。您必须显式唤起本技能，Agent 会严格遵守 **“只读体检 -> 呈批候选清单 -> 靶向确认 -> 执行自愈”** 闭环。

---

### ⚡ 一键给 Agent 的安装与运行指令 (推荐 ⭐⭐⭐⭐⭐)

你**无需手动下载配置**！直接将下面这段指令完整复制，粘贴发送给你的任意 AI 编程助手（**Antigravity、WorkBuddy、Cursor、Claude Code、OpenCode、Codex 等**）：

```text
请帮我把 https://github.com/Sorakis/save-my-disk.git 克隆到当前工作区的 .tools/save-my-disk 目录中，读取其中的 SKILL.md 与 AGENTS.md 规范；然后作为 save-my-disk 助手，对当前电脑执行一次只读磁盘体检，向我汇报各盘空间占用分布与安全清理候选清单，并提示我下一步如何选择性清理。
```

> **Agent 收到这句口令后会自动**：
> 1. 执行 Git 克隆将仓库拉取到工作区；
> 2. 识别并装载其中的全套多 Agent 协议与工具；
> 3. 自动执行只读体检并列出带编号的候选清理清单；
> 4. 给出清晰指引，等待你挑选确认后再动手！

---

### 📦 手动安装方式 (Manual Installation)

如果你更习惯手动下载或希望在本机全局部署：

#### 选项 A：克隆到当前开发项目（推荐配合项目使用）
在你的项目根目录下打开终端，执行：
```bash
# 推荐克隆到工作区的工具目录
git clone https://github.com/Sorakis/save-my-disk.git .tools/save-my-disk
```

#### 选项 B：一键全局安装（让本机所有 Agent / 终端随时随地可用）
在 PowerShell 中运行以下一行命令，将工具包克隆到用户全局技能库：
```powershell
# 克隆到全局技能配置目录（以 Antigravity / 全局 Agent 规范为例）
git clone https://github.com/Sorakis/save-my-disk.git "$HOME\.gemini\config\skills\save-my-disk"
```
*安装完成后，无论你在电脑的哪个文件夹打开 AI，直接对它说：“使用 save-my-disk 技能扫描磁盘” 即可！*

---

### 💬 交互式会话流程演示 (Interactive Workflow)

#### 1. 显式唤醒与只读体检
在对话框中直接输入显式调用口令：
> **用户**：“使用 `save-my-disk` 技能，帮我只读扫描一下当前电脑的磁盘空间，看看有哪些大文件或安全残留”

AI 会自动执行只读体检脚本，输出各驱动器容量分布，以及一份**带独立编号的候选审核清单**：
```markdown
| 编号 | 类别 | 名称 | 占用大小 | 路径 | 建议 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **RES-001** | Steam 残留 | GhostGameResidual | 120 MB | `D:\STEAM\steamapps\common\GhostGame` | 游戏已卸载，仅存留崩溃日志，建议清理 |
| **RES-002** | 软件空目录 | 鑻遍泟鑱旂洘 | 0 MB | `D:\WeGameApps\鑻遍泟鑱旂洘` | 乱码空目录，建议清理 |
| **RES-003** | WPS 缓存 | WPS 自动备份暂存 | 450 MB | `%APPDATA%\Kingsoft\backup` | 历史临时快照，建议清理 |
```

#### 2. 靶向授权与定向清理
**AI 绝不会自动删除全部项目**。您只需根据清单，回复您想清理的编号：
> **用户**：“确认清理 RES-001 和 RES-002，其余保留”

AI 收到您的明确指令后，才会调用底层精准清理脚本清除指定项，并汇报最终释放的容量与服务健康状态。

---

### 方式二：脱离 AI，人类开发者纯终端独立使用 (CLI Mode)

即使不借助任何 AI 工具，所有脚本也可以在 Windows PowerShell 中直接独立运行：

```powershell
# 1. 进入脚本目录
cd save-my-disk/scripts

# 2. 运行只读体检（支持查看控制台表格或输出 JSON）
.\audit_drives.ps1
.\audit_drives.ps1 -Json

# 3. 扫描软件卸载残留与应用安全缓存
.\scan_app_residues.ps1

# 4. 根据扫描出来的编号，定向安全清理（必须带 -Force 才会真正执行，否则仅 Dry-Run 预演）
.\clean_selected_residues.ps1 -TargetIds RES-001,RES-002 -Force

# 5. 安全清理 Windows Update 补丁缓存（需管理员权限，自动重启更新服务）
.\clean_windows_update.ps1
```

---

## 📂 目录结构 (Directory Layout)

```text
save-my-disk/
├── SKILL.md                  # Antigravity & OpenCode 核心技能定义
├── AGENTS.md                 # Universal Agent 规范 (Codex, WorkBuddy, DeepSeek 等)
├── CLAUDE.md                 # Claude Code 专用配置
├── README.md                 # 项目介绍与开源文档
├── LICENSE                   # MIT 开源协议
├── tools/                    # Function Calling / OpenAPI 架构定义
│   └── tool_definitions.json # 标准函数调用工具声明
├── scripts/                  # 解耦的高可用自动化脚本 (支持 -Json / -DryRun)
│   ├── audit_drives.ps1      # 只读盘符与热点体检脚本
│   ├── clean_windows_update.ps1 # 安全停止服务、清除更新补丁、自愈重启服务
│   ├── clean_user_temp.ps1   # 安全清理 Temp 目录与回收站
│   ├── scan_app_residues.ps1 # 软件残留与安全缓存扫描器
│   ├── clean_selected_residues.ps1 # 基于 ID/路径的精准清理器
│   └── verify_health.ps1     # 空间差值与系统服务存活核验
├── tests/                    # 100% 隔离的自动化 Mock 沙箱测试套件
│   └── test_mock_sandbox.ps1 # 零接触本机实际文件的验证测试
└── references/               # 离线知识库
    ├── safety_matrix.md      # 4级风险判定矩阵
    ├── cleanmgr_guide.md     # cleanmgr 系统文件清理金牌指南
    └── dev_cache_guide.md    # Docker WSL2 迁移 D 盘、Conda/Npm 治理指引
```

---

## ⚡ 真实实战战果 (Real-World Case)

在某台重度开发机器上的真实实测效果：
* **初始可用空间**：`193.90 GB`
* **清理后可用空间**：`242.20 GB`
* **净释放空间**：**+48.3 GB！**（清理了 42GB 旧系统升级残留 `$WINDOWS.~BT` 以及近 20GB 的 Windows Update 下载缓存与废弃备份）。
* **系统服务状态**：`Windows Update (wuauserv)` 验证通过，持续健康运行。

---

## 🗺️ 开源演进路线 (Roadmap)

- [x] **v0.1**: Windows 核心审计、更新缓存自愈清理、Temp/回收站清理、Cleanmgr 体系化方案、多 Agent 协议接入。
- [x] **v0.2 (Preview/Design)**: 软件卸载残留扫描、办公/聊天日志转储安全清理、隔离沙箱自动化测试套件、Function Calling OpenAPI 声明。
- [ ] **v0.3**: Docker / WSL 虚拟硬盘跨盘无损迁移脚本与自动化压缩 (`compact`)。
- [ ] **v0.4**: macOS 平台支持 (`~/Library/Caches`, Xcode DerivedData, Homebrew cache)。
- [ ] **v0.5**: Linux 平台支持 (`/var/cache/apt`, journalctl 日志修剪, Docker system prune)。

---

## 📄 开源许可证

本项目基于 [MIT License](LICENSE) 开源，欢迎自由 Fork、定制与贡献 PR！

