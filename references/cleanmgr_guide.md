# Windows Native Cleanmgr System Files Guide (系统文件清理标准指南)

This guide documents the gold-standard GUI cleanup workflow using Windows native `cleanmgr` with elevated system file cleanup privileges.

---

## Standard Procedure (标准执行流程)

### Step 1: Launch Cleanmgr in System Mode
1. Press `Win + R` to open the Windows Run dialog.
2. Type `cleanmgr` and press Enter.
3. Select drive `C:` and click **OK**.
4. In the dialog, click the button **"Clean up system files" (清理系统文件)** located at the bottom-left.
5. Windows will re-scan with full Administrator rights.

### Step 2: Select Items
Check all recommended safe checkboxes:
* **Previous Windows installation(s) / 以前的 Windows 安装**: Can easily free 20 GB ~ 50 GB (`$WINDOWS.~BT` / `Windows.old`).
* **Delivery Optimization Files / 传递优化文件**: Safe (frees ~1 GB).
* **Temporary Windows installation files / 临时 Windows 安装文件**: Safe (frees ~20 GB+).
* **Recycle Bin / 回收站**: Ensure no desired deleted files remain.
* **DirectX Shader Cache / 着色器缓存**: Safe.
* **Temporary files / 临时文件**: Safe.
* **Thumbnails / 缩略图**: Safe.

### Step 3: Execute
1. Click **OK**.
2. Click **Delete Files** on confirmation.
3. Allow the progress bar to finish (may take 2-5 minutes on large system installation rollbacks).

---

## When the Agent Should Recommend This
* Whenever `$WINDOWS.~BT` or `Windows.old` exceeds 10 GB.
* When the user prefers a native Windows UI without running CLI scripts.
