# Build & Test — LiveDeb13

## 1. Prerequisiti (Debian 13 trixie)

```bash
sudo apt update
sudo apt install -y live-build debootstrap squashfs-tools xorriso isolinux \
  syslinux-common grub-pc-bin grub-efi-amd64-bin mtools dosfstools \
  qemu-system-x86 ovmf
```

Verifica:

```bash
make check
lb --version     # deve essere la 1:20250505+deb13u1 (o successiva), NON 3.0~a57
```

> **Attenzione:** se `lb --version` risponde `3.0~a57` hai una live-build
> dell'epoca Debian 7/8, che **non** può costruire immagini Debian 13.
> Vedi §6.3.

## 2. Configurazione

```bash
make config
# equivale a: ./auto/config
```

Questo rigenera i file di configurazione di live-build a partire da
`auto/config`. `sudo make build` riesegue comunque sempre `auto/config`
(`auto/build` rimuove lo stage file `.build/config`), quindi le modifiche
alla configurazione sono sempre applicate.

**Compatibilità tra versioni di live-build:** `auto/config` interroga
`lb config --help` e passa solo le opzioni supportate dall'istanza installata;
le altre vengono saltate con un avviso del tipo:

```
ATTENZIONE: opzioni non supportate da questa versione di live-build, ignorate:
  --image-name
```

Se viene saltata `--image-name`, l'ISO prodotta da live-build si chiama
`live-image-amd64.hybrid.iso`: `auto/build` la rinomina comunque in
`livedeb13-amd64.hybrid.iso`.

## 3. Build

```bash
sudo make build
# equivale a: sudo ./auto/build
```

- Durata tipica: 10–30 minuti (dipende da rete/CPU).
- Output: `livedeb13-amd64.hybrid.iso` (nella radice del progetto)
- Log: `*.build.log` nella root del progetto.

Pulizia:

```bash
sudo make clean        # lb clean
sudo make distclean    # lb clean --purge (cancella anche la cache)
```

## 4. Test in VM

BIOS:

```bash
make run
```

UEFI (richiede `ovmf`):

```bash
make run-uefi
```

Test manuale con QEMU (esempio):

```bash
qemu-system-x86_64 -m 2048 -cdrom livedeb13-amd64.hybrid.iso -boot d -enable-kvm
```

## 5. Scrittura su USB

```bash
# ATTENZIONE: sostituisci /dev/sdX con la chiavetta corretta!
sudo dd if=livedeb13-amd64.hybrid.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

Oppure:

```bash
USB=/dev/sdX make usb
```

Verifica la chiavetta con `lsblk` prima di scrivere.

## 6. Troubleshooting

| Errore | Soluzione |
|---|---|
| `lb: command not found` | Installa `live-build` (vedi §1) |
| `debootstrap` fallisce / rete | Controlla la connessione e i mirror in `auto/config` |
| `xorriso` non trovato | Installa `xorriso` |
| ISO non si avvia in UEFI | Disattiva Secure Boot oppure verifica OVMF; usa `make run-uefi` |
| Build sporca / errori strani | `sudo make distclean && sudo make build` |
| Pacchetto non trovato | Verifica nome in trixie e componenti in `auto/config` (`--archive-areas`) |
| `gzip: stdin: unexpected end of file` / `Errore 1` generico | Vedi §6.2 (pulizia totale, `CACHE=false`, mirror alternativo, `make debug`) |
| `lb config: opzione non riconosciuta "--xxx"` | `auto/config` filtra le opzioni non supportate; se l'errore compare, aggiorna il progetto (`git pull`) e riporta l'output di `lb --version` |
| `E: The repository 'http://security.debian.org trixie/updates Release' does not have a Release file` | Vedi §6.1 |

### 6.1 Errore 100 — repository `trixie/updates` senza Release file

Sintomo (durante `apt update` nel chroot):

```
E: The repository 'http://security.debian.org trixie/updates Release' does not have a Release file.
N: Updating from such a repository can't be done securely, and is therefore disabled by default.
make: *** [Makefile:17: build] Errore 100
```

Causa: per la suite `trixie` il repository di sicurezza è
**`http://security.debian.org/debian-security` con suite `trixie-security`**
(mentre `trixie-updates` sta su `deb.debian.org/debian`). Alcune versioni di
live-build generano invece la vecchia riga `${dist}/updates`, che non esiste e
fa fallire `apt update` (exit 100).

Soluzione già applicata in questo progetto:

1. `auto/config` usa `--security false` (live-build non genera più quella riga)
   e i mirror di sicurezza corretti
   (`--mirror-chroot-security`/`--mirror-binary-security` →
   `http://security.debian.org/debian-security/`);
2. il repository corretto è fornito da `config/archives/livedeb13-security.list`
   (usato nel chroot di build **e** nel sistema live).

Dopo aver aggiornato il progetto è **obbligatorio** rigenerare la configurazione
e ripulire gli artefatti della build fallita:

```bash
make config                 # rigenera config/ da auto/config
sudo make distclean         # lb clean --purge (rimuove chroot/, cache/, .build/)
sudo make build
```

Se dopo `make build` il problema si ripresenta, allega l'output di
`lb --version` e di `lb config --help | head -40`: serve a capire quali
opzioni supporta la tua live-build.

### 6.2 Altri errori generici (`Errore 1`, `gzip: stdin: unexpected end of file`)

Sintomo tipico: la build si interrompe con `make: *** Errore 1` e, poco prima,
messaggi come:

```
gzip: stdin: unexpected end of file
P: Begin unmounting filesystems...
P: Saving caches...
Reading package lists... Done
```

Sono quasi sempre **file scaricati troncati** (rete instabile, proxy, mirror
lento) oppure **cache corrotta** rimasta da una build precedente. Rimedi, in
ordine:

1. **Pulizia totale** (elimina chroot, cache e indici parziali):

   ```bash
   sudo make distclean
   sudo rm -rf chroot binary cache .build
   ```

2. **Build con cache disattivata** (riscarica tutto, niente dati vecchi):

   ```bash
   sudo env CACHE=false make build
   ```

3. **Mirror diverso** (es. mirror italiano, spesso più veloce dall'Italia):

   ```bash
   sudo env DEBIAN_MIRROR=http://ftp.it.debian.org/debian/ make build
   ```

   Per cambiare in modo permanente il mirror di sicurezza modifica
   `config/archives/livedeb13-security.list`.

4. **Log completo per diagnosi**:

   ```bash
   sudo make debug          # scrive tutto in build.log
   ```

   Da allegare in caso di segnalazione, insieme a:

   ```bash
   lb --version
   tail -80 build.log
   grep -nE "^(E:|W:)" build.log | tail -30
   ```

Se vuoi verificare cosa genera live-build, controlla:

```bash
cat chroot/etc/apt/sources.list
ls chroot/etc/apt/sources.list.d/
```

non devono comparire suite tipo `trixie/updates`.

### 6.3 `lb --version` = `3.0~a57` (live-build troppo vecchia — tipico di Ubuntu)

Sintomo: `lb config` rifiuta opzioni (`--image-name`, `--bootloaders`,
`--updates`, …), la build si ferma (spesso in `lb_chroot_linux-image`) con
`gzip: stdin: unexpected end of file`, e nel log compaiono variabili d'epoca
Debian 7/8:

```
LB_CONFIG_VERSION='3.0~a57'
LB_UNION_FILESYSTEM='aufs'
W: --force-yes is deprecated
```

Causa: **Ubuntu impacchetta una live-build ferma al 2013**
(`3.0~a57-1ubuntuXX`) e non ne esiste una versione moderna nei repo Ubuntu.
Quella versione non può costruire Debian 13, in nessun modo.

Rimedio: usa un ambiente Debian 13 — vedi **§8** (container `debian:trixie`,
GitHub Actions, o installazione della live-build di Debian). Poi:

```bash
sudo make distclean           # o: ./build-docker.sh --clean
sudo rm -rf chroot binary cache .build
sudo make build               # oppure: ./build-docker.sh
```

`auto/config` e `make check` verificano la versione e si fermano subito con un
messaggio esplicito se rilevano la serie 2.x/3.x, senza sprecare una build.

## 7. Build in CI

Il workflow `.github/workflows/build.yml` compila l’ISO su `debian:trixie`.
Per rilasciare una versione:

```bash
git tag v1.0.0
git push origin v1.0.0
```

## 8. Host non Debian (Ubuntu, Fedora, …) — usare un container Debian 13

live-build deve girare su **Debian 13**: su Ubuntu il pacchetto è la
`3.0~a57` del 2013 (vedi §6.3) e la build non può funzionare. Tre strade:

### 8.1 Container Debian 13 (consigliata)

```bash
sudo apt install docker.io        # oppure: sudo apt install podman
./build-docker.sh                 # alias: make docker
./build-docker.sh --clean         # con pulizia preventiva
RUNTIME=podman ./build-docker.sh  # se preferisci podman
```

Lo script:

- avvia `debian:trixie` con `--privileged` (serve per chroot e mount);
- monta la cartella del progetto in `/build`;
- installa `live-build`, `debootstrap`, `xorriso`, `squashfs-tools`, i
  bootloader e i firmware necessari;
- esegue `./auto/config` e `./auto/build`;
- lascia la ISO in `livedeb13-amd64.hybrid.iso` e riporta i file generati in
  proprietà all'utente host.

La prima esecuzione scarica l'immagine `debian:trixie` (~120 MB) e richiede
10–30 minuti; le successive sono più rapide.

### 8.2 GitHub Actions (nessuna installazione locale)

Nel repository: scheda **Actions** → **Build LiveDeb13 ISO** →
**Run workflow** (scegli la tua branch). Al termine scarica l'artifact
`livedeb13-amd64-<branch>`, che contiene la ISO.

> Il workflow è eseguibile da qui solo dopo che `.github/workflows/build.yml`
> è presente sul branch di default (`main`): se "Run workflow" non compare,
> fai il merge della branch in `main` e riprova — oppure usa §8.1/§8.3.

### 8.3 Installare la live-build di Debian sull'host (Ubuntu)

Miscela non supportata ufficialmente, ma funziona perché live-build è solo
shell + `debootstrap`:

```bash
sudo apt purge live-build
cd /tmp
wget http://deb.debian.org/debian/pool/main/l/live-build/live-build_20250505+deb13u1_all.deb
sudo apt install ./live-build_20250505+deb13u1_all.deb
hash -r
lb --version          # deve mostrare 20250505+deb13u1

cd ~/LiveDeb13
sudo make distclean
sudo make build
```

Se `debootstrap` di Ubuntu è troppo vecchio per `trixie`, installa anche
quello di Debian (`debootstrap_*_all.deb` dallo stesso mirror) oppure usa
§8.1.
