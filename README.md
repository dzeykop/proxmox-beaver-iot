# proxmox-beaver-iot

One-command installer for [Milesight Beaver IoT](https://www.milesight.com/beaver-iot/) on Proxmox VE.

Creates a Debian 12 VM, installs Docker via cloud-init and starts Beaver IoT automatically.

**Current version:** 1.2.0

## Quick start

Run on your Proxmox host as root (preferably via SSH, so copy and paste works):

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/dzeykop/proxmox-beaver-iot/main/install.sh)"
```

## Features

- Shows host resources (CPU cores, total and available RAM)
- Shows recommended and minimum values at every step
- Validates input and warns below the minimum
- Storage selection with free space
- Network bridge selection
- Checks that the VM ID is free
- Password confirmation
- Summary before anything is created
- Docker and Beaver IoT with auto-restart
- Daily update check with a notice at SSH login (never installs on its own)
- Backup and rollback for updates
- Shows web UI, MQTT and SSH info at the end

## Recommended settings

| Setting | Recommended | Minimum |
|---|---|---|
| CPU cores | 2 | 1 |
| RAM | 4096 MB | 2048 MB |
| Disk | 32 GB | 16 GB |

## Ports

| Service | Port |
|---|---|
| Web UI | 9080 (changeable) |
| MQTT broker | 1883 |

## After installation

- Web UI: `http://<VM-IP>:9080`
- MQTT: `<VM-IP>:1883`
- SSH: `ssh beaver@<VM-IP>`
- Data: `/opt/beaver-iot` inside the VM

The first boot takes a few minutes while Docker and Beaver IoT are installed.

## Updating Beaver IoT

The VM checks once a day for a new Beaver IoT image. **Nothing is installed automatically.**
When an update is available, you see a notice at SSH login. You decide when to install it.

| Command | What it does |
|---|---|
| `sudo beaver-update` | Checks and, after your confirmation, installs the update |
| `sudo beaver-update --status` | Shows installed version, pending update and backups |
| `sudo beaver-update --rollback` | Goes back to the version before the last update |

Before every update:

- Beaver IoT is stopped and `/opt/beaver-iot` is backed up to `/opt/beaver-iot-backups`
- The last 3 backups are kept
- The previous version is kept for a rollback

Settings for the update helper are in `/etc/beaver-iot.conf`.

## Requirements

- Proxmox VE 8 or 9
- Internet access on host and VM

## Changelog

- **1.2.0** - Update helper `beaver-update` with daily check, login notice, backup and rollback
- **1.1.1** - Fixed hidden warning dialogs and cancel handling
- **1.1.0** - Host resources, recommended values, input checks, storage and bridge selection, summary
- **1.0.1** - Added MQTT port 1883
- **1.0.0** - First release

## Notes

Personal learning project, not affiliated with Milesight.

Made by JFFK.
