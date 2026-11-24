# Aggiornamenti di ZinimalOS (apt + reprepro)

Come far sì che una macchina con ZinimalOS **installato** aggiorni sia Debian sia
le personalizzazioni del progetto con un solo comando:

```bash
sudo apt update && sudo apt upgrade
```

> La **live** non si aggiorna: gira da un filesystem squashfs in sola lettura.
> Gli aggiornamenti riguardano le macchine installate su disco. Rifare l'ISO
> serve solo a distribuire un sistema già aggiornato "da zero".

---

## 1. Come funziona

```
branding/rootfs/            →  packaging/build-deb.sh  →  zinimalos-branding_<ver>_all.deb
  (logo, issue, motd,                                      │
   config fastfetch, script)                               ├─→ config/includes.chroot/opt/zinimalos/packages/
                                                           │     (installato nell'ISO dall'hook 0400)
                                                           └─→ repo/ (reprepro) → GitHub Pages
                                                                                        │
                                                                       sudo apt upgrade ─┘
```

Tre pezzi, ognuno con un compito:

| Pezzo | Comando | Cosa fa |
|---|---|---|
| packaging | `make deb` | trasforma `branding/rootfs/` in un pacchetto `.deb` |
| repository | `make publish` | inserisce il `.deb` in un repo apt firmato e lo pubblica |
| consumo | `sudo apt upgrade` | le macchine installate prendono il pacchetto nuovo |

`live-build` **non costruisce** i pacchetti: li installa. La costruzione la fa
`dpkg-deb` (dentro `packaging/build-deb.sh`), il repository lo gestisce
`reprepro`.

### Perché il pacchetto e non le copie di file

Prima logo, `/etc/issue`, MOTD e config di fastfetch venivano copiati dal
progetto nel chroot con `config/includes.chroot/`. Un file copiato **non
appartiene a nessun pacchetto**, quindi:

- nessun `apt upgrade` poteva aggiornarlo;
- cancellare un file dal progetto non lo rimuoveva dall'immagine (il vecchio
  banner che lanciava `fastfetch` è sopravvissuto per questo).

Ora quei file stanno in `branding/rootfs/` e viaggiano **dentro** il pacchetto:
dpkg li conosce, li aggiorna e li sostituisce.

---

## 2. Preparazione (una volta sola)

### 2.1 Firma: genera la chiave GPG

```bash
sudo apt install gnupg reprepro
./packaging/setup-gpg.sh
```

Crea una chiave RSA 4096 (identità `ZinimalOS Archive`) e salva la **pubblica**
in `branding/rootfs/etc/apt/keyrings/zinimalos.gpg` (finisce nell'ISO).
L'ID della chiave va in `packaging/gpg-keyid` (file locale, in `.gitignore`).

**Backup obbligatorio** della chiave privata, fuori dal repository:

```bash
gpg --export-secret-keys --armor "$(cat packaging/gpg-keyid)" > ~/zinimalos-archive-secret.asc
```

Se la perdi: le macchine non si fidano più del repo e va reinstallata la chiave
a mano su ognuna. La passphrase resta in cache nell'agente GPG durante la
sessione (`gpgconf --kill gpg-agent` per azzerarla).

### 2.2 Repository: crea il progetto su GitHub

Serve un repository **dedicato** per il repo apt, separato da quello dell'ISO:

- `packaging/publish-repo.sh` lo crea da sé con `gh` la prima volta
  (`AvancerDev/zinimalos-repo`, branch `gh-pages`), oppure crealo a mano su
  GitHub: nuovo repo pubblico, branch `gh-pages`, Settings → Pages → *Deploy
  from a branch* → `gh-pages` / `/ (root)`.
- L'URL finale è `https://avancerdev.github.io/zinimalos-repo/`; se cambi
  utente o nome, aggiorna `URIs:` in
  `branding/rootfs/etc/apt/sources.list.d/zinimalos.sources` (e `GH_REPO`).

Perché Pages: HTTPS gratis, nessun server da mantenere, apt funziona
normalmente (indici `Release`/`InRelease` firmati). Lo spazio occupato sono
poche decine di KB per release.

---

## 3. Ciclo di aggiornamento

```bash
# 1. modifichi quello che vuoi in branding/rootfs/ (logo, /etc/issue, MOTD, …)
# 2. costruisci e pubblichi
make publish          # = build-deb.sh + reprepro includedeb + export + push gh-pages

# 3. sulle macchine ZinimalOS installate
sudo apt update && sudo apt upgrade
```

`make publish` stampa la versione pubblicata, ad esempio
`1.0.202611221845`. La versione è `ZINIMALOS_VERSION` (in
`branding/rootfs/etc/zinimalos-release`) più data/ora UTC: apt la vede sempre
come più nuova della precedente, senza doverla inventare a mano.

Per una versione "ufficiale" (es. `1.1`) basta alzare `ZINIMALOS_VERSION` nel
file `zinimalos-release`: il numero entra nel nome del pacchetto.

### Cosa arriva sulle macchine

| Cambio | Effetto sulle macchine già installate |
|---|---|
| logo, `/etc/issue`, MOTD, config fastfetch | sostituiti dall'upgrade (salvo tuoi file modificati, vedi §4) |
| script `made`, `made-by`, `zinimalos-info` | sostituiti |
| nuovi pacchetti Debian, kernel, firmware | aggiornati da Debian (mirror ufficiale) |

### La ISO va rifatta?

Solo per distribuire un sistema nuovo già aggiornato. `auto/build` ricostruisce
il `.deb` e lo mette in `config/includes.chroot/opt/zinimalos/packages/`, che
l'hook `0400-install-branding-deb.hook.chroot` installa nel chroot: l'ISO
contiene **lo stesso identico pacchetto** pubblicato nel repo.

Se hai cambiato solo `branding/`, `auto/build` invalida gli stadi
`chroot`/`binary` da sé (vedi §3.1 di `docs/BUILD.md`) e la build costa ~5-10
minuti senza riscaricare pacchetti.

---

## 4. File di configurazione modificati a mano

`/etc/issue`, `/etc/motd`, `/etc/zinimalos-release` e
`/etc/fastfetch/config.jsonc` sono **conffile** di dpkg: se li modifichi, dpkg
lo sa. Per non bloccare mai un upgrade non interattivo, il pacchetto installa
`/etc/apt/apt.conf.d/90-zinimalos` con:

```
Dpkg::Options { "--force-confdef"; "--force-confold"; };
```

Quindi in caso di conflitto **vince la tua versione**: l'upgrade prosegue e il
logo ufficiale nuovo non viene applicato a quel file.

Per riallinearti alla versione ufficiale:

```bash
sudo apt install --reinstall zinimalos-branding
```

---

## 5. Macchine installate con una ISO vecchia (bootstrap una volta)

Se la macchina non ha ancora la riga apt di ZinimalOS (`ls
/etc/apt/sources.list.d/` non mostra `zinimalos.sources`), tre comandi:

```bash
sudo install -d -m 755 /etc/apt/keyrings
sudo curl -fsSL -o /etc/apt/keyrings/zinimalos.gpg \
  https://raw.githubusercontent.com/AvancerDev/ZinimalOS/main/branding/rootfs/etc/apt/keyrings/zinimalos.gpg
sudo tee /etc/apt/sources.list.d/zinimalos.sources >/dev/null <<'EOF'
Types: deb
URIs: https://avancerdev.github.io/zinimalos-repo/
Suites: trixie
Components: main
Architectures: amd64
Signed-By: /etc/apt/keyrings/zinimalos.gpg
EOF
sudo apt update && sudo apt install zinimalos-branding
```

Dalla successiva ISO in poi non serve: chiave e riga apt arrivano col pacchetto.

---

## 6. Diagnostica

| Sintomo | Causa / rimedio |
|---|---|
| `apt update` → `NO_PUBKEY` | keyring assente o diverso: reinstalla `zinimalos-branding` o rifai il §5 |
| `apt update` → `404` su `zinimalos-repo` | repository non ancora pubblicato / branch `gh-pages` vuoto: `make publish` |
| `apt update` → `Release ... is not signed` | `make publish` non ha firmato: controlla `packaging/gpg-keyid` e che `gpg --list-keys` la veda |
| `apt upgrade` dice "0 aggiornati" | versione già allineata: `apt policy zinimalos-branding` per vedere la candidata |
| `apt upgrade` chiede cosa fare di `/etc/issue` | manca `90-zinimalos` (pacchetto vecchio): `sudo apt install --reinstall zinimalos-branding` |
| `dpkg -L zinimalos-branding` | elenca i file posseduti dal pacchetto |

Verifiche utili:

```bash
apt policy zinimalos-branding          # installata vs candidata
apt changelog zinimalos-branding       # non disponibile: il changelog non è nel repo
dpkg -L zinimalos-branding | head      # cosa contiene il pacchetto
gpg --verify <(curl -fsSL https://avancerdev.github.io/zinimalos-repo/dists/trixie/InRelease)
```

---

## 7. Cosa NON è coperto (e perché)

- **Aggiornare il sistema live**: impossibile, è in sola lettura. Si rifà l'ISO.
- **Aggiornare il kernel della live**: idem.
- **Pacchetti Debian "pinnati"**: nessun pin, si usa il mirror ufficiale trixie.
- **Aggiornamenti automatici notturni**: volutamente assenti. Se li vuoi:
  `sudo apt install unattended-upgrades` e abilita
  `Unattended-Upgrade::Origins-Pattern` con `o=ZinimalOS`.

---

## 8. Riferimenti

- `packaging/build-deb.sh` — costruzione del `.deb`
- `packaging/setup-gpg.sh` — chiave di firma
- `packaging/publish-repo.sh` — reprepro + pubblicazione su GitHub Pages
- `config/hooks/normal/0400-install-branding-deb.hook.chroot` — installazione nell'ISO
- `branding/rootfs/etc/apt/` — riga apt, apt.conf.d, chiave pubblica
- `docs/BUILD.md` — build dell'ISO e stadi di live-build
