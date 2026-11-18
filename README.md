# baota

Multi-distribution Linux file-deployment helper for the user-supplied LinuxPanel 7.4.0 archive.

## Archive source

The installer downloads `LinuxPanel-7.4.0.zip` from:

`https://raw.githubusercontent.com/yigexiaoyunwei/BaoTa_History_Release/main/LinuxPanel-7.4.0.zip`

The ZIP is not duplicated in this repository. For stronger supply-chain integrity, set `EXPECTED_SHA256` to a checksum you have independently verified.

## Install

Run as root:

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

## OS and architecture detection

The installer detects `/etc/os-release`, CPU architecture and an available package manager. It can use apt, dnf, yum, zypper, apk or pacman to install the small set of tools required for archive download and extraction.

Supported CPU architectures: x86_64/amd64 and aarch64/arm64. Other architectures are rejected.

This is **not** a guarantee that every Linux distribution can run this legacy panel. Distributions with one of the detected package managers can pass the file-staging workflow, but the panel runtime must be validated separately.

## Important compatibility warning

The supplied archive uses the legacy `/usr/bin/python` launcher and old dependencies, including `Werkzeug==0.16.1`, `Pillow==5.4.1` and `MarkupSafe==2.0.1`. Runtime compatibility with modern Python versions has not been established.

The current installer validates the archive, backs up an existing panel directory and deploys files only. It deliberately does **not** create or start services until Python dependency compatibility, initialization and BT-Panel / BT-Task behavior have been tested.

Default install path: `/www/server/panel`; default configured port: `8888`. Nginx, MySQL and PHP are not installed. Cloud firewall/security-group rules are not modified.
