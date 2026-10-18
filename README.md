# proxmox-beaver-iot

One-command installer for [Milesight Beaver IoT](https://www.milesight.com/beaver-iot/) on Proxmox VE.

The script creates a Debian 12 VM, installs Docker via cloud-init and starts Beaver IoT automatically.

## Quick start

Run this on your Proxmox host as root (preferably via SSH):

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/dzeykop/proxmox-beaver-iot/main/install.sh)"
```

## What it does

- Downloads the official Debian 12 cloud image
- Lets you choose VM ID, hostname, CPU, RAM, disk, storage, bridge and web port interactively
- Creates the VM with QEMU guest agent enabled
- Installs Docker and runs the `milesight/beaver-iot` container
- Shows the web UI address, MQTT port and SSH login when finished

## Default settings

| Setting | Default |
|---|---|
| Cores | 2 |
| RAM | 4096 MB |
| Disk | 32 GB |
| Web port | 9080 |
| MQTT port | 1883 |
| User | beaver |

## After installation

- Web UI: `http://<VM-IP>:9080`
- MQTT broker: `<VM-IP>:1883`
- Data is stored in `/opt/beaver-iot` inside the VM

The first boot takes a few minutes while Docker and Beaver IoT are installed.

## Requirements

- Proxmox VE 8 or 9
- Internet access on the host and VM

## Notes

This is a personal learning project and is not affiliated with Milesight.

Made by JFFK.
