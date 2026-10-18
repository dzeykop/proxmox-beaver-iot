# proxmox-beaver-iot

One-command installer for [Milesight Beaver IoT](https://www.milesight.com/beaver-iot/) on Proxmox VE.

Creates a Debian 12 VM, installs Docker via cloud-init and starts Beaver IoT automatically.

**Current version:** 1.1.1

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

## Requirements

- Proxmox VE 8 or 9
- Internet access on host and VM

## Notes

Personal learning project, not affiliated with Milesight.

Made by JFFK.
