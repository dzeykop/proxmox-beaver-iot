#!/usr/bin/env bash
# =============================================================
#  proxmox-beaver-iot - One-command Beaver IoT VM installer
#  Version: 1.2.0
#  Repo:    github.com/dzeykop/proxmox-beaver-iot
#  Signed:  from JFFK
# =============================================================
set -euo pipefail

VERSION="1.2.0"
IMG_URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
IMG_FILE="/var/lib/vz/template/iso/debian-12-genericcloud-amd64.qcow2"
SNIPPET_DIR="/var/lib/vz/snippets"
MQTTPORT="1883"
BEAVER_IMAGE="milesight/beaver-iot:latest"

# Recommended / minimum values for Beaver IoT
REC_CORES=2;  MIN_CORES=1
REC_RAM=4096; MIN_RAM=2048
REC_DISK=32;  MIN_DISK=16

msg()  { echo -e "\e[1;34m[INFO]\e[0m $*"; }
ok()   { echo -e "\e[1;32m[ OK ]\e[0m $*"; }
warn() { echo -e "\e[1;33m[WARN]\e[0m $*"; }
fail() { echo -e "\e[1;31m[FAIL]\e[0m $*"; exit 1; }

is_num() { [[ "$1" =~ ^[0-9]+$ ]]; }

# --- Pre-checks ---------------------------------------------------
[[ $EUID -eq 0 ]] || fail "Run as root."
command -v qm >/dev/null || fail "This is not a Proxmox VE host."
command -v whiptail >/dev/null || apt-get install -y whiptail >/dev/null

# --- Host resources -----------------------------------------------
HOST_CORES=$(nproc)
HOST_RAM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
HOST_RAM_FREE=$(free -m | awk '/Mem:/ {print $7}')

whiptail --title "Beaver IoT Installer v$VERSION" --yesno \
"This will create a new Debian 12 VM with Docker and Milesight Beaver IoT.

Host resources:
  CPU cores:      $HOST_CORES
  RAM total:      $HOST_RAM_TOTAL MB
  RAM available:  $HOST_RAM_FREE MB

Recommended for Beaver IoT:
  $REC_CORES cores, $REC_RAM MB RAM, $REC_DISK GB disk

Continue?" 20 64 || exit 0

# --- Helper: ask for a number with check ---------------------------
# Dialogs inside use >&2 so they stay visible inside $( ... )
ask_num() {
  local title="$1" text="$2" def="$3" min="$4" max="$5" val
  while true; do
    val=$(whiptail --title "$title" --inputbox "$text" 14 64 "$def" 3>&1 1>&2 2>&3) || return 1
    if ! is_num "$val"; then
      whiptail --msgbox "Please enter a number." 8 40 >&2; continue
    fi
    if (( val > max )); then
      whiptail --msgbox "Maximum available is $max." 8 40 >&2; continue
    fi
    if (( val < min )); then
      whiptail --yesno "$val is below the recommended minimum of $min.\nUse it anyway?" 10 50 >&2 || continue
    fi
    echo "$val"; return 0
  done
}

# --- VM ID and name ------------------------------------------------
NEXTID=$(pvesh get /cluster/nextid)
while true; do
  VMID=$(whiptail --title "VM ID" --inputbox "VM ID (next free: $NEXTID)" 10 50 "$NEXTID" 3>&1 1>&2 2>&3) || exit 0
  if ! is_num "$VMID"; then whiptail --msgbox "Please enter a number." 8 40; continue; fi
  if qm status "$VMID" &>/dev/null || pct status "$VMID" &>/dev/null; then
    whiptail --msgbox "ID $VMID is already in use." 8 40; continue
  fi
  break
done
VMNAME=$(whiptail --title "Hostname" --inputbox "Hostname" 10 50 "beaver-iot" 3>&1 1>&2 2>&3) || exit 0

# --- CPU, RAM -------------------------------------------------------
CORES=$(ask_num "CPU" "CPU cores\n\nHost has: $HOST_CORES\nRecommended: $REC_CORES\nMinimum: $MIN_CORES" \
  "$REC_CORES" "$MIN_CORES" "$HOST_CORES") || exit 0
RAM=$(ask_num "RAM" "RAM in MB\n\nHost total: $HOST_RAM_TOTAL MB\nHost available: $HOST_RAM_FREE MB\nRecommended: $REC_RAM MB\nMinimum: $MIN_RAM MB" \
  "$REC_RAM" "$MIN_RAM" "$HOST_RAM_TOTAL") || exit 0
if (( RAM > HOST_RAM_FREE )); then
  whiptail --msgbox "Note: $RAM MB is more than currently available ($HOST_RAM_FREE MB).\nThe host may start swapping." 10 60
fi

# --- Storage selection with free space ------------------------------
STORAGE_MENU=()
while read -r name type status total used avail pct; do
  STORAGE_MENU+=("$name" "$type - free: $((avail / 1024 / 1024)) GB")
done < <(pvesm status -content images | awk 'NR>1')
[[ ${#STORAGE_MENU[@]} -gt 0 ]] || fail "No storage for VM disks found."
STORAGE=$(whiptail --title "Storage" --menu "Select storage for the VM disk" 16 64 6 \
  "${STORAGE_MENU[@]}" 3>&1 1>&2 2>&3) || exit 0
STORAGE_FREE_GB=$(pvesm status -storage "$STORAGE" | awk 'NR>1 {print int($6/1024/1024)}')

DISK=$(ask_num "Disk" "Disk size in GB\n\nFree on $STORAGE: $STORAGE_FREE_GB GB\nRecommended: $REC_DISK GB\nMinimum: $MIN_DISK GB" \
  "$REC_DISK" "$MIN_DISK" "$STORAGE_FREE_GB") || exit 0

# --- Network bridge selection ---------------------------------------
BRIDGE_MENU=()
for b in $(ip -o link show type bridge | awk -F': ' '{print $2}'); do
  BRIDGE_MENU+=("$b" "")
done
[[ ${#BRIDGE_MENU[@]} -gt 0 ]] || fail "No network bridge found."
BRIDGE=$(whiptail --title "Network" --menu "Select network bridge" 14 50 5 \
  "${BRIDGE_MENU[@]}" 3>&1 1>&2 2>&3) || exit 0

# --- Ports and user -------------------------------------------------
WEBPORT=$(ask_num "Web port" "Beaver IoT web port\n\nDefault: 9080" "9080" 1 65535) || exit 0
CIUSER=$(whiptail --title "User" --inputbox "Linux user" 10 50 "beaver" 3>&1 1>&2 2>&3) || exit 0
while true; do
  CIPASS=$(whiptail --title "Password" --passwordbox "Password for $CIUSER" 10 50 3>&1 1>&2 2>&3) || exit 0
  CIPASS2=$(whiptail --title "Password" --passwordbox "Repeat password" 10 50 3>&1 1>&2 2>&3) || exit 0
  if [[ -z "$CIPASS" ]]; then whiptail --msgbox "Password must not be empty." 8 40; continue; fi
  if [[ "$CIPASS" != "$CIPASS2" ]]; then whiptail --msgbox "Passwords do not match." 8 40; continue; fi
  break
done

# --- Summary --------------------------------------------------------
whiptail --title "Summary" --yesno \
"Please confirm:

  VM ID:     $VMID
  Hostname:  $VMNAME
  Cores:     $CORES
  RAM:       $RAM MB
  Disk:      $DISK GB on $STORAGE
  Bridge:    $BRIDGE
  Web port:  $WEBPORT
  MQTT port: $MQTTPORT
  User:      $CIUSER

Includes a daily update check with a notice at login.
Updates are only installed when you run 'sudo beaver-update'.

Create the VM now?" 24 64 || exit 0

# --- Enable snippets on 'local' -------------------------------------
CONTENT=$(pvesm config local 2>/dev/null | awk '/content/ {print $2}' || true)
if [[ "$CONTENT" != *snippets* ]]; then
  msg "Enabling 'snippets' content on storage 'local'"
  pvesm set local --content "${CONTENT:+$CONTENT,}snippets"
fi
mkdir -p "$SNIPPET_DIR"

# --- Download image -------------------------------------------------
if [[ ! -f "$IMG_FILE" ]]; then
  msg "Downloading Debian 12 cloud image"
  wget -q --show-progress -O "$IMG_FILE" "$IMG_URL"
fi
ok "Image ready"

# =============================================================
#  Files placed inside the VM
# =============================================================

# --- /etc/beaver-iot.conf -------------------------------------------
read -r -d '' F_CONF <<EOF || true
# Beaver IoT settings - created by proxmox-beaver-iot v$VERSION - from JFFK
NAME=beaver-iot
IMAGE=$BEAVER_IMAGE
DATA_DIR=/opt/beaver-iot
BACKUP_DIR=/opt/beaver-iot-backups
KEEP_BACKUPS=3
WEBPORT=$WEBPORT
MQTTPORT=$MQTTPORT
EOF

# --- /usr/local/bin/beaver-update -----------------------------------
read -r -d '' F_UPDATE <<'EOF' || true
#!/usr/bin/env bash
# beaver-update - update helper for Beaver IoT (from JFFK)
#
#   sudo beaver-update             check and, after your confirmation, update
#   sudo beaver-update --status    show installed version, update and backups
#   sudo beaver-update --rollback  go back to the version before the last update
#   beaver-update --check          only check (used by the daily timer)
set -euo pipefail

CONF=/etc/beaver-iot.conf
[[ -f "$CONF" ]] && source "$CONF"
NAME=${NAME:-beaver-iot}
IMAGE=${IMAGE:-milesight/beaver-iot:latest}
DATA_DIR=${DATA_DIR:-/opt/beaver-iot}
BACKUP_DIR=${BACKUP_DIR:-/opt/beaver-iot-backups}
KEEP_BACKUPS=${KEEP_BACKUPS:-3}
WEBPORT=${WEBPORT:-9080}
MQTTPORT=${MQTTPORT:-1883}
ROLLBACK_TAG="beaver-iot:rollback"
STATE_DIR=/var/lib/beaver-iot
FLAG="$STATE_DIR/update-available"

msg()  { echo -e "\e[1;34m[INFO]\e[0m $*"; }
ok()   { echo -e "\e[1;32m[ OK ]\e[0m $*"; }
warn() { echo -e "\e[1;33m[WARN]\e[0m $*"; }
fail() { echo -e "\e[1;31m[FAIL]\e[0m $*"; exit 1; }

[[ $EUID -eq 0 ]] || fail "Please run with sudo: sudo beaver-update $*"
mkdir -p "$STATE_DIR" "$BACKUP_DIR"

running_id() { docker inspect --format '{{.Image}}' "$NAME" 2>/dev/null || true; }
local_id()   { docker image inspect --format '{{.Id}}' "$IMAGE" 2>/dev/null || true; }
img_date()   { docker image inspect --format '{{.Created}}' "$1" 2>/dev/null | cut -c1-10 || echo "unknown"; }

run_container() {
  docker run -d --name "$NAME" --restart unless-stopped \
    -v "$DATA_DIR:/root/beaver-iot" \
    -p "$WEBPORT:80" -p "$MQTTPORT:1883" "$1" >/dev/null
}

wait_web() {
  local code
  for i in {1..36}; do
    code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$WEBPORT" || true)
    [[ "$code" != "000" ]] && return 0
    sleep 5
  done
  return 1
}

backup() {
  local file="$BACKUP_DIR/beaver-iot-$(date +%F_%H%M).tar.gz"
  msg "Creating backup: $file"
  tar -czf "$file" -C "$(dirname "$DATA_DIR")" "$(basename "$DATA_DIR")"
  ls -1t "$BACKUP_DIR"/beaver-iot-*.tar.gz 2>/dev/null | tail -n +$((KEEP_BACKUPS + 1)) | xargs -r rm -f
  ok "Backup done (keeping the last $KEEP_BACKUPS)"
}

# Returns 0 when a newer image is available
check() {
  docker pull -q "$IMAGE" >/dev/null || { warn "Could not reach Docker Hub."; return 1; }
  if [[ -n "$(local_id)" && "$(running_id)" != "$(local_id)" ]]; then
    date '+%F' > "$FLAG"; return 0
  fi
  rm -f "$FLAG"; return 1
}

do_init() {
  mkdir -p "$DATA_DIR"
  docker pull -q "$IMAGE" >/dev/null
  [[ -z "$(running_id)" ]] && run_container "$IMAGE"
  ok "Beaver IoT started"
}

do_status() {
  echo "Container: $NAME"
  echo "Running:   $(running_id | cut -c8-19) (built $(img_date "$(running_id)"))"
  echo "Latest:    $(local_id | cut -c8-19) (built $(img_date "$IMAGE"), as of last check)"
  if [[ -f "$FLAG" ]]; then echo "Update:    available (found $(cat "$FLAG"))"; else echo "Update:    none known"; fi
  if docker image inspect "$ROLLBACK_TAG" &>/dev/null; then echo "Rollback:  possible"; else echo "Rollback:  not available"; fi
  echo "Backups:   $(ls -1 "$BACKUP_DIR"/beaver-iot-*.tar.gz 2>/dev/null | wc -l) in $BACKUP_DIR"
}

do_update() {
  msg "Checking for a new Beaver IoT version..."
  if ! check; then ok "Beaver IoT is up to date."; exit 0; fi

  echo
  echo "  Installed: built $(img_date "$(running_id)")"
  echo "  New:       built $(img_date "$IMAGE")"
  echo
  echo "  A backup of $DATA_DIR is created first."
  echo "  If something goes wrong: sudo beaver-update --rollback"
  echo
  read -rp "Install the update now? [y/N] " ans
  [[ "$ans" =~ ^[yYjJ]$ ]] || { msg "Update skipped. The login notice stays until you update."; exit 0; }

  docker tag "$(running_id)" "$ROLLBACK_TAG"
  msg "Stopping Beaver IoT"
  docker stop "$NAME" >/dev/null
  backup
  docker rm "$NAME" >/dev/null
  msg "Starting the new version"
  run_container "$IMAGE"
  msg "Waiting for the web UI (up to 3 min)"
  if wait_web; then
    rm -f "$FLAG"
    docker image prune -f >/dev/null
    ok "Update finished. Web UI on port $WEBPORT"
  else
    warn "Web UI does not answer yet. Check with: docker logs $NAME"
    warn "To go back: sudo beaver-update --rollback"
  fi
}

do_rollback() {
  docker image inspect "$ROLLBACK_TAG" &>/dev/null || fail "No previous version available."
  local last
  last=$(ls -1t "$BACKUP_DIR"/beaver-iot-*.tar.gz 2>/dev/null | head -n1 || true)
  echo "This goes back to the version before the last update."
  [[ -n "$last" ]] && echo "Data will be restored from: $last"
  read -rp "Continue? [y/N] " ans
  [[ "$ans" =~ ^[yYjJ]$ ]] || exit 0

  docker stop "$NAME" &>/dev/null || true
  docker rm "$NAME" &>/dev/null || true
  if [[ -n "$last" ]]; then
    local failed="$DATA_DIR.failed-$(date +%F_%H%M)"
    mv "$DATA_DIR" "$failed"
    tar -xzf "$last" -C "$(dirname "$DATA_DIR")"
    msg "Current data kept in $failed"
  fi
  run_container "$ROLLBACK_TAG"
  ok "Rollback done. Beaver IoT runs the previous version."
}

case "${1:-}" in
  --init)      do_init ;;
  --check)     check || true ;;
  --status)    do_status ;;
  --rollback)  do_rollback ;;
  ""|--update) do_update ;;
  -h|--help)   sed -n '2,8p' "$0" ;;
  *) fail "Unknown option: $1 (see --help)" ;;
esac
EOF

# --- Login notice ----------------------------------------------------
read -r -d '' F_PROFILE <<'EOF' || true
# Beaver IoT update notice - from JFFK
if [ -f /var/lib/beaver-iot/update-available ]; then
  printf '\n\033[1;33m[Beaver IoT]\033[0m A new version is available (found %s).\n             Install it with: sudo beaver-update\n\n' "$(cat /var/lib/beaver-iot/update-available)"
fi
EOF

# --- Daily check (systemd) -------------------------------------------
read -r -d '' F_SERVICE <<'EOF' || true
[Unit]
Description=Check for Beaver IoT updates (no install)
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/beaver-update --check
EOF

read -r -d '' F_TIMER <<'EOF' || true
[Unit]
Description=Daily Beaver IoT update check

[Timer]
OnBootSec=15min
OnCalendar=daily
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF

b64() { printf '%s\n' "$1" | base64 -w0; }

# --- Cloud-init ------------------------------------------------------
cat > "$SNIPPET_DIR/beaver-$VMID.yaml" <<EOF
#cloud-config
package_update: true
packages: [qemu-guest-agent, curl, ca-certificates]
write_files:
  - path: /etc/beaver-iot.conf
    permissions: '0644'
    encoding: b64
    content: $(b64 "$F_CONF")
  - path: /usr/local/bin/beaver-update
    permissions: '0755'
    encoding: b64
    content: $(b64 "$F_UPDATE")
  - path: /etc/profile.d/beaver-update.sh
    permissions: '0644'
    encoding: b64
    content: $(b64 "$F_PROFILE")
  - path: /etc/systemd/system/beaver-update-check.service
    permissions: '0644'
    encoding: b64
    content: $(b64 "$F_SERVICE")
  - path: /etc/systemd/system/beaver-update-check.timer
    permissions: '0644'
    encoding: b64
    content: $(b64 "$F_TIMER")
runcmd:
  - systemctl enable --now qemu-guest-agent
  - curl -fsSL https://get.docker.com | sh
  - usermod -aG docker $CIUSER
  - /usr/local/bin/beaver-update --init
  - systemctl daemon-reload
  - systemctl enable --now beaver-update-check.timer
EOF

# --- Create VM ------------------------------------------------------
msg "Creating VM $VMID ($VMNAME)"
qm create "$VMID" --name "$VMNAME" --cores "$CORES" --memory "$RAM" \
  --net0 virtio,bridge="$BRIDGE" --scsihw virtio-scsi-single \
  --ostype l26 --agent enabled=1 --serial0 socket --vga serial0 \
  --description "Milesight Beaver IoT - installer v$VERSION - from JFFK"
qm importdisk "$VMID" "$IMG_FILE" "$STORAGE" >/dev/null
DISKREF=$(qm config "$VMID" | awk -F': ' '/^unused0/ {print $2}')
qm set "$VMID" --scsi0 "$DISKREF,discard=on,ssd=1" \
  --boot order=scsi0 --ide2 "$STORAGE:cloudinit" \
  --ciuser "$CIUSER" --cipassword "$CIPASS" --ipconfig0 ip=dhcp \
  --cicustom "vendor=local:snippets/beaver-$VMID.yaml" >/dev/null
qm resize "$VMID" scsi0 "${DISK}G" >/dev/null
qm start "$VMID"
ok "VM started"

# --- Wait for IP ----------------------------------------------------
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
echo "  Update:  sudo beaver-update  (inside the VM, you get a notice at login)"
