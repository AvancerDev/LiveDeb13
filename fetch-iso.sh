#!/usr/bin/env bash
# fetch-iso.sh — Scarica l'ISO prodotta dalla CI con resume automatico.
#
# Perche' esiste: `gh run download` scarica l'artifact (~1.5 GB) in un colpo
# solo e non riprende; su linee instabili fallisce con
#   error writing zip archive: read: connection reset by peer
# Questo script usa `curl -C -`, quindi riparte da dove si era interrotto.
#
# Uso:
#   ./fetch-iso.sh                 # ultima run verde del repo, ISO nella cwd
#   ./fetch-iso.sh 45041861620     # run specifica
#   ./fetch-iso.sh 45041861620 ~/Downloads
#   REPO=AvancerDev/LiveDeb13 ATTEMPTS=50 ./fetch-iso.sh
#
# Richiede: gh (autenticato con `gh auth login`), curl, unzip.

set -euo pipefail

REPO="${REPO:-AvancerDev/LiveDeb13}"
RUN_ID="${1:-}"
OUT_DIR="${2:-$PWD}"
ATTEMPTS="${ATTEMPTS:-40}"      # tentativi di ripresa
SLEEP="${SLEEP:-5}"             # attesa fra i tentativi (secondi)

info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31mERRORE:\033[0m %s\n' "$*" >&2; exit 1; }

command -v gh    >/dev/null || die "gh non installato (sudo apt install gh)"
command -v curl  >/dev/null || die "curl non installato (sudo apt install curl)"
command -v unzip >/dev/null || die "unzip non installato (sudo apt install unzip)"

gh auth status >/dev/null 2>&1 || die "non sei autenticato su GitHub: esegui 'gh auth login'"

# --- 1. Individua la run -----------------------------------------------------
if [ -z "$RUN_ID" ]; then
  info "Cerco l'ultima run completata con successo di $REPO…"
  RUN_ID=$(gh run list -R "$REPO" --status success --limit 1 \
             --json databaseId --jq '.[0].databaseId' 2>/dev/null || true)
  [ -n "$RUN_ID" ] && [ "$RUN_ID" != "null" ] || die "nessuna run verde trovata: passa un RUN_ID esplicito"
fi
info "Run: $RUN_ID"

# --- 2. Individua l'artifact ISO ---------------------------------------------
read -r ART_ID ART_NAME ART_SIZE < <(
  gh api "repos/$REPO/actions/runs/$RUN_ID/artifacts" \
    --jq '.artifacts[]
          | select(.name | startswith("livedeb13-amd64"))
          | "\(.id) \(.name) \(.size_in_bytes)"' | head -1
) || true

[ -n "${ART_ID:-}" ] || die "nessun artifact 'livedeb13-amd64-*' nella run $RUN_ID (build fallita?)"
info "Artifact: $ART_NAME ($(numfmt --to=iec "$ART_SIZE" 2>/dev/null || echo "$ART_SIZE" B))"

mkdir -p "$OUT_DIR"
ZIP="$OUT_DIR/$ART_NAME.zip"
PARTIAL_SIZE=$(stat -c%s "$ZIP" 2>/dev/null || echo 0)
[ "$PARTIAL_SIZE" -gt 0 ] && info "Riprendo da $(numfmt --to=iec "$PARTIAL_SIZE" 2>/dev/null || echo "$PARTIAL_SIZE") già scaricati"

# --- 3. Scarica con resume ---------------------------------------------------
TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
[ -n "$TOKEN" ] || TOKEN=$(gh auth token)

URL="https://api.github.com/repos/$REPO/actions/artifacts/$ART_ID/zip"

# --retry-all-errors esiste da curl 7.71: su curl più vecchi lo si omette
CURL_OPTS=(-fL -C - --retry 5 --retry-delay 5 --connect-timeout 30)
if curl --help all 2>/dev/null | grep -q -- '--retry-all-errors'; then
  CURL_OPTS+=(--retry-all-errors)
fi

i=0
while [ "$i" -lt "$ATTEMPTS" ]; do
  i=$((i + 1))
  info "Tentativo $i/$ATTEMPTS…"
  # -C - : riprende; --retry: gestisce errori transitori dentro il tentativo
  if curl "${CURL_OPTS[@]}" \
        -H "Authorization: token $TOKEN" \
        -o "$ZIP" "$URL"; then
    break
  else
    rc=$?
    # 33 = server non supporta il resume: ricomincia da zero
    if [ "$rc" -eq 33 ]; then
      warn "Il server non supporta la ripresa: riparto da zero"
      rm -f "$ZIP"
    else
      warn "Download interrotto (curl exit $rc)"
    fi
    [ "$i" -lt "$ATTEMPTS" ] && sleep "$SLEEP"
  fi
done

GOT=$(stat -c%s "$ZIP" 2>/dev/null || echo 0)
if [ "$GOT" -lt "$ART_SIZE" ]; then
  die "download incompleto: $GOT/$ART_SIZE byte. Rilancia lo stesso comando per riprendere."
fi

# --- 4. Verifica ed estrai ---------------------------------------------------
info "Verifico l'archivio…"
unzip -t "$ZIP" >/dev/null || { rm -f "$ZIP"; die "archivio corrotto (rimosso): rilancia lo script"; }

info "Estraggo in $OUT_DIR…"
unzip -o -q "$ZIP" -d "$OUT_DIR"
rm -f "$ZIP"

ISO=$(ls -1t "$OUT_DIR"/*.iso 2>/dev/null | head -1 || true)
[ -n "$ISO" ] || die "nessun .iso estratto dall'artifact"

info "ISO pronta: $ISO"
ls -lh "$ISO"
sha256sum "$ISO"
echo
info "Avvio di prova: qemu-system-x86_64 -m 2048 -cdrom \"$ISO\""
