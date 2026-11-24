#!/bin/bash
# ZinimalOS — pubblica gli aggiornamenti nel repository apt (reprepro).
#
# Cosa fa, in ordine:
#   1. costruisce il .deb aggiornato (packaging/build-deb.sh);
#   2. lo inserisce nel repository locale repo/ (reprepro includedeb);
#   3. firma e rigenera gli indici (reprepro export);
#   4. copia dists/ e pool/ nel branch gh-pages del repository GitHub
#      dedicato (default: AvancerDev/zinimalos-repo), da cui apt scarica;
#   5. attiva GitHub Pages su quel branch, se non è già attivo.
#
# Uso:
#   ./packaging/publish-repo.sh                # build + pubblica su GitHub Pages
#   ./packaging/publish-repo.sh --no-publish   # solo repo locale in repo/
#   GH_REPO=utente/altro-repo ./packaging/publish-repo.sh
#   GH_REMOTE=/percorso/repo.git ./packaging/publish-repo.sh   # (test: remoto locale)
#
# Requisiti: reprepro, gnupg, git (e gh per attivare Pages / creare il repo).
# La chiave privata GPG resta sulla tua macchina: qui viene solo usata per firmare.
#
# Funziona anche sul repository appena creato e VUOTO: in quel caso crea il
# branch gh-pages da zero.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

REPO_DIR="${REPO_DIR:-$ROOT/repo}"
GH_REPO="${GH_REPO:-AvancerDev/zinimalos-repo}"
GH_REMOTE="${GH_REMOTE:-https://github.com/$GH_REPO}"
SKIP_PAGES="${ZINIMALOS_SKIP_PAGES:-0}"
BRANCH="gh-pages"
CODENAME="trixie"
PUBLISH=1

for arg in "$@"; do
  case "$arg" in
    --no-publish) PUBLISH=0 ;;
    -h|--help) sed -n '2,29p' "$0"; exit 0 ;;
    *) echo "Argomento sconosciuto: $arg" >&2; exit 1 ;;
  esac
done

say()  { printf '%s\n' "$*" >&2; }
die()  { printf 'ERRORE: %s\n' "$*" >&2; exit 1; }

command -v reprepro >/dev/null 2>&1 || die "manca reprepro: sudo apt install reprepro"
command -v gpg      >/dev/null 2>&1 || die "manca gpg: sudo apt install gnupg"

KEYID="${ZINIMALOS_GPG_KEY:-$(cat packaging/gpg-keyid 2>/dev/null || true)}"
if [ -z "$KEYID" ]; then
  die "nessuna chiave configurata: esegui prima ./packaging/setup-gpg.sh"
fi

# --- 1/4 pacchetto -----------------------------------------------------------
say "==> 1/4 Costruisco il pacchetto"
DEB=$(./packaging/build-deb.sh | tail -1)
[ -f "$DEB" ] || die "il pacchetto non è stato creato ($DEB)"
say "    $(basename "$DEB")"

# --- 2/4 inserimento nel repo locale ----------------------------------------
say "==> 2/4 Inserisco nel repository locale (${REPO_DIR#$ROOT/})"
mkdir -p "$REPO_DIR/conf"
sed "s|@KEY@|$KEYID|" packaging/repo/conf/distributions.in > "$REPO_DIR/conf/distributions"
cp packaging/repo/conf/options "$REPO_DIR/conf/options"

# Firma: usa l'agente gpg. Al primo uso la passphrase viene chiesta una volta e
# resta in cache (gpgconf --kill gpg-agent per azzerarla).
reprepro --basedir "$REPO_DIR" includedeb "$CODENAME" "$DEB"

# --- 3/4 indici firmati ------------------------------------------------------
say "==> 3/4 Rigenero e firmo gli indici"
reprepro --basedir "$REPO_DIR" export
[ -f "$REPO_DIR/dists/$CODENAME/Release" ]    || die "manca dists/$CODENAME/Release"
[ -f "$REPO_DIR/dists/$CODENAME/InRelease" ]  || die "manca dists/$CODENAME/InRelease (firma fallita?)"

if [ "$PUBLISH" = "0" ]; then
  say "Repository locale pronto in ${REPO_DIR#$ROOT/}/ (pubblicazione saltata)."
  say "Prova locale:"
  say "  (cd ${REPO_DIR#$ROOT/} && python3 -m http.server 8000)"
  exit 0
fi

# --- 4/4 pubblicazione su gh-pages ------------------------------------------
say "==> 4/4 Pubblico su GitHub Pages ($GH_REMOTE, branch $BRANCH)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

# NOTA: senza --exit-code, `git ls-remote` esce 0 anche su un repository
# esistente ma ancora VUOTO (zero ref) — è il caso della prima pubblicazione.
have_remote=0
if git ls-remote "$GH_REMOTE" >/dev/null 2>&1; then
  have_remote=1
fi

if [ "$have_remote" = "1" ]; then
  if git clone --quiet --depth 1 --branch "$BRANCH" "$GH_REMOTE" "$TMP" 2>/dev/null; then
    say "    branch $BRANCH trovato: aggiorno"
  else
    # Repository vuoto o senza branch gh-pages (prima pubblicazione)
    say "    branch $BRANCH assente: lo creo (prima pubblicazione)"
    rm -rf "$TMP"; mkdir -p "$TMP"
    git -C "$TMP" init -q
    git -C "$TMP" remote add origin "$GH_REMOTE"
    git -C "$TMP" checkout -q --orphan "$BRANCH"
  fi
else
  say "    il remoto non esiste: creo il repository con gh"
  command -v gh >/dev/null 2>&1 || die "serve gh per creare il repository (oppure crealo a mano)"
  gh repo create "$GH_REPO" --public \
     --description "Repository apt firmato di ZinimalOS" >/dev/null
  mkdir -p "$TMP"
  git -C "$TMP" init -q
  git -C "$TMP" remote add origin "$GH_REMOTE"
  git -C "$TMP" checkout -q --orphan "$BRANCH"
fi

# Contenuto = dists/ + pool/ aggiornati + .nojekyll (senza Jekyll)
find "$TMP" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp -a "$REPO_DIR/dists" "$REPO_DIR/pool" "$TMP"/
: > "$TMP/.nojekyll"
PAGES_URL=""
case "$GH_REMOTE" in
  https://github.com/*)
    _rest="${GH_REMOTE#https://github.com/}"
    _rest="${_rest%.git}"
    _owner="${_rest%%/*}"
    _repo="${_rest#*/}"
    # GitHub Pages serve <owner>.github.io/<repo> (host in minuscolo)
    PAGES_URL="$(printf '%s' "$_owner" | tr '[:upper:]' '[:lower:]').github.io/${_repo}"
    ;;
esac
[ -n "$PAGES_URL" ] || PAGES_URL="<utente>.github.io/<repo>"

cat > "$TMP/README.md" <<EOF
# ZinimalOS — repository apt

Repository **firmato** degli aggiornamenti di ZinimalOS (pacchetto
\`zinimalos-branding\`), generato con reprepro.

Sulle macchine ZinimalOS installate non serve configurarlo a mano: la riga apt
è in \`/usr/share/zinimalos/zinimalos.sources\` e viene attivata
automaticamente (\`zinimalos-repo.service\`) appena questo repository risponde.

\`\`\`
Types: deb
URIs: https://$PAGES_URL/
Suites: trixie
Components: main
Signed-By: /etc/apt/keyrings/zinimalos.gpg
\`\`\`

Non modificare a mano: usare \`make publish\` nel repository \`ZinimalOS\`.
EOF

git -C "$TMP" add -A
if git -C "$TMP" diff --cached --quiet; then
  say "    nessuna modifica da pubblicare."
else
  DEBVER="$(dpkg-deb -f "$DEB" Version 2>/dev/null || basename "$DEB" .deb)"
  git -C "$TMP" -c user.name="ZinimalOS" -c user.email="noreply@zinimalos.local" \
      commit -q -m "repo: zinimalos-branding $DEBVER"
  git -C "$TMP" push -q origin "HEAD:$BRANCH"
  say "    pubblicato: zinimalos-branding $DEBVER"
fi

# --- GitHub Pages ------------------------------------------------------------
if [ "$SKIP_PAGES" = "1" ]; then
  say "    (attivazione Pages saltata: ZINIMALOS_SKIP_PAGES=1)"
elif command -v gh >/dev/null 2>&1 && printf '%s' "$GH_REPO" | grep -q '/'; then
  PAGES_JSON='{"source":{"branch":"'"$BRANCH"'","path":"/"}}'
  if gh api "repos/$GH_REPO/pages" >/dev/null 2>&1; then
    say "    GitHub Pages già attivo."
  elif printf '%s' "$PAGES_JSON" | gh api -X POST "repos/$GH_REPO/pages" --input - >/dev/null 2>&1 \
    || printf '%s' "$PAGES_JSON" | gh api -X PUT "repos/$GH_REPO/pages" --input - >/dev/null 2>&1; then
    say "    GitHub Pages attivato su $BRANCH (prima build: ~1 minuto)."
  else
    say "    ATTENZIONE: attiva GitHub Pages a mano: Settings → Pages →"
    say "                 Source: Deploy from a branch → $BRANCH → / (root)"
  fi
fi

say ""
say "Fatto. Verifica (dopo ~1 minuto dal primo avvio di Pages):"
say "  curl -fsSL https://$PAGES_URL/dists/$CODENAME/Release | head -3"
say ""
say "Sulle macchine ZinimalOS:"
say "  sudo apt update && sudo apt upgrade"
