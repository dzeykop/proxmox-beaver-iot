#!/usr/bin/env bash
# =============================================================
#  proxmox-beaver-iot - One-command Beaver IoT VM installer
#  Version: 1.0.1
#  Repo:    github.com/dzeykop/proxmox-beaver-iot
#  Signed:  from JFFK
# =============================================================
set -euo pipefail

VERSION="1.0.1"
IMG_URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
IMG_FILE="/var/lib/vz/template/iso/debian-12-genericcloud-amd64.qcow2"
SNIPPET_DIR="/var/lib/vz/snippets"
MQTTPORT="1883"

msg()  { echo -e "\e[1;34m[INFO]\e[0m $*"; }
ok()   { echo -e "\e[1;32m[ OK ]\e[0m $*"; }
fail() { echo -e "\e[1;31m[FAIL]\e[0m $*"; exit 1; }

# --- Pre-checks ---------------------------------------------------
[[ $EUID -eq 0 ]] || fail "Run as root."
command -v qm >/dev/null || fail "This is not a Proxmox VE host."
command -v whiptail >/dev/null || apt-get install -y whiptail >/dev/null

whiptail --title "Beaver IoT Installer v$VERSION" --yesno \
"This will create a new Debian 12 VM with Docker and Milesight Beaver IoT.\n\nContinue?" 12 60 || exit 0

# --- Interactive settings -----------------------------------------
NEXTID=$(pvesh get /cluster/nextid)
VMID=$(whiptail --inputbox "VM ID" 8 50 "$NEXTID" 3>&1 1>&2 2>&3) || exit 0
qm status "$VMID" &>/dev/null && fail "VM ID $VMID already exists."
VMNAME=$(whiptail --inputbox "Hostname" 8 50 "beaver-iot" 3>&1 1>&2 2>&3) || exit 0
CORES=$(whiptail --inputbox "CPU cores" 8 50 "2" 3>&1 1>&2 2>&3) || exit 0
RAM=$(whiptail --inputbox "RAM in MB" 8 50 "4096" 3>&1 1>&2 2>&3) || exit 0
DISK=$(whiptail --inputbox "Disk size in GB" 8 50 "32" 3>&1 1>&2 2>&3) || exit 0
BRIDGE=$(whiptail --inputbox "Network bridge" 8 50 "vmbr0" 3>&1 1>&2 2>&3) || exit 0
STORAGE=$(whiptail --inputbox "VM disk storage" 8 50 "local-lvm" 3>&1 1>&2 2>&3) || exit 0
WEBPORT=$(whiptail --inputbox "Beaver IoT web port" 8 50 "9080" 3>&1 1>&2 2>&3) || exit 0
CIUSER=$(whiptail --inputbox "Linux user" 8 50 "beaver" 3>&1 1>&2 2>&3) || exit 0
CIPASS=$(whiptail --passwordbox "Password for $CIUSER" 8 50 3>&1 1>&2 2>&3) || exit 0
[[ -n "$CIPASS" ]] || fail "Password must not be empty."

# --- Enable snippets on 'local' -------------------------------------
CONTENT=$(pvesm config local 2>/dev/null | awk '/content/ {print $2}' || true)
if [[ "$CONTENT" != *snippets* ]]; then
  msg "Enabling 'snippets' content on storage 'local'"
  pvesm set local --content "${CONTENT:+$CONTENT,}snippets"
fi
mkdir -p "$SNIPPET_DIR"

# --- Download image --------------------------------------------------
if [[ ! -f "$IMG_FILE" ]]; then
  msg "Downloading Debian 12 cloud image"
  wget -q --show-progress -O "$IMG_FILE" "$IMG_URL"
fi
ok "Image ready"

# --- Cloud-init: Docker + Beaver IoT --------------------------------
cat > "$SNIPPET_DIR/beaver-$VMID.yaml" <<EOF
#cloud-config
package_update: true
packages: [qemu-guest-agent, curl, ca-certificates]
runcmd:
  - systemctl enable --now qemu-guest-agent
  - curl -fsSL https://get.docker.com | sh
  - usermod -aG docker $CIUSER
  - mkdir -p /opt/beaver-iot
  - docker run -d --name beaver-iot --restart unless-stopped -v /opt/beaver-iot:/root/beaver-iot -p $WEBPORT:80 -p $MQTTPORT:1883 milesight/beaver-iot
EOF

# --- Create VM ----------------------------------------------------------
msg "Creating VM $VMID ($VMNAME)"
qm create "$VMID" --name "$VMNAME" --cores "$CORES" --memory "$RAM" \
  --net0 virtio,bridge="$BRIDGE" --scsihw virtio-scsi-single \
  --ostype l26 --agent enabled=1 --serial0 socket --vga serial0 \
  --description "Milesight Beaver IoT - installer v$VERSION - from JFFK"
qm importdisk "$VMID" "$IMG_FILE" "$STORAGE" >/dev/null
qm set "$VMID" --scsi0 "$STORAGE:vm-$VMID-disk-0,discard=on,ssd=1" \
  --boot order=scsi0 --ide2 "$STORAGE:cloudinit" \
  --ciuser "$CIUSER" --cipassword "$CIPASS" --ipconfig0 ip=dhcp \
  --cicustom "vendor=local:snippets/beaver-$VMID.yaml" >/dev/null
qm resize "$VMID" scsi0 "${DISK}G" >/dev/null
qm start "$VMID"
ok "VM started"

# --- Wait for IP ------------------------------------------------------
msg "Waiting for the VM to get an IP (first boot takes a few minutes)"
IP=""
for i in {1..60}; do
  IP=$(qm guest cmd "$VMID" network-get-interfaces 2>/dev/null \
    | grep -oP '"ip-address"\s*:\s*"\K(\d+\.){3}\d+' | grep -v '^127\.' | head -n1 || true)
  [[ -n "$IP" ]] && break
  sleep 10
done

echo
ok "Beaver IoT installer v$VERSION finished - from JFFK"
if [[ -n "$IP" ]]; then
  echo "  Web UI:  http://$IP:$WEBPORT  (Docker install may still need 2-5 min)"
  echo "  MQTT:    $IP:$MQTTPORT"
  echo "  SSH:     ssh $CIUSER@$IP"
else
  echo "  No IP yet. Check later with: qm guest cmd $VMID network-get-interfaces"
fi
