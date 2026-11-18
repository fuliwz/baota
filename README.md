# baota

Ubuntu 24.04 deployment helper for the user-supplied LinuxPanel 7.4.0 archive.

## Archive source

The installer downloads `LinuxPanel-7.4.0.zip` directly from the public upstream archive:

`https://raw.githubusercontent.com/yigexiaoyunwei/BaoTa_History_Release/main/LinuxPanel-7.4.0.zip`

No duplicate ZIP is stored in this repository. To pin integrity, set `EXPECTED_SHA256` to the verified 64-character SHA256 digest before running.

## Install

Run as root on Ubuntu 24.04:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/fuliwz/baota/main/install.sh)
```

Optionally pin the archive checksum:

```bash
EXPECTED_SHA256='替换为已核实的64位SHA256' bash <(curl -fsSL https://raw.githubusercontent.com/fuliwz/baota/main/install.sh)
```

Or provide a trusted HTTPS archive URL:

```bash
PANEL_ARCHIVE_URL='https://your-host/LinuxPanel-7.4.0.zip' bash <(curl -fsSL https://raw.githubusercontent.com/fuliwz/baota/main/install.sh)
```

## Important compatibility warning

The provided archive's launcher and dependencies are from an older software generation. Runtime compatibility with Ubuntu 24.04 / Python 3.12 has not yet been established. The current installer checks system and ZIP structure, backs up an existing installation, and deploys files only. It deliberately does not claim that the panel is fully installed or start unverified services.

Default install path: `/www/server/panel`; default configured port: `8888`. Nginx, MySQL and PHP are not installed. Cloud firewall/security-group rules are not modified.

Before enabling service startup, test Python dependency compatibility, the panel initialization process, and the BT-Panel / BT-Task processes.
