#!/bin/sh
# ZinimalOS — crea la chiave GPG con cui viene firmato il repository apt.
#
# Da eseguire UNA VOLTA sulla tua macchina (la chiave privata resta lì, mai nel
# repository: nel repo finisce solo la chiave pubblica, dentro il pacchetto).
#
# Cosa fa:
#   1. genera una chiave RSA 4096 (solo firma) con identità "ZinimalOS Archive";
#   2. esporta la chiave pubblica in
#      branding/rootfs/etc/apt/keyrings/zinimalos.gpg  (finisce nell'ISO);
#   3. salva l'ID della chiave in packaging/gpg-keyid (file locale, ignorato da git).
#
# Uso:
#   ./packaging/setup-gpg.sh                     # crea la chiave
#   ./packaging/setup-gpg.sh --show              # mostra l'ID già configurato
#   KEYID=ABCD1234 ./packaging/setup-gpg.sh      # usa una chiave esistente
#
# IMPORTANTE: fai un backup della chiave privata. Se la perdi, tutte le macchine
# ZinimalOS dovranno ri-trovare la fiducia nel repository a mano.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

KEYRING_DIR="branding/rootfs/etc/apt/keyrings"
KEYRING="$KEYRING_DIR/zinimalos.gpg"
KEYID_FILE="packaging/gpg-keyid"
IDENTITY="${IDENTITY:-ZinimalOS Archive <avancerdev@users.noreply.github.com>}"

say() { printf '%s\n' "$*" >&2; }
die() { printf 'ERRORE: %s\n' "$*" >&2; exit 1; }

command -v gpg >/dev/null 2>&1 || die "gpg non installato: sudo apt install gnupg"

export_key() {
  mkdir -p "$KEYRING_DIR"
  gpg --batch --yes --export "$1" > "$KEYRING"
  [ -s "$KEYRING" ] || die "esportazione della chiave $1 fallita"
  chmod 0644 "$KEYRING"
  printf '%s\n' "$1" > "$KEYID_FILE"
  say "==> Chiave pubblica: $KEYRING"
  say "    ID chiave: $1  (salvato in $KEYID_FILE)"
  say ""
  say "Backup della chiave privata (conservalo fuori dal repo):"
  say "  gpg --export-secret-keys --armor $1 > zinimalos-archive-secret.asc"
}

case "${1:-}" in
  --show)
    [ -f "$KEYID_FILE" ] || die "nessuna chiave configurata (esegui senza argomenti)"
    cat "$KEYID_FILE"
    exit 0
    ;;
  -h|--help)
    sed -n '2,25p' "$0"
    exit 0
    ;;
esac

if [ -n "${KEYID:-}" ]; then
  say "==> Uso la chiave indicata: $KEYID"
  export_key "$KEYID"
  exit 0
fi

if [ -f "$KEYID_FILE" ]; then
  say "==> Chiave già configurata: $(cat "$KEYID_FILE")"
  say "    (per rigenerarla: rm $KEYID_FILE e riesegui)"
  export_key "$(cat "$KEYID_FILE")"
  exit 0
fi

say "==> Genero la chiave GPG per il repository ZinimalOS"
say "    Identità: $IDENTITY"
say "    Ti verrà chiesta una passphrase: serve per firmare (reprepro)."
say ""

gpg --batch --quick-generate-key "$IDENTITY" rsa4096 sign 5y
KEYID=$(gpg --list-keys --with-colons "$IDENTITY" \
        | awk -F: '/^fpr:/ {print $10; exit}')
[ -n "${KEYID:-}" ] || die "impossibile determinare l'ID della chiave"

export_key "$KEYID"
say ""
say "Fatto. Prossimi passi:"
say "  1) ./packaging/publish-repo.sh    # crea il .deb e pubblica il repository"
say "  2) ./build-docker.sh              # la nuova ISO contiene il pacchetto"
