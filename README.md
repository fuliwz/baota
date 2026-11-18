# baota

Ubuntu 24.04 deployment helper for the user-supplied LinuxPanel 7.4.0 archive.

**Compatibility warning:** the supplied archive uses a legacy `/usr/bin/python` launcher and pins old dependencies including Pillow 5.4.1. Runtime compatibility with Ubuntu 24.04 / Python 3.12 has not been established. The installer performs preflight, archive safety checks, backup and file deployment only; it deliberately does not start the panel or claim a successful runtime install.

## Install

Upload `LinuxPanel-7.4.0.zip` as the `v7.4.0` GitHub Release asset, then run as root on Ubuntu 24.04:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/fuliwz/baota/main/install.sh)
```

Or provide a trusted HTTPS URL:

```bash
PANEL_ARCHIVE_URL='https://your-host/LinuxPanel-7.4.0.zip' bash <(curl -fsSL https://raw.githubusercontent.com/fuliwz/baota/main/install.sh)
```

Default install path: `/www/server/panel`; default configured port: `8888`. Nginx, MySQL and PHP are not installed. Cloud firewall/security-group rules are not modified.

This is a guarded deployment scaffold, not yet a fully validated panel installation. Python dependencies, panel initialization and both service processes must be tested before enabling systemd startup.
