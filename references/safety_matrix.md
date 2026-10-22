# Disk Triage Safety Matrix (风险分级决策矩阵)

This matrix defines the directory classification, safety levels, and handling policies for AI Agents.

---

## 🟢 Tier 1: Zero-Risk / Pure Cache (无痛零风险 - 可在用户确认后自动化执行)

| Target Path | Description | Recommended Agent Action |
| :--- | :--- | :--- |
| `C:\$WINDOWS.~BT` | Windows version upgrade residual & rollback archive | Instruct user to run `cleanmgr` (Clean up system files) or execute automated removal |
| `C:\Windows\SoftwareDistribution\Download` | Windows Update downloaded patch packages | Stop `wuauserv` -> purge directory -> restart `wuauserv` |
| `C:\Windows\SoftwareDistribution\Download.bak` | Historical dead backup folder | Delete immediately |
| `%LOCALAPPDATA%\Temp` | User temporary files from installers/unzippers | Clear non-locked files |
| `C:\$RECYCLE.BIN` | Recycle Bin | Confirm with user, then empty |
| `Delivery Optimization Files` | P2P patch sharing cache | Purge via cleanmgr or PowerShell |
| Game uninstaller residue | Empty folders after game uninstall | Safe to delete |

---

## 🟡 Tier 2: Developer Caches & Runtimes (开发者缓存 - 建议迁移或定向修剪)

| Target Path | Description | Recommended Agent Action |
| :--- | :--- | :--- |
| `%LOCALAPPDATA%\Docker\wsl\disk\docker_data.vhdx` | Docker Desktop WSL2 virtual disk | **Do not directly delete!** Guide user to migrate disk to secondary drive (e.g. D:) or run `docker system prune` |
| `%USERPROFILE%\miniconda3\pkgs` | Conda downloaded package tarballs | Run `conda clean --packages --tarballs` |
| `%USERPROFILE%\.cache\codex-runtimes` | Code generation sandbox runtime installs | Keep primary active runtime; purge temporary `*-install-*` directories |
| `%LOCALAPPDATA%\npm-cache` | Node.js npm package cache | Run `npm cache clean --force` |
| `%USERPROFILE%\.gradle\caches` | Gradle build tool dependencies | Safe to delete if willing to re-download on next build |
| `C:\hiberfil.sys` | Windows hibernation memory snapshot | If user does not use hibernation, guide `powercfg -h off` |

---

## 🟠 Tier 3: Application Internal Storage (应用内数据 - 必须应用内治理)

| Target Path | Description | Recommended Agent Action |
| :--- | :--- | :--- |
| `%APPDATA%\LarkShell` | Feishu / Lark chat media & docs cache | Guide user: Settings -> General -> Storage Management -> Clear Cache |
| `%USERPROFILE%\xwechat_files` | WeChat received media & cache | Guide user: Settings -> General -> Storage Management -> Manage |
| `%LOCALAPPDATA%\Packages` | Windows UWP app sandbox data | Guide user: Windows Settings -> Apps -> Installed Apps -> Reset |

---

## 🔴 Tier 4: Red Line / Forbidden (绝对禁区 - 严禁手动删除)

| Target Path | Description | Why It Must Not Be Touched |
| :--- | :--- | :--- |
| `C:\Windows\System32` & `SysWOW64` | OS core binaries and libraries | Immediate BSOD / system death |
| `C:\Windows\WinSxS` | Windows Component Store | Breaks Windows servicing; only manageable via `DISM /online /cleanup-image` |
| `C:\pagefile.sys` & `swapfile.sys` | System virtual memory | Locked by kernel; can only be relocated via Advanced System Settings |
| `%USERPROFILE%\Desktop\*` (e.g. `HDU-World`) | User project files, source codes, coursework | High risk of permanent data loss |
| `C:\Program Files` & `(x86)` root | Active installed software binaries | Corrupts installed applications and registry entries |
