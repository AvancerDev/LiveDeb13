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
lb --version
```

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

## 7. Build in CI

Il workflow `.github/workflows/build.yml` compila l’ISO su `debian:trixie`.
Per rilasciare una versione:

```bash
git tag v1.0.0
git push origin v1.0.0
```
