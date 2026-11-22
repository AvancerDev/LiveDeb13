#!/bin/bash
# LiveDeb13 — verifica che tutti i pacchetti delle liste esistano in Debian 13.
#
# Evita build lunghe interrotte a metà per un nome sbagliato
# (es. "E: Unable to locate package gptfdisk": in Debian il pacchetto è gdisk).
#
# Uso:
#   ./check-packages.sh            # controlla config/package-lists/*
#   RUNTIME=podman ./check-packages.sh
#
# Richiede docker o podman (usa un container debian:trixie, ~30 secondi).
set -euo pipefail
cd "$(dirname "$0")"

RUNTIME="${RUNTIME:-}"
if [ -z "$RUNTIME" ]; then
  if command -v docker >/dev/null 2>&1; then
    RUNTIME=docker
  elif command -v podman >/dev/null 2>&1; then
    RUNTIME=podman
  else
    echo "ERRORE: serve 'docker' oppure 'podman' (oppure controlla a mano su https://packages.debian.org/trixie/<pacchetto>)."
    exit 1
  fi
fi

SUDO=""
if [ "$RUNTIME" = "docker" ] && ! docker info >/dev/null 2>&1; then
  SUDO="sudo"
fi

echo "==> Controllo dei pacchetti in Debian 13 (container debian:trixie)..."
${SUDO} $RUNTIME run --rm -i -v "$PWD":/build -w /build \
  -e DEBIAN_FRONTEND=noninteractive \
  debian:trixie bash -c '
    set -e
    # abilita le aree usate da auto/config
    sed -i "s/^Components: .*/Components: main contrib non-free non-free-firmware/" \
      /etc/apt/sources.list.d/debian.sources 2>/dev/null || true
    apt-get update -qq

    rc=0
    for f in config/package-lists/*; do
      [ -f "$f" ] || continue
      while IFS= read -r pkg; do
        pkg="$(printf "%s" "$pkg" | tr -d "\r" | sed "s/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//")"
        [ -z "$pkg" ] && continue
        if ! apt-cache show "$pkg" >/dev/null 2>&1; then
          echo "MANCANTE in Debian 13: $pkg   (in $f)"
          rc=1
        fi
      done < "$f"
    done

    if [ "$rc" -eq 0 ]; then
      echo "OK: tutti i pacchetti delle liste esistono in Debian 13."
    else
      echo
      echo "Correggi i nomi qui sopra (nomi Debian, non Ubuntu) e rilancia."
    fi
    exit $rc
  '
