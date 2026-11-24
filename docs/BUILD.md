# Build & Test — ZinimalOS

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
`zinimalos-amd64.hybrid.iso`.

## 3. Build

```bash
sudo make build
# equivale a: sudo ./auto/build
```

- Durata tipica: 10–30 minuti (dipende da rete/CPU).
- Output: `zinimalos-amd64.hybrid.iso` (nella radice del progetto)
- Log: `*.build.log` nella root del progetto.

Pulizia:

```bash
sudo make clean        # lb clean
sudo make distclean    # lb clean --purge (cancella anche la cache)
```

### 3.1 Ho modificato `config/` ma la ISO è identica

live-build **salta** ogni stadio che ha già il suo *stage file* in `.build/`
(nome = nome dello script: `chroot_hooks`, `binary_rootfs`, …) e stampa
`W: Skipping …, already done`. Di conseguenza una modifica a
`branding/rootfs/` (logo, MOTD, `/etc/issue`, config di fastfetch) o
`config/includes.chroot/` non
entrerebbe **mai** nell’immagine: la build riesce ma produce un’ISO identica
alla precedente.

Da questa versione `auto/build` se ne accorge da solo: se un file di`config/`
è più recente dell’ultima build, rimuove gli stage file di `chroot` e `binary`
e li riesegue sul chroot esistente (**senza riscaricare pacchetti**).

Attenzione: live-build copia `config/includes.chroot/` ma **non cancella** i
file che rimuovi dal progetto, quindi un file eliminato continua a esistere nel
chroot (è il caso del vecchio banner che lanciava fastfetch). I residui noti
sono rimossi da `config/hooks/normal/0300-remove-stale-files.hook.chroot`.

Il caso più frequente è il branding: `branding/rootfs/` viene impacchettato in
`zinimalos-branding_*.deb` e installato nel chroot dall'hook `0400`, quindi se
non si rieseguono gli stadi il logo resta quello vecchio.

Se vuoi forzare a mano:

```bash
rm -f .build/chroot_* .build/binary*    # mirato: ~5 min, nessun download
./build-docker.sh
```

oppure `./build-docker.sh --force`, che passa `--force` a `lb build` e fa
rieseguire **tutti** gli stadi (più lento: anche bootstrap e reinstall dei
pacchetti, sempre dalla cache locale).

Verifica rapida che una modifica sia entrata nell’ISO senza riavviare la VM:

```bash
# la data dei file dentro il squashfs
unsquashfs -ll binary/live/filesystem.squashfs | grep -E 'etc/issue|logo-ascii'
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
qemu-system-x86_64 -m 2048 -cdrom zinimalos-amd64.hybrid.iso -boot d -enable-kvm
```

## 5. Scrittura su USB

```bash
# ATTENZIONE: sostituisci /dev/sdX con la chiavetta corretta!
sudo dd if=zinimalos-amd64.hybrid.iso of=/dev/sdX bs=4M status=progress oflag=sync
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
| `Do you want to continue? [Y/n] Abort.` | Manca `--yes` in `--apt-options` (vedi §6.6) |
| `E: Unable to locate package …` | Vedi §6.5: nome Debian ≠ nome Ubuntu; usa `make check-packages` |
| `Temporary failure resolving 'deb.debian.org'` | Vedi §6.4 (DNS/rete: `--net-host`, `--dns`, mirror alternativo) |
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
2. il repository corretto è fornito da `config/archives/zinimalos-security.list`
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
   `config/archives/zinimalos-security.list`.

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
GitHub Actions, o installazione della live-build di Debian).

Da quando esiste `build-docker.sh`, **`sudo make build` fa tutto da solo**: se
la live-build dell'host è assente o troppo vecchia e docker/podman è installato,
`auto/build` delega automaticamente la build al container Debian 13. Poi:

```bash
sudo make distclean           # o: ./build-docker.sh --clean
sudo rm -rf chroot binary cache .build
sudo make build               # oppure: ./build-docker.sh
```

`auto/config` e `make check` verificano la versione e si fermano subito con un
messaggio esplicito se rilevano la serie 2.x/3.x, senza sprecare una build.

### 6.4 `Temporary failure resolving 'deb.debian.org'`

```
Err:1 http://deb.debian.org/debian trixie/main amd64 dctrl-tools ...
  Temporary failure resolving 'deb.debian.org'
E: Failed to fetch ... Unable to fetch some archives
```

Non è un problema della configurazione: **il sistema che compila non riesce a
risolvere i nomi DNS** (o la connessione è instabile/molto lenta). Diagnosi:

```bash
getent hosts deb.debian.org          # deve stampare un IP
curl -sI http://deb.debian.org/debian/ | head -1
```

Rimedi:

- **Build in container** (`./build-docker.sh`): lo script verifica il DNS nel
  container e, se non funziona, aggiunge DNS pubblici; in alternativa forza la
  rete dell'host (utile con proxy/DNS aziendali o systemd-resolved):

  ```bash
  ./build-docker.sh --net-host
  ./build-docker.sh --dns 192.168.1.1     # DNS specifico
  ```

- **Rete lenta**: i timeout sono già a 120 s con 5 tentativi (`auto/config`);
  puoi alzarli:

  ```bash
  sudo env APT_OPTIONS="--option Acquire::Retries=10 --option Acquire::http::Timeout=300" make build
  ```

- **Mirror più vicino/veloce**:

  ```bash
  sudo env DEBIAN_MIRROR=http://ftp.it.debian.org/debian/ make build
  ```

- **Connessione molto lenta**: valuta la build su GitHub Actions (§8.2), che
  scarica tutto dai server GitHub/Debian e ti restituisce solo la ISO.

### 6.6 `Do you want to continue? [Y/n] Abort.` + `E: An unexpected failure occurred`

```
The following packages will be REMOVED:
  dctrl-tools*
Do you want to continue? [Y/n] Abort.
E: An unexpected failure occurred, exiting...
```

Causa: l'opzione `--apt-options` di `auto/config` **sostituisce** il valore
predefinito di live-build, che contiene `--yes`. Senza `--yes`, apt chiede
conferma quando live-build rimuove i pacchetti temporanei (es. `dctrl-tools`)
e, non essendo interattivo, abortisce.

Rimedio: `--apt-options` deve **sempre** iniziare con `--yes` (o `-y`):

```bash
--apt-options "--yes --option Acquire::Retries=5 --option Acquire::http::Timeout=120"
```

Da questa versione del progetto `auto/config` **aggiunge `--yes` da solo** se
manca, quindi anche una sovrascrittura da ambiente non può più reintrodurre il
problema:

```bash
# va bene anche senza --yes: viene aggiunto da auto/config
sudo env APT_OPTIONS="--option Acquire::Retries=10 --option Acquire::http::Timeout=300" make build
```

Per verificare cosa viene passato davvero a `lb config`:

```bash
./auto/config 2>&1 | grep APT_OPTIONS
# APT_OPTIONS: --yes --option Acquire::Retries=5 --option Acquire::http::Timeout=120
```

### 6.5 `E: Unable to locate package <nome>`

```
P: Begin installing packages (live pass)...
E: Unable to locate package gptfdisk
E: An unexpected failure occurred, exiting...
```

Uno dei nomi in `config/package-lists/` non esiste in Debian (spesso è un nome
**di Ubuntu**, diverso da quello Debian).

Da questa versione `auto/config` controlla i nomi noti come errati **prima** di
iniziare (10 ms invece di 15 minuti) e si ferma con la correzione pronta:

```
ERRORE: nomi di pacchetto che non esistono in Debian 13 (trixie):
  config/package-lists/packages.list.chroot: gptfdisk  ->  gdisk
```

Il controllo copre i casi visti finora (vedi tabella); per una verifica
completa e aggiornata serve `./check-packages.sh` (usa un container). Esempi
tipici:

| Nome errato (Ubuntu) | Nome corretto in Debian 13 |
|---|---|
| `gptfdisk` | `gdisk` |
| `dnsutils` (virtuale) | `bind9-dnsutils` |
| pacchetti grafici (`gparted`) | non servono in una live solo console |

Controlla **tutta** la lista in pochi secondi, senza avviare una build:

```bash
./check-packages.sh        # oppure: make check-packages
```

Lo script usa un container `debian:trixie`, abilita
`main contrib non-free non-free-firmware` e segnala ogni nome mancante.
In alternativa verifica a mano su `https://packages.debian.org/trixie/<nome>`.

Corretto il nome, rilancia:

```bash
git pull
sudo make distclean
sudo rm -rf chroot binary cache .build
sudo make build
```

### 6.7 `error: unable to create file config/…: Permesso negato` (git bloccato)

```
error: unable to create file config/hooks/normal/0200-set-locale.hook.chroot: Permesso negato
fatal: Impossibile ripristinare il file indice alla revisione 'origin/…'
```

`lb config` scrive file generati **dentro `config/`**. Se la build è stata
lanciata con `sudo make build` (o se il container ha scritto come root), quei
file diventano di proprietà di `root`: poi `git` — che gira come te — non può
più sostituirli, e anche le build successive si bloccano.

Rimedio (una volta sola, dalla radice del progetto):

```bash
sudo chown -R "$USER:$USER" .          # oppure: sudo chown -R "$USER:$USER" config
git fetch origin
git reset --hard origin/arena/e324deaa-zinimalos
```

Da questa versione `./build-docker.sh` restituisce `config/`, `chroot/`,
`binary/`, `.build/` e `cache/` al tuo utente **anche quando la build
fallisce**, così il problema non si ripresenta.

### 6.8 `E: lb bootstrap_cache already locked`

```
[2026-11-22 18:40:12] lb bootstrap_cache restore
P: Restoring bootstrap stage from cache...
E: lb bootstrap_cache already locked
E: An unexpected failure occurred, exiting...
```

Ogni stadio di live-build prende un lock creando il file **`.lock`** nella
directory di build (la radice del progetto) e lo cancella all’uscita. Se la
build viene interrotta bruscamente — Ctrl-C, container ucciso, terminale
chiuso, crash — il file resta lì e **tutte** le build successive si fermano
subito, prima di fare qualsiasi cosa.

Rimedio (2 secondi, non riscarica nulla):

```bash
cd ~/ZinimalOS
rm -f .lock
./build-docker.sh --reset
```

Da questa versione `./build-docker.sh` rimuove da solo un `.lock` orfano
all’avvio e non ne lascia dietro se la build fallisce; `.lock` è in
`.gitignore`.

### 6.9 `Cannot stat source directory "chroot"` (dopo un kill forzato)

```
[2026-11-24 11:49:50] lb binary_rootfs
P: Begin building root filesystem image...
P: Preparing squashfs image...
Cannot stat source directory "chroot" because No such file or directory
E: An unexpected failure occurred, exiting...
```

Se la build viene uccisa (kill, container terminato, PC sospeso) live-build può
lasciare in `.build/` i file di stage che dichiarano **completati** gli stadi del
chroot, mentre `chroot/` non esiste più. La build allora salta tutto:

```
W: Skipping chroot_dpkg, already done
W: Skipping chroot_install-packages.live, already done
...
```

e arriva a `binary_rootfs` senza niente da impacchettare.

Rimedio **senza riscaricare nulla** (non serve `--reset`, non serve toccare
`cache/`):

```bash
rm -rf .build       # solo i file di stato; cache/, chroot/ e binary/ restano
./build-docker.sh
```

`cache/` contiene i `.deb` già scaricati (`cache/packages.*`) e lo stage del
bootstrap (`cache/bootstrap`), quindi la reinstallazione è locale e veloce.
Da questa versione `./build-docker.sh` riconosce da sé l’incoerenza e rimuove
`.build/` all’avvio.

Per capire cosa c’è in cache prima di decidere:

```bash
du -sh cache/*         # bootstrap/, packages.bootstrap/, packages.chroot/…
```

Se `cache/` è vuota (mai completata una build), i pacchetti — firmware incluso —
vanno riscaricati una volta; dalle build successive restano in cache.

### 6.10 `ln: failed to create symbolic link 'binary/dists/testing/trixie': File exists`

```
[11:59:34] lb binary_debian-installer
Fetched 201 MB in 1min 19s (2561 kB/s)
Download complete and in download only mode
ln: failed to create symbolic link 'binary/dists/testing/trixie': File exists
E: An unexpected failure occurred, exiting...
```

Lo stadio `binary` (squashfs + ISO + debian-installer) è rimasto **a metà** in una
build precedente: `binary/dists/testing/trixie` esiste già, quindi `ln -s` non
può ricrearlo. Rimediare è veloce e **non tocca il chroot né i `.deb` in cache**:

```bash
rm -rf binary
rm -f .build/*binary*      # senza i suoi stage file, lo stadio viene rifatto
./build-docker.sh
```

Costo tipico: ~4–6 minuti (viene riscaricato solo l’insieme del Debian
Installer, ~200 MB, perché live-build lo rifetcha a ogni passaggio; squashfs e
ISO vengono ricostruiti dal `chroot/` esistente).

Se vuoi provare la via più rapida (a tuo rischio, riusa tutto il resto):

```bash
rm -f binary/dists/testing/trixie
./build-docker.sh
```

Da questa versione `./build-docker.sh` rimuove da sé `binary/` e i suoi stage
file **quando una build fallisce**, così la successiva riparte pulita su quello
stadio senza errori da residui.

### 6.11 `trying to overwrite '/etc/issue', which is also in package base-files`

```
P: Executing hook config/hooks/normal/0400-install-branding-deb.hook.chroot...
dpkg: error processing archive /opt/zinimalos/packages/zinimalos-branding_....deb (--install):
 trying to overwrite '/etc/issue', which is also in package base-files (13.8+deb13u8)
E: config/hooks/normal/0400-install-branding-deb.hook.chroot failed (exit non-zero)
```

`/etc/issue` **appartiene al pacchetto `base-files`** di Debian: nessun altro
pacchetto può dichiararlo come proprio (dpkg lo rifiuta, ed è giusto così).

Dal commit che ha introdotto il pacchetto di branding la struttura è:

| File | Chi lo possiede |
|---|---|
| `/usr/share/zinimalos/issue`, `/usr/share/zinimalos/motd` | `zinimalos-branding` (template) |
| `/etc/issue`, `/etc/motd` | applicati dal `postinst` del pacchetto |

Il `postinst` copia i template e salva il checksum in `/var/lib/zinimalos/`:
se hai modificato `/etc/issue` a mano, l'upgrade non lo sovrascrive (stampa un
avviso). Per ripristinare la versione ufficiale:

```bash
sudo rm /etc/issue && sudo apt install --reinstall zinimalos-branding
```

### Perché è potuto riapparire (e perché non riapparirà)

Il rimedio al pacchetto non bastava: live-build **copia** i file nel chroot ma
non cancella quelli che non ci sono più. Dopo una build fallita, in
`chroot/opt/zinimalos/packages/` restavano **due** `.deb`:

```
zinimalos-branding_1.0.202611241359_all.deb   ← vecchio, con /etc/issue dentro
zinimalos-branding_1.0.202611241409_all.deb   ← corretto
```

L'hook installava il primo che trovava (`1359`, il vecchio) e l'errore tornava
identico, nonostante il pacchetto fosse stato corretto. Tre contromisure, tutte
attive:

1. nella ISO il pacchetto ha **nome fisso** `zinimalos-branding.deb`: non si
   accumulano più versioni;
2. l'hook installa **solo il più recente** e cancella gli altri `.deb` prima di
   installare;
3. dopo l'installazione l'hook verifica che la versione installata sia quella
   del `.deb` e che `/etc/issue` contenga `ZinimalOS`, altrimenti ferma la build.

Se ti capita con una versione **vecchia** del pacchetto, la build è morta a metà
e il chroot ha il pacchetto in stato inconsistente. L'hook `0400` ora lo
ripulisce da sé (`dpkg --purge --force-all` se lo stato non è uno di quelli
puliti); se vuoi essere sicuro, riesegui gli stadi del chroot:

```bash
rm -f .build/chroot_* .build/binary*
./build-docker.sh
```

## 7. Build in CI

Il workflow `.github/workflows/build.yml` compila l’ISO su `debian:trixie`
(container `--privileged`, live-build 20250505+deb13u1). Ogni PR esegue la build:
l’ISO compare come **artifact** della run.

Scaricare l’ISO (artifact `zinimalos-amd64-<branch>`):

- **interfaccia web**: PR (o Actions) → run → sezione *Artifacts* → clic sul
  nome dell’artifact. Si scarica uno `.zip`: va estratto (dentro c’è
  `zinimalos-amd64.hybrid.iso`).
- **da terminale** (con `gh`, consigliato): `gh run download` scarica **ed
  estrae** l’artifact, quindi **non serve `unzip`**. Con `-n` (un solo
  artifact) i file finiscono nella directory corrente:

  ```bash
  cd ~/ZinimalOS                       # dentro il repo, altrimenti errore
  gh run list --limit 5                # trova il <RUN_ID> verde
  gh run download <RUN_ID> -n zinimalos-amd64-arena-e324deaa-zinimalos
  ls -lh zinimalos-amd64.hybrid.iso    # ~1.5 GB
  sha256sum zinimalos-amd64.hybrid.iso
  ```

  Se non sei dentro il repo (`fatal: .git non è un repository Git`), indica il
  repository esplicitamente:

  ```bash
  gh run download <RUN_ID> -R AvancerDev/ZinimalOS \
     -n zinimalos-amd64-arena-e324deaa-zinimalos -D ~/Downloads
  ```

  `-D`/`--dir` esiste da `gh` 2.28: con versioni più vecchie fai `cd` nella
  directory di destinazione e ometti `-D`.

  Nome dell’artifact per ogni branch (controllalo in *Artifacts*, il suffisso
  cambia): `zinimalos-amd64-${branch con '/' → '-'}`; su `main` e sui tag è
  `zinimalos-amd64-main` / `zinimalos-amd64-v1.0.0`.

- **senza `gh`, via API** (richiede un token GitHub):

  ```bash
  gh auth token > token.txt        # oppure un PAT con scope repo
  curl -L -H "Authorization: token $(cat token.txt)" \
    -o iso.zip \
    https://api.github.com/repos/AvancerDev/ZinimalOS/actions/artifacts/<ARTIFACT_ID>/zip
  unzip iso.zip
  ```

  L’`<ARTIFACT_ID>` si legge dall’interfaccia web (URL dell’artifact) o con
  `gh api repos/AvancerDev/ZinimalOS/actions/runs/<RUN_ID>/artifacts`.

In caso di errore, il workflow commenta automaticamente la PR con le ultime
200 righe di `build.log`, così la diagnosi non richiede di scaricare nulla.
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
./build-docker.sh --net-host      # rete dell'host (DNS/proxy aziendali)
./build-docker.sh --dns 1.1.1.1   # DNS specifico
RUNTIME=podman ./build-docker.sh  # se preferisci podman
```

`sudo make build` (o `make debug`) su Ubuntu **delega automaticamente** a
`build-docker.sh`: è sufficiente avere docker o podman installato.

Lo script:

- verifica il DNS dentro il container e aggiunge DNS pubblici se serve;
- avvia `debian:trixie` con `--privileged` (serve per chroot e mount);
- monta la cartella del progetto in `/build`;
- installa `live-build`, `debootstrap`, `xorriso`, `squashfs-tools`, i
  bootloader e i firmware necessari;
- esegue `./auto/config` e `./auto/build`;
- lascia la ISO in `zinimalos-amd64.hybrid.iso` e riporta i file generati in
  proprietà all'utente host.

La prima esecuzione scarica l'immagine `debian:trixie` (~120 MB) e richiede
10–30 minuti; le successive sono più rapide.

### 8.2 GitHub Actions (nessuna installazione locale)

Nel repository: scheda **Actions** → **Build ZinimalOS ISO** →
**Run workflow** (scegli la tua branch). Al termine scarica l'artifact
`zinimalos-amd64-<branch>`, che contiene la ISO.

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

cd ~/ZinimalOS
sudo make distclean
sudo make build
```

Se `debootstrap` di Ubuntu è troppo vecchio per `trixie`, installa anche
quello di Debian (`debootstrap_*_all.deb` dallo stesso mirror) oppure usa
§8.1.

## 9. Build locale o CI: cosa si scarica ogni volta

L’ISO pesa ~1,45 GB: è il collo di bottiglia quando la rete è lenta.

| | Download di pacchetti | Download dell’ISO |
|---|---|---|
| **CI** (GitHub Actions) | ~1,2–1,5 GB **a ogni run** (runner usa-e-getta) | 1,45 GB di artifact da scaricare |
| **Build locale, prima volta** | ~1,2–1,5 GB (bootstrap + firmware) | nessuno |
| **Build locale, volte successive** | solo i `.deb` nuovi o cambiati (spesso 0–100 MB) | nessuno |

Quindi per iterare sulla configurazione **conviene compilare in locale**: il
primo giro costa quanto la CI, tutti gli altri quasi solo CPU (squashfs +
xorriso, circa 3–8 minuti).

```bash
./build-docker.sh        # host Ubuntu: build in container Debian 13
# oppure, su Debian 13:  sudo make build
make run                 # avvia l'ISO appena prodotta in QEMU
```

Regola d’oro: **non cancellare `cache/` e `chroot/`**, sono la cache.

| Comando | Cosa rimuove | Riscarica i pacchetti? |
|---|---|---|
| `./build-docker.sh` | nulla | no (solo i cambiamenti) |
| `./build-docker.sh --reset` | `chroot/`, `binary/`, `.build/` | no: reinstalla dai `.deb` in `cache/` |
| `make clean` | `chroot/`, `binary/` | no: reinstalla dai `.deb` in `cache/` |
| `make distclean`, `./build-docker.sh --clean` | tutto, `cache/` compresa | **sì, da zero (~1,5 GB)** |

Ogni build lanciata con `./build-docker.sh` salva l’output completo in
`build.log` (nella radice del progetto) e, in caso di errore, ne stampa le
ultime 30 righe con i controlli da fare: se ti serve aiuto, basta allegare
quel file.

La CI resta utile per: verificare che la build funzioni su un ambiente pulito,
avere un’ISO “ufficiale” a ogni push, e produrla se non hai Debian 13 né
docker. Per il lavoro quotidiano, la build locale è più veloce e non scarica
niente.
