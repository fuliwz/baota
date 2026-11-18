# 宝塔 Linux Panel 7.4.0 第三方一键部署器

本项目为第三方自动化工具，不是宝塔官方发行包或官方支持安装器。

## 重要：7.4.0 ZIP 的真实用途

`LinuxPanel-7.4.0.zip` 是离线升级/降级包，不是全新安装所需的完整面板源码。ZIP 内通过 `panel/update.sh` 将已经安装的面板切换到 7.4.0。官方 7.4.0 发布说明采用的也是先安装面板、再解压并执行 `panel/update.sh` 的流程。

本项目使用两阶段方案：
1. 使用基础安装器安装完整宝塔面板及其运行环境。
2. 使用 7.4.0 离线升级包的 `panel/update.sh` 切换到目标版本。

## 全新安装

开发分支入口（root）：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/fuliwz/baota/runtime-installer-dev/install.sh)
```

可选：

```bash
PANEL_PORT=8888 \
EXPECTED_SHA256='经独立核实的64位SHA256' \
bash <(curl -fsSL https://raw.githubusercontent.com/fuliwz/baota/runtime-installer-dev/install.sh)
```

基础安装器默认使用 `https://download.bt.cn/install/install_6.0.sh`。它依赖上游脚本可用性和上游脚本当前选择的面板版本，不是完全离线安装器。随后才调用历史 7.4.0 ZIP 的 `panel/update.sh`。首次执行前应审阅上游基础安装脚本，并在可回滚的测试 VPS 上运行。

## 已安装面板切换到 7.4.0

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/fuliwz/baota/runtime-installer-dev/upgrade.sh)
```

升级脚本先完整备份 `/www/server/panel`，再下载并执行升级包自带的 `panel/update.sh`。

## 卸载和诊断

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/fuliwz/baota/runtime-installer-dev/uninstall.sh)
bash <(curl -fsSL https://raw.githubusercontent.com/fuliwz/baota/runtime-installer-dev/diagnose.sh)
```

卸载只移除面板 systemd 服务和面板目录（按提示选择）；不会自动删除 Nginx、MySQL、PHP、站点和系统级依赖。

## 兼容性范围

当前仍是初始实现，尚未在多个发行版进行端到端测试。目标优先级为 Ubuntu/Debian、RHEL 系、openSUSE/SLES；CPU x86_64 和 aarch64。实际运行取决于基础安装脚本支持的操作系统、架构及其安装的 Python/依赖组合，不能宣称支持所有 Linux。

## 安全和使用限制

- 首次全新安装会执行第三方提供的基础安装脚本，必须先审阅来源和内容。
- 7.4.0 归档执行的是其自带的更新程序；不要将该 ZIP 直接解压覆盖 `/www/server/panel`。
- 强烈建议先创建 VPS 快照，并保留脚本自动生成的面板目录备份。
- 归档地址：`https://raw.githubusercontent.com/yigexiaoyunwei/BaoTa_History_Release/main/LinuxPanel-7.4.0.zip`。
- 云厂商安全组需要自行放行面板端口（默认 8888）。
- 不假设或伪造管理员密码；请以基础安装器实际输出为准。