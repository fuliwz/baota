# 宝塔 Linux Panel 7.4.0 第三方安装/版本切换工具

本仓库是第三方自动化工具，并非宝塔官方安装包。

## 必须先明确：7.4.0 ZIP 是升级包

`LinuxPanel-7.4.0.zip` 是宝塔 7.4.0 离线升级/降级归档。归档通过 `panel/update.sh` 操作已有面板，不包含一个可直接复制为 `/www/server/panel` 的完整首次安装流程。因此绝不能把 ZIP 根目录中的 `panel/` 目录直接覆盖到新系统的 `/www/server/panel`。

宝塔 7.4.0 官方发布说明列出的离线流程为：先安装宝塔，再解压归档并执行 `panel/update.sh`。来源：
`https://www.bt.cn/bbs/thread-52291-1-1.html`

## 全新安装入口

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/fuliwz/baota/runtime-installer-dev/install.sh)
```

`install.sh` 当前负责下载并执行宝塔基础在线安装器 `https://download.bt.cn/install/install_6.0.sh`。基础安装成功后，面板版本由基础安装器/上游当前策略决定；再运行 `upgrade.sh` 使用离线 7.4.0 包切换版本。首次执行前应阅读并审查上游脚本，在可回滚的测试 VPS 上进行。

## 已安装面板切换到 7.4.0

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/fuliwz/baota/runtime-installer-dev/upgrade.sh)
```

`upgrade.sh` 会备份 `/www/server/panel`，下载 7.4.0 ZIP，确认 ZIP 中存在 `panel/update.sh` 后执行它。失败时会保留完整备份供人工恢复；由于更新脚本可能已经迁移数据库或配置，不能盲目覆盖回滚。

可选校验：

```bash
EXPECTED_SHA256='经独立核实的64位SHA256' bash upgrade.sh
```

## 其他工具

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/fuliwz/baota/runtime-installer-dev/diagnose.sh)
bash <(curl -fsSL https://raw.githubusercontent.com/fuliwz/baota/runtime-installer-dev/uninstall.sh)
```

卸载脚本仅移除面板 systemd unit 和（按确认选择）面板程序目录，不会自动卸载网站服务、数据库、PHP 或删除网站数据。

## 平台兼容性

目前只做基础系统识别和脚本入口；并未在 Ubuntu、Debian、RHEL、openSUSE 等所有发行版完成端到端测试。最终兼容范围取决于宝塔基础安装器和历史升级脚本各自支持的系统、架构、Python 及依赖组合。不要将“识别包管理器”理解为“面板已支持该发行版”。

## 安全须知

- 这是第三方工具。基础安装脚本来自宝塔下载站并以 root 权限执行；升级包来自第三方历史归档仓库。
- 建议在执行前创建 VPS 快照，并独立验证下载源及 SHA256。
- 默认面板端口通常由基础安装器设置；云厂商安全组需要另行放行。
- 初始管理员账号和密码请以基础安装器输出为准，不在此硬编码。