#!/bin/bash
# LiveDeb13 — script di build comodo (alternativa a `make build`)
# Uso: ./build.sh [--clean] [--config-only]
set -euo pipefail
cd "$(dirname "$0")"

CLEAN=false
CONFIG_ONLY=false
for arg in "$@"; do
  case "$arg" in
    --clean) CLEAN=true ;;
    --config-only) CONFIG_ONLY=true ;;
    *) echo "Argomento sconosciuto: $arg"; exit 1 ;;
  esac
done

if ! command -v lb >/dev/null 2>&1; then
  echo "ERRORE: 'lb' (live-build) non trovato."
  echo "Installa i prerequisiti (vedi README.md):"
  echo "  sudo apt install live-build debootstrap squashfs-tools xorriso isolinux syslinux-common"
  exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "NOTA: la build richiede root. Re-eseguo con sudo..."
  exec sudo "$0" "$@"
fi

if [ "$CLEAN" = true ]; then
  echo "==> Pulizia..."
  ./auto/clean --purge || true
fi

echo "==> Configurazione (lb config)..."
./auto/config

if [ "$CONFIG_ONLY" = true ]; then
  echo "Configurazione completata. Per compilare: sudo ./auto/build"
  exit 0
fi

echo "==> Build ISO (lb build)..."
./auto/build "$@"

ISO="livedeb13-amd64.hybrid.iso"
if [ -f "$ISO" ]; then
  echo "==> OK: $ISO ($(du -h "$ISO" | cut -f1))"
else
  echo "ERRORE: ISO non generata." >&2
  exit 1
fi
