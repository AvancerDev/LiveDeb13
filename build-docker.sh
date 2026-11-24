#!/bin/bash
# ZinimalOS — build dell'ISO in un container Debian 13 (trixie).
#
# Serve quando l'host NON è Debian 13: per esempio Ubuntu, dove il pacchetto
# live-build è fermo alla 3.0~a57 (epoca Debian 7) e non può costruire trixie.
# Il container fornisce l'ambiente Debian 13 corretto, identico alla CI.
#
# Requisiti: docker oppure podman.
# Uso:
#   ./build-docker.sh                 # build completa
#   ./build-docker.sh --reset         # reset veloce: rifà chroot/binary, tiene cache/
#   ./build-docker.sh --clean         # pulizia totale (svuota anche cache/)
#   ./build-docker.sh --net-host      # usa la rete dell'host (DNS incluso)
#   ./build-docker.sh --dns 192.168.1.1
#   ./build-docker.sh --debug   # passa --debug a lb build
#   RUNTIME=podman ./build-docker.sh
#
# Note:
# - serve --privileged: live-build crea chroot e monta /proc, /sys, /dev;
# - la ISO e le directory di build restano nella cartella del progetto;
# - se il container non risolve i nomi (errore "Temporary failure resolving"),
#   lo script aggiunge da solo DNS pubblici oppure usa --net-host.
set -euo pipefail
cd "$(dirname "$0")"

CLEAN=0
RESET=0
NET_OPTS=()
DNS_EXPLICIT=0
HOST_NET=0
LB_ARGS=()

usage() { sed -n '2,22p' "$0"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --clean) CLEAN=1 ;;
    --reset|--fast) RESET=1 ;;
    --net-host) NET_OPTS+=(--network host); HOST_NET=1 ;;
    --dns)
      shift
      if [ $# -eq 0 ]; then echo "ERRORE: --dns richiede un indirizzo"; exit 1; fi
      NET_OPTS+=(--dns "$1"); DNS_EXPLICIT=1 ;;
    --dns=*)
      NET_OPTS+=(--dns "${1#--dns=}"); DNS_EXPLICIT=1 ;;
    --debug|--force|--verbose|--quiet) LB_ARGS+=("$1") ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Argomento sconosciuto: $1"; usage; exit 1 ;;
  esac
  shift
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

# --- Diagnostica rete/DNS nel container --------------------------------------
echo "==> Verifica risoluzione DNS nel container ($RUNTIME)..."
if [ "$DNS_EXPLICIT" = "0" ] && [ "$HOST_NET" = "0" ]; then
  if ! ${SUDO} $RUNTIME run --rm "${NET_OPTS[@]}" debian:trixie getent hosts deb.debian.org >/dev/null 2>&1; then
    echo "NOTA: il container non risolve deb.debian.org (DNS non raggiungibile)."
    echo "      Aggiungo DNS pubblici 1.1.1.1 e 9.9.9.9."
    echo "      Se la tua rete usa un DNS interno/proxy, usa: ./build-docker.sh --net-host"
    NET_OPTS+=(--dns 1.1.1.1 --dns 9.9.9.9)
  else
    echo "    DNS OK."
  fi
fi

COMMON_ARGS=(--rm -i --privileged -v "$PWD":/build -w /build)

# Retry per apt/getent: utile su reti lente o instabili
APT_RETRY='
apt_update() {
  n=0
  until apt-get update; do
    n=$((n+1))
    [ "$n" -ge 3 ] && return 1
    echo "    apt-get update fallito, nuovo tentativo ($n/3) tra 10s..."
    sleep 10
  done
}
apt_install() {
  n=0
  until apt-get install -y --no-install-recommends "$@"; do
    n=$((n+1))
    [ "$n" -ge 3 ] && return 1
    echo "    installazione fallita, nuovo tentativo ($n/3) tra 10s..."
    sleep 10
  done
}
'

# --- Stato incoerente: stage file in .build/ ma chroot/ assente --------------
# Dopo un kill forzato (Ctrl-C ignorato, container ucciso, chiusura terminale)
# live-build può lasciare i file di stage che dichiarano "già fatto" gli stadi
# del chroot, mentre chroot/ non esiste più. La build salta tutto e muore su:
#   lb binary_rootfs
#   Cannot stat source directory "chroot" because No such file or directory
# Rimediare solo a .build/ è sufficiente e NON riscarica nulla: la cache dei
# .deb in cache/ resta intatta.
if [ ! -d chroot ] && [ -d .build ]; then
  _stale="$(ls -A .build 2>/dev/null | grep -vx 'config' | grep -vx 'lock' || true)"
  if [ -n "${_stale}" ]; then
    echo "==> Stato incoerente: file di stage in .build/ ma chroot/ assente"
    echo "    (tipico dopo un kill forzato). Rimuovo .build/, cache/ resta intatta."
    rm -rf .build 2>/dev/null || ${SUDO} rm -rf .build
  fi
fi

# --- Lock orfano di live-build ----------------------------------------------
# `lb <stage>` crea un file `.lock` nella directory di build (qui: la radice del
# progetto) e lo rimuove solo se il processo esce "pulito". Dopo un Ctrl-C, un
# container ucciso o un crash resta lì e ogni build successiva muore con:
#   E: lb bootstrap_cache already locked
#   E: An unexpected failure occurred, exiting...
if [ -e .lock ]; then
  echo "==> Rimosso lock orfano .lock (build precedente interrotta)"
  rm -f .lock 2>/dev/null || ${SUDO} rm -f .lock
fi

# --- Reset veloce (chroot/binary sporchi, cache dei .deb conservata) ---------
if [ "$RESET" = "1" ]; then
  echo "==> Reset veloce: rimuovo chroot/, binary/ e .build/ (cache/ conservata)"
  echo "    Nessun riscaricamento: si riparte dai .deb già in cache/."
  if ! rm -rf chroot binary .build 2>/dev/null; then
    ${SUDO} rm -rf chroot binary .build
  fi
  rm -f .lock 2>/dev/null || ${SUDO} rm -f .lock
fi

# --- Pulizia preventiva ------------------------------------------------------
if [ "$CLEAN" = "1" ]; then
  echo "==> Pulizia (lb clean --purge + rimozione chroot/binary/cache/.build)..."
  ${SUDO} $RUNTIME run "${COMMON_ARGS[@]}" "${NET_OPTS[@]}" \
    debian:trixie bash -c "
      set -e
      export DEBIAN_FRONTEND=noninteractive
      ${APT_RETRY}
      apt_update
      apt_install live-build
      lb clean --purge || true
      rm -rf chroot binary cache .build
    "
fi

# --- Build -------------------------------------------------------------------
echo "==> Build in container debian:trixie con $RUNTIME (può durare 10-30 minuti)..."
echo "    ISO finale: zinimalos-amd64.hybrid.iso"
echo "    Log completo: build.log"
set +e
${SUDO} $RUNTIME run "${COMMON_ARGS[@]}" "${NET_OPTS[@]}" \
  -e DEBIAN_FRONTEND=noninteractive \
  -e ZINIMALOS_IN_CONTAINER=1 \
  -e LB_ARGS="${LB_ARGS[*]:-}" \
  -e HOST_UID="$HOST_UID" -e HOST_GID="$HOST_GID" \
  debian:trixie bash -c "
    set -e
    export DEBIAN_FRONTEND=noninteractive
    ${APT_RETRY}
    apt_update
    apt_install \
      live-build debootstrap squashfs-tools xorriso isolinux syslinux-common \
      grub-pc-bin grub-efi-amd64-bin mtools dosfstools ca-certificates \
      cpio zstd xz-utils file rsync git

    echo '==> live-build installata:'
    lb --version

    ./auto/config
    # shellcheck disable=SC2086
    ./auto/build \${LB_ARGS:-}

    # lb config scrive file generati DENTRO config/: senza questo chown
    # l'albero resterebbe di root e git (utente) non potrebbe piu aggiornarlo
    # (errore: unable to create file config/..., Permesso negato).
    #
    # IMPORTANTE: chroot/, cache/ e binary/ NON vanno chownati ricorsivamente.
    # Quei file finiscono DENTRO la ISO: con proprietario uid 1000 la live e
    # rotta - sudo si rifiuta di partire (sudo is owned by uid 1000, should be 0)
    # e apt fallisce con open (13: Permission denied) perche l'utente _apt non
    # puo scrivere nelle directory di cache. Qui si cambia solo il primo livello,
    # cosi restano rimovibili senza sudo.
    chown -R \"\${HOST_UID}:\${HOST_GID}\" .build config dist 2>/dev/null || true
    chown \"\${HOST_UID}:\${HOST_GID}\" chroot cache binary 2>/dev/null || true
    chown \"\${HOST_UID}:\${HOST_GID}\" ./*.iso 2>/dev/null || true
  " 2>&1 | tee build.log
RC=${PIPESTATUS[0]}
set -e

# --- Diagnosi in caso di fallimento -----------------------------------------
if [ "$RC" -ne 0 ]; then
  # anche una build fallita lascia chroot/, config/ ecc. di proprietà di root:
  # li restituiamo all'utente, altrimenti git e le build successive si bloccano
  # Ricorsivo solo dove serve a git; per chroot/ cache/ binary/ solo il primo
  # livello (i file interni devono restare di root: vedi sopra).
  for _d in .build config dist; do
    [ -e "$_d" ] || continue
    ${SUDO} chown -R "$HOST_UID:$HOST_GID" "$_d" 2>/dev/null || true
  done
  for _d in chroot cache binary; do
    [ -e "$_d" ] || continue
    ${SUDO} chown "$HOST_UID:$HOST_GID" "$_d" 2>/dev/null || true
  done
  # nessun lock deve sopravvivere a una build fallita
  ${SUDO} rm -f .lock 2>/dev/null || rm -f .lock 2>/dev/null || true

  # Lo stadio "binary" (squashfs + ISO + debian-installer) è quello che più
  # spesso resta a metà: un binary/ parziale fa fallire la build successiva con
  #   ln: failed to create symbolic link 'binary/dists/testing/trixie': File exists
  # Rimuoverlo costa pochi minuti e ZERO download del chroot: chroot/ e cache/
  # restano intatti e i suoi stage file vengono azzerati, così viene rifatto.
  echo "    Rimuovo binary/ e i suoi file di stage (la prossima build lo rifà)" >&2
  ${SUDO} rm -rf binary 2>/dev/null || rm -rf binary 2>/dev/null || true
  find .build -maxdepth 1 -name '*binary*' -delete 2>/dev/null || true

  echo
  echo "ERRORE: build fallita (exit $RC). Log completo salvato in: build.log" >&2
  echo "--- ultime 30 righe di build.log ---" >&2
  tail -n 30 build.log >&2 || true
  echo >&2
  cat >&2 <<'HINT'
Rimedi rapidi (in ordine di frequenza):
  grep -n 'Y/n\|Abort\|unexpected failure' build.log
      -> apt ha chiesto conferma: manca --yes in --apt-options (auto/config).
  grep -n 'Temporary failure resolving' build.log
      -> rete/DNS del container: ./build-docker.sh --net-host
  grep -n 'Unable to locate package' build.log
      -> nome pacchetto errato: ./check-packages.sh
  grep -n 'Unable to correct problems\|is in a very bad inconsistent state\|dpkg was interrupted' build.log
      -> stato sporco: sudo rm -rf chroot binary cache .build && ./build-docker.sh --clean
HINT
  echo >&2
  echo "Suggerimento: ./build-docker.sh --clean   (riparte da zero, riscarica ~1,5 GB)" >&2
  exit "$RC"
fi

echo
if [ -f zinimalos-amd64.hybrid.iso ]; then
  echo "==> OK: zinimalos-amd64.hybrid.iso ($(du -h zinimalos-amd64.hybrid.iso | cut -f1))"
else
  echo "ERRORE: ISO non generata (vedi output sopra)." >&2
  exit 1
fi
