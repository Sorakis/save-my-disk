# Developer Caches & Runtime Migration Guide (开发者缓存与环境治理指南)

---

## 1. Docker Desktop WSL2 Virtual Disk Migration (无损迁移到 D 盘)

### Why Migrate?
By default, Docker Desktop places `docker_data.vhdx` inside `%LOCALAPPDATA%\Docker\wsl\disk\`. As developers pull images, this file quickly consumes 20 GB ~ 50 GB of C: drive space, and WSL2 does not auto-shrink.

### GUI Migration Method (Docker Desktop 4.15+)
1. Open **Docker Desktop Settings** (Gear icon in top bar).
2. Navigate to **Resources** -> **Advanced** (or **Virtual disk limit / Disk image location** depending on version).
3. Under **Disk image location**, click **Browse** and select a folder on a secondary drive (e.g. `D:\Docker\`).
4. Click **Apply & restart**. Docker will automatically move the 20 GB `.vhdx` file to D:.

### CLI Compacting (If not migrating)
```powershell
# In PowerShell:
wsl --shutdown
diskpart
# In diskpart prompt:
# select vdisk file="C:\Users\<username>\AppData\Local\Docker\wsl\disk\docker_data.vhdx"
# compact vdisk
# exit
```

---

## 2. Conda & Package Managers

### Conda Tarballs
```bash
conda clean --packages --tarballs -y
```

### NPM Cache
```bash
npm cache clean --force
```

### Pip Cache
```bash
pip cache purge
```

---

## 3. Communication Apps (WeChat / Lark)

* **Feishu / Lark**:
  1. Open Feishu -> Click Avatar (Top Left) -> **Settings**.
  2. Navigate to **General** -> **Storage Management**.
  3. Click **Clear Cache** (removes temporary media, retains message text).

* **WeChat**:
  1. Open WeChat -> Click Menu (Bottom Left) -> **Settings**.
  2. Navigate to **General** -> **Storage Space**.
  3. Click **Manage** to selectively delete older video/file downloads.
