#!/bin/sh
# ZinimalOS — costruisce il pacchetto .deb del branding.
#
# Cosa fa:
#   1. prende i file da branding/rootfs/ (logo, /etc/issue, MOTD, config
#      fastfetch, script made / made by / zinimalos-info, chiave apt);
#   2. genera DEBIAN/ (control, conffiles, md5sums);
#   3. crea dist/zinimalos-branding_<versione>_all.deb;
#   4. copia il .deb in config/includes.chroot/opt/zinimalos/packages/, dove
#      l'hook 0400-install-branding-deb.hook.chroot lo installa nel chroot:
#      l'ISO contiene così lo stessO identico .deb che scaricano le altre
#      macchine con `apt upgrade`.
#
# Uso:
#   ./packaging/build-deb.sh                 # versione automatica (data/ora)
#   VERSION=1.0.3 ./packaging/build-deb.sh   # versione imposta a mano
#
# Non serve fakeroot: si usa `dpkg-deb --root-owner-group` (dpkg ≥ 1.19).
# L'ultima riga su stdout è il percorso del .deb.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

PAYLOAD="branding/rootfs"
PKG="zinimalos-branding"
OUT="${OUT:-$ROOT/dist}"
ISO_DEB_DIR="$ROOT/config/includes.chroot/opt/zinimalos/packages"

say() { printf '%s\n' "$*" >&2; }
die() { printf 'ERRORE: %s\n' "$*" >&2; exit 1; }

command -v dpkg-deb >/dev/null 2>&1 || die "dpkg-deb non trovato (pacchetto dpkg)."
[ -d "$PAYLOAD" ] || die "manca $PAYLOAD (payload del pacchetto)."

# --- Versione ----------------------------------------------------------------
# Base: ZINIMALOS_VERSION di /etc/zinimalos-release, più data/ora UTC.
# Esempio: 1.0.202611221845 → apt la vede sempre come più nuova.
if [ -z "${VERSION:-}" ]; then
  BASE="$(sed -n 's/^ZINIMALOS_VERSION="\(.*\)"$/\1/p' "$PAYLOAD/etc/zinimalos-release" 2>/dev/null | head -1)"
  [ -n "$BASE" ] || BASE="1.0"
  VERSION="${BASE}.$(date -u +%Y%m%d%H%M)"
fi
case "$VERSION" in
  *[!0-9.]*) die "versione non valida: $VERSION (solo cifre e punti)" ;;
esac

# --- Staging -----------------------------------------------------------------
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT INT TERM

cp -a "$PAYLOAD"/. "$STAGE"/
rm -rf "$STAGE/opt"

# Script eseguibili e permessi coerenti
chmod 0755 "$STAGE"/usr/local/bin/* 2>/dev/null || true
chmod 0755 "$STAGE"/usr/libexec/zinimalos/* 2>/dev/null || true
find "$STAGE" -name '*.gpg' -exec chmod 0644 {} + 2>/dev/null || true
find "$STAGE" -type d -exec chmod 0755 {} +
find "$STAGE" -type f ! -path "$STAGE/usr/local/bin/*" ! -path "$STAGE/usr/libexec/*" \
    -exec chmod 0644 {} + 2>/dev/null || true
chmod 0755 "$STAGE"/usr/local/bin/* "$STAGE"/usr/libexec/zinimalos/* 2>/dev/null || true

# Guardia anti-regressione: questi file appartengono a pacchetti Debian
# (base-files) e non possono stare nel nostro pacchetto, altrimenti dpkg
# rifiuta l'installazione con "trying to overwrite '/etc/issue'".
for _f in etc/issue etc/issue.net etc/motd etc/hostname etc/hosts; do
  if [ -e "$STAGE/$_f" ]; then
    die "$PAYLOAD/$_f non può stare nel pacchetto: appartiene a base-files." \
        "Mettilo in $PAYLOAD/usr/share/zinimalos/ e applicalo dal postinst."
  fi
done

# Guardia anti-regressione: nessuna fonte apt ATTIVA nel pacchetto. Se il
# repository ZinimalOS non è raggiungibile, l'`apt update` che live-build esegue
# alla fine dello stadio chroot fallirebbe e la build si fermerebbe. La riga vive
# come template e viene attivata sulla macchina installata (repo-enable).
if [ -n "$(find "$STAGE/etc/apt/sources.list.d" -name '*.sources' -o -name '*.list' 2>/dev/null | head -1)" ]; then
  die "in etc/apt/sources.list.d/ c'è una fonte apt attiva: durante la build" \
      "live-build esegue 'apt update' e un repo non raggiungibile fa fallire tutto." \
      "Metti la riga in $PAYLOAD/usr/share/zinimalos/zinimalos.sources (template)."
fi

# Se la chiave pubblica non c'è ancora (setup-gpg.sh non eseguito), il
# pacchetto non deve installare un repository che apt non saprebbe verificare.
if [ ! -s "$STAGE/etc/apt/keyrings/zinimalos.gpg" ]; then
  say "NOTA: chiave pubblica assente → il pacchetto NON include il repository apt."
  say "      Esegui ./packaging/setup-gpg.sh per attivare gli aggiornamenti via apt."
  rm -f "$STAGE/usr/share/zinimalos/zinimalos.sources"
  rm -f "$STAGE/lib/systemd/system/zinimalos-repo.service"
  rm -f "$STAGE/usr/libexec/zinimalos/repo-enable"
fi

# --- DEBIAN/ -----------------------------------------------------------------
mkdir -p "$STAGE/DEBIAN"

# Script di manutenzione: /etc/issue e /etc/motd NON sono nel pacchetto (sono di
# base-files, dpkg rifiuterebbe la sovrascrittura): il postinst copia i template
# da /usr/share/zinimalos/. Vedi packaging/zinimalos-branding/postinst.
for _s in postinst postrm; do
  if [ -f "packaging/zinimalos-branding/$_s" ]; then
    cp "packaging/zinimalos-branding/$_s" "$STAGE/DEBIAN/$_s"
    chmod 0755 "$STAGE/DEBIAN/$_s"
  fi
done
INSTALLED_SIZE=$(du -sk "$STAGE" | cut -f1)
sed -e "s|@PKG@|$PKG|g" \
    -e "s|@VERSION@|$VERSION|g" \
    -e "s|@INSTALLED_SIZE@|$INSTALLED_SIZE|g" \
    packaging/zinimalos-branding/control.in > "$STAGE/DEBIAN/control"

# conffile: file che l'utente può modificare e che dpkg non sovrascrive senza
# chiedere. /etc/issue e /etc/motd sono esclusi di proposito (appartengono a
# base-files): li gestisce il postinst.
: > "$STAGE/DEBIAN/conffiles"
for f in /etc/zinimalos-release /etc/fastfetch/config.jsonc; do
  [ -f "$STAGE$f" ] && printf '%s\n' "$f" >> "$STAGE/DEBIAN/conffiles"
done

( cd "$STAGE" && find . -path ./DEBIAN -prune -o -type f -print \
    | sed 's|^\./||' | LC_ALL=C sort | xargs -r md5sum > DEBIAN/md5sums )
chmod 0644 "$STAGE/DEBIAN/control" "$STAGE/DEBIAN/conffiles" "$STAGE/DEBIAN/md5sums"

# --- Build -------------------------------------------------------------------
mkdir -p "$OUT"
DEB="$OUT/${PKG}_${VERSION}_all.deb"
dpkg-deb --root-owner-group -Zxz --build "$STAGE" "$DEB" >/dev/null

# --- Copia nella ISO ---------------------------------------------------------
# Nome FISSO (senza versione) di proposito: live-build copia
# config/includes.chroot/ nel chroot ma non cancella mai i file rimossi, quindi
# con un nome versionato le build successive accumulavano più .deb e l'hook
# poteva installare quello vecchio (bug: "trying to overwrite '/etc/issue'").
rm -rf "$ISO_DEB_DIR"
mkdir -p "$ISO_DEB_DIR"
cp "$DEB" "$ISO_DEB_DIR/zinimalos-branding.deb"

say "==> Pacchetto: ${DEB#$ROOT/}"
say "    versione $VERSION, $(du -h "$DEB" | cut -f1), $(du -sk "$STAGE" | cut -f1) KB installati"
say "    copiato in ${ISO_DEB_DIR#$ROOT/}/"

printf '%s\n' "$DEB"
