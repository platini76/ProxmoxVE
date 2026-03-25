#!/usr/bin/env bash
set -euo pipefail

trap 'echo "Errore alla riga $LINENO" >&2' ERR

msg() { echo -e "\n==> $*"; }
die() { echo "ERRORE: $*" >&2; exit 1; }
ask() {
  local prompt="$1"
  read -r -p "$prompt [s/N]: " ans
  [[ "${ans:-}" =~ ^[sS]$ ]]
}

command -v pct >/dev/null 2>&1 || die "Esegui questo script sulla shell del nodo Proxmox, come root."

[[ $EUID -eq 0 ]] || die "Serve root."

msg "Controllo storage e template"
PVE_STORAGE="${PVE_STORAGE:-local-lvm}"
PVE_BRIDGE="${PVE_BRIDGE:-vmbr0}"
PVE_TZ="${PVE_TZ:-Europe/Rome}"
PVE_ARCH="${PVE_ARCH:-amd64}"
PVE_DIST="${PVE_DIST:-debian}"
PVE_VER="${PVE_VER:-12}"

if ! pct config 99999 >/dev/null 2>&1; then :; fi

if ! pveam available | grep -qE "debian-${PVE_VER}-standard"; then
  msg "Aggiorno lista template"
  pveam update >/dev/null
fi

TEMPLATE="debian-${PVE_VER}-standard_${PVE_VER}.0-1_${PVE_ARCH}.tar.zst"
if ! pveam available | awk '{print $1}' | grep -qx "$TEMPLATE"; then
  TEMPLATE="$(pveam available | awk '/debian-12-standard/ {print $1; exit}')"
fi
[[ -n "${TEMPLATE:-}" ]] || die "Template Debian non trovato."

CTID="${CTID:-}"
if [[ -z "${CTID}" ]]; then
  for id in $(seq 200 299); do
    if ! pct status "$id" >/dev/null 2>&1; then CTID="$id"; break; fi
  done
fi
[[ -n "${CTID:-}" ]] || die "Impossibile trovare un CTID libero."

HOSTNAME="${HOSTNAME:-bambuddy}"
DISK_GB="${DISK_GB:-8}"
MEM_MB="${MEM_MB:-1024}"
SWAP_MB="${SWAP_MB:-512}"
CORES="${CORES:-2}"
PASSWORD="${PASSWORD:-}"

msg "Parametri previsti"
echo "CTID=$CTID"
echo "HOSTNAME=$HOSTNAME"
echo "TEMPLATE=$TEMPLATE"
echo "STORAGE=$PVE_STORAGE"
echo "BRIDGE=$PVE_BRIDGE"
echo "DISK=${DISK_GB}G MEM=${MEM_MB}MB SWAP=${SWAP_MB}MB CORES=$CORES"
echo "TZ=$PVE_TZ"

ask "Continuare con la creazione del container?" || die "Annullato."

msg "Scarico template"
pveam download "$PVE_STORAGE" "$TEMPLATE"

TEMPLATE_PATH="/var/lib/vz/template/cache/$TEMPLATE"
if [[ ! -f "$TEMPLATE_PATH" ]]; then
  TEMPLATE_PATH="/mnt/pve/$PVE_STORAGE/template/cache/$TEMPLATE"
fi
[[ -f "$TEMPLATE_PATH" ]] || die "Template non trovato nel percorso atteso."

msg "Creo CT unprivileged"
pct create "$CTID" "$TEMPLATE_PATH" \
  --hostname "$HOSTNAME" \
  --cores "$CORES" \
  --memory "$MEM_MB" \
  --swap "$SWAP_MB" \
  --rootfs "${PVE_STORAGE}:${DISK_GB}" \
  --net0 "name=eth0,bridge=${PVE_BRIDGE},ip=dhcp" \
  --ostype debian \
  --unprivileged 1 \
  --features "keyctl=1,nesting=1" \
  --onboot 1 \
  --timezone "$PVE_TZ"

if [[ -n "$PASSWORD" ]]; then
  pct set "$CTID" --password "$PASSWORD"
fi

msg "Avvio container"
pct start "$CTID"

msg "Attendo boot"
sleep 8

msg "Aggiorno pacchetti e installo Docker"
pct exec "$CTID" -- bash -lc '
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian "$VERSION_CODENAME" stable" > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
docker --version
'

msg "Creo directory Bambuddy e scarico compose"
pct exec "$CTID" -- bash -lc '
set -euo pipefail
mkdir -p /opt/bambuddy
cd /opt/bambuddy
curl -fsSL https://raw.githubusercontent.com/maziggy/bambuddy/main/docker-compose.yml -o docker-compose.yml
mkdir -p data logs
sed -i "s#TZ=Europe/Berlin#TZ='"$PVE_TZ"'#g" docker-compose.yml || true
docker compose up -d
'

msg "Fatto"
echo "CT creato: $CTID"
echo "Accesso: pct enter $CTID"
echo "Bambuddy: nel CT, directory /opt/bambuddy"
