# 宝塔 Linux Panel 7.4.0 自定义一键安装器

本项目基于用户提供的 LinuxPanel 7.4.0 归档制作，属于第三方自定义部署工具，不是宝塔官方安装包或官方支持版本。

## 一键安装

当前开发分支安装命令（需要 root）：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/fuliwz/baota/runtime-installer-dev/install.sh)
```

可选设置端口、归档地址和独立核验的 SHA256：

```bash
PANEL_PORT=8888 \
PANEL_ARCHIVE_URL='https://your-trusted-host/LinuxPanel-7.4.0.zip' \
EXPECTED_SHA256='替换为64位SHA256' \
bash <(curl -fsSL https://raw.githubusercontent.com/fuliwz/baota/runtime-installer-dev/install.sh)
```

## 已实现的安装步骤

1. 检查 root 权限、Linux 发行版、CPU 架构和 systemd。
2. 通过 apt、dnf/yum 或 zypper 安装系统构建依赖。
3. 下载并检查 ZIP 成员路径，拒绝绝对路径、目录穿越和符号链接。
4. 将现有面板目录备份到带时间戳的目录。
5. 部署 Panel 7.4.0 文件并写入面板端口。
6. 应用限定范围的 Python 2 语法兼容补丁。
7. 创建独立 Python 虚拟环境，安装锁定依赖。
8. 编译检查 Python 文件并测试关键依赖导入。
9. 安装前台 gevent 启动器和两个 systemd 服务。
10. 启动服务并检查本机 `/service_status` 健康端点。

## 当前目标兼容范围（尚待真实 VPS 验证）

- 发行版家族：Ubuntu、Debian、RHEL/CentOS/Rocky/AlmaLinux/Fedora、openSUSE/SLES。
- CPU：x86_64、aarch64。
- init：systemd。
- Python：系统 Python 3.10 或 3.11。

安装器会拒绝 Python 3.12+、不支持的架构和非 systemd 系统。Alpine/OpenRC、Arch/pacman 当前尚未完成运行时适配。不同发行版的软件包名称和依赖构建仍需逐一验证，因此不能据此宣称所有 Linux 均已支持。

## 管理

```bash
systemctl status bt bt-task
systemctl restart bt
systemctl restart bt-task
journalctl -u bt -u bt-task -n 100 --no-pager
bash diagnose.sh
bash upgrade.sh
bash uninstall.sh
```

- `diagnose.sh`：输出系统、服务、端口和日志诊断信息。
- `uninstall.sh`：移除 systemd 服务；选择 REMOVE 时将面板目录移动到备份位置，不会立即永久删除。
- `upgrade.sh`：当前仅提供备份保护和升级前检查，**尚未启用自动覆盖升级**；待数据迁移与回滚测试通过后再完善。

## 重要说明

- 当前依赖锁文件是首轮兼容性候选组合，不代表已经在所有目标发行版和架构完成验证。
- 首轮必须在 Ubuntu 22.04 x86_64 VPS 上验证安装、登录、任务调度、WebSocket、SSL、重启和卸载，再扩展其他系统。
- 不安装 Nginx、MySQL、PHP，不修改云厂商安全组。
- 云厂商安全组需要自行放行面板 TCP 端口（默认 8888）。
- 安装器不猜测默认管理员账号或密码；以面板实际初始化状态为准。
- 建议为上游 ZIP 设置独立核实的 `EXPECTED_SHA256`。归档来源：`https://raw.githubusercontent.com/yigexiaoyunwei/BaoTa_History_Release/main/LinuxPanel-7.4.0.zip`。
