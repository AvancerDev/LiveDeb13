#!/bin/bash
# ZinimalOS — pubblica gli aggiornamenti nel repository apt (reprepro).
#
# Cosa fa, in ordine:
#   1. costruisce il .deb aggiornato (packaging/build-deb.sh);
#   2. lo inserisce nel repository locale repo/ (reprepro includedeb);
#   3. firma e rigenera gli indici (reprepro export);
#   4. copia dists/ e pool/ nel branch gh-pages del repository GitHub
#      dedicato (default: AvancerDev/zinimalos-repo), da cui apt scarica.
#
# Uso:
#   ./packaging/publish-repo.sh                # build + pubblica su GitHub Pages
#   ./packaging/publish-repo.sh --no-publish   # solo repo locale in repo/
#   GH_REPO=utente/altro-repo ./packaging/publish-repo.sh
#
# Requisiti: reprepro, gnupg, git (e gh per creare il repository la prima volta).
# La chiave privata GPG resta sulla tua macchina: qui viene solo usata per firmare.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

REPO_DIR="${REPO_DIR:-$ROOT/repo}"
GH_REPO="${GH_REPO:-AvancerDev/zinimalos-repo}"
BRANCH="gh-pages"
CODENAME="trixie"
PUBLISH=1

for arg in "$@"; do
  case "$arg" in
    --no-publish) PUBLISH=0 ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "Argomento sconosciuto: $arg" >&2; exit 1 ;;
  esac
done

say() { printf '%s\n' "$*" >&2; }
die() { printf 'ERRORE: %s\n' "$*" >&2; exit 1; }

command -v reprepro >/dev/null 2>&1 || die "manca reprepro: sudo apt install reprepro"
command -v gpg >/dev/null 2>&1 || die "manca gpg: sudo apt install gnupg"

KEYID="${ZINIMALOS_GPG_KEY:-$(cat packaging/gpg-keyid 2>/dev/null || true)}"
if [ -z "$KEYID" ]; then
  die "nessuna chiave configurata: esegui prima ./packaging/setup-gpg.sh"
fi

say "==> 1/4 Costruisco il pacchetto"
DEB=$(./packaging/build-deb.sh | tail -1)
[ -f "$DEB" ] || die "il pacchetto non è stato creato ($DEB)"

say "==> 2/4 Inserisco nel repository locale ($REPO_DIR)"
mkdir -p "$REPO_DIR/conf"
sed "s|@KEY@|$KEYID|" packaging/repo/conf/distributions.in > "$REPO_DIR/conf/distributions"
cp packaging/repo/conf/options "$REPO_DIR/conf/options"

# Firma: usa l'agente gpg. Al primo uso la passphrase viene chiesta una volta
# e resta in cache (gpg-agent); per disattivare la cache: gpgconf --kill gpg-agent
reprepro --basedir "$REPO_DIR" includedeb "$CODENAME" "$DEB"

say "==> 3/4 Rigeno e firmo gli indici"
reprepro --basedir "$REPO_DIR" export

if [ "$PUBLISH" = "0" ]; then
  say "Repository locale pronto in ${REPO_DIR#$ROOT/}/ (pubblicazione saltata)."
  say "Prova locale:"
  say "  (cd ${REPO_DIR#$ROOT/} && python3 -m http.server 8000)"
  say "  deb [signed-by=/etc/apt/keyrings/zinimalos.gpg] http://127.0.0.1:8000 trixie main"
  exit 0
fi

say "==> 4/4 Pubblico su GitHub Pages ($GH_REPO, branch $BRANCH)"
URL="https://github.com/$GH_REPO"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

if git ls-remote --exit-code "$URL" >/dev/null 2>&1; then
  if ! git clone --depth 1 --branch "$BRANCH" "$URL" "$TMP" 2>/dev/null; then
    say "    branch $BRANCH assente: lo creo"
    git clone "$URL" "$TMP"
    git -C "$TMP" checkout --orphan "$BRANCH"
    git -C "$TMP" rm -rf . >/dev/null 2>&1 || true
  fi
else
  say "    il repository $GH_REPO non esiste: lo creo"
  command -v gh >/dev/null 2>&1 || die "serve gh per creare il repository (oppure crealo a mano)"
  gh repo create "$GH_REPO" --public \
     --description "Repository apt firmato di ZinimalOS" >/dev/null
  git init -q "$TMP"
  git -C "$TMP" checkout -q --orphan "$BRANCH"
fi

# Sostituisce il contenuto (tranne .git) con dists/ + pool/ aggiornati
find "$TMP" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp -a "$REPO_DIR/dists" "$REPO_DIR/pool" "$TMP"/
: > "$TMP/.nojekyll"
cat > "$TMP/README.md" <<EOF
# ZinimalOS — repository apt

Repository firmato degli aggiornamenti di ZinimalOS (pacchetto \`zinimalos-branding\`).

\`\`\`
Types: deb
URIs: https://$(printf '%s' "$GH_REPO" | tr '[:upper:]' '[:lower:]' | cut -d/ -f1).github.io/$(printf '%s' "$GH_REPO" | cut -d/ -f2)/
Suites: trixie
Components: main
Signed-By: /etc/apt/keyrings/zinimalos.gpg
\`\`\`

Generato con reprepro. Non modificare a mano: usare \`make publish\` nel
repository \`ZinimalOS\`.
EOF

if git -C "$TMP" add -A && ! git -C "$TMP" diff --cached --quiet; then
  git -C "$TMP" -c user.name="ZinimalOS" -c user.email="noreply@zinimalos.local" \
      commit -q -m "repo: zinimalos-branding $(basename "$DEB" .deb | sed 's/.*_//')"
  git -C "$TMP" push -q origin "HEAD:$BRANCH"
  say "    pubblicato."
else
  say "    nessuna modifica da pubblicare."
fi

# Attiva GitHub Pages (idempotente: se già attivo, l'errore viene ignorato)
if command -v gh >/dev/null 2>&1; then
  gh api -X POST "repos/$GH_REPO/pages" \
     -f 'source[branch]='$BRANCH -f 'source[path]=/' >/dev/null 2>&1 \
  || gh api -X PUT "repos/$GH_REPO/pages" \
     -f 'source[branch]='$BRANCH -f 'source[path]=/' >/dev/null 2>&1 \
  || say "    (GitHub Pages va attivato a mano: Settings → Pages → branch $BRANCH)"
fi

say ""
say "Fatto. Sulle macchine ZinimalOS:"
say "  sudo apt update && sudo apt upgrade"
