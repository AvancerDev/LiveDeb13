#!/bin/bash
# LiveDeb13 — build dell'ISO in un container Debian 13 (trixie).
#
# Serve quando l'host NON è Debian 13: per esempio Ubuntu, dove il pacchetto
# live-build è fermo alla 3.0~a57 (epoca Debian 7) e non può costruire trixie.
# Il container fornisce l'ambiente Debian 13 corretto, identico alla CI.
#
# Requisiti: docker oppure podman.
# Uso:
#   ./build-docker.sh                # build completa
#   ./build-docker.sh --clean        # pulizia prima della build
#   RUNTIME=podman ./build-docker.sh
#
# Note:
# - serve --privileged: live-build crea chroot e monta /proc, /sys, /dev;
# - la ISO e le directory di build restano nella cartella del progetto;
# - se docker richiede sudo, lo script lo usa automaticamente.
set -euo pipefail
cd "$(dirname "$0")"

CLEAN=0
for arg in "$@"; do
  case "$arg" in
    --clean) CLEAN=1 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "Argomento sconosciuto: $arg"; exit 1 ;;
  esac
done

RUNTIME="${RUNTIME:-}"
if [ -z "$RUNTIME" ]; then
  if command -v docker >/dev/null 2>&1; then
    RUNTIME=docker
  elif command -v podman >/dev/null 2>&1; then
    RUNTIME=podman
  else
    echo "ERRORE: serve 'docker' oppure 'podman'."
    echo "  Ubuntu/Debian: sudo apt install docker.io   (oppure: podman)"
    exit 1
  fi
fi

SUDO=""
if [ "$RUNTIME" = "docker" ] && ! docker info >/dev/null 2>&1; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
    echo "NOTA: docker richiede privilegi, uso sudo."
  else
    echo "ERRORE: docker non accessibile e 'sudo' non disponibile."
    exit 1
  fi
fi

HOST_UID="$(id -u)"
HOST_GID="$(id -g)"

# Pulizia preventiva (dentro il container, come root)
if [ "$CLEAN" = "1" ]; then
  echo "==> Pulizia (lb clean --purge)..."
  ${SUDO} $RUNTIME run --rm -i --privileged -v "$PWD":/build -w /build \
    debian:trixie bash -c '
      set -e
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -qq
      apt-get install -y -qq --no-install-recommends live-build >/dev/null
      lb clean --purge || true
      rm -rf chroot binary cache .build
    '
fi

echo "==> Build in container debian:trixie con $RUNTIME (può durare 10-30 minuti)..."
${SUDO} $RUNTIME run --rm -i --privileged \
  -v "$PWD":/build -w /build \
  -e DEBIAN_FRONTEND=noninteractive \
  -e HOST_UID="$HOST_UID" -e HOST_GID="$HOST_GID" \
  debian:trixie bash -c '
    set -e
    apt-get update
    apt-get install -y --no-install-recommends \
      live-build debootstrap squashfs-tools xorriso isolinux syslinux-common \
      grub-pc-bin grub-efi-amd64-bin mtools dosfstools ca-certificates \
      cpio zstd xz-utils file rsync git

    echo "==> live-build installata:"
    lb --version

    ./auto/config
    ./auto/build

    # I file creati come root nel container appartengono a root anche sull host
    chown -R "${HOST_UID}:${HOST_GID}" .build cache chroot binary 2>/dev/null || true
    chown "${HOST_UID}:${HOST_GID}" ./*.iso 2>/dev/null || true
  '

echo
if [ -f livedeb13-amd64.hybrid.iso ]; then
  echo "==> OK: livedeb13-amd64.hybrid.iso ($(du -h livedeb13-amd64.hybrid.iso | cut -f1))"
else
  echo "ERRORE: ISO non generata (vedi output sopra)." >&2
  exit 1
fi
