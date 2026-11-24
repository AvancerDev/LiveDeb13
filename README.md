<p align="center">
  <img src="docs/images/zinimalos-logo.png" alt="ZinimalOS" width="220">
</p>

# ZinimalOS — Debian 13 (trixie) Minimal Live + Installer

Fork minimale di **Debian 13 “trixie”** basato su [`live-build`](https://wiki.debian.org/Live/Build/GettingStarted).

- **Architettura:** `amd64` (x86_64)
- **Ambiente:** solo console (nessun desktop environment)
- **Scopo:** immagine **Live + Installer** (Debian Installer in modalità testuale)
- **Formato:** ISO ibrida BIOS/UEFI avviabile da USB/DVD/VM

> Obiettivo: un sistema live leggero (~600–900 MB) per rescue, manutenzione e
> installazione di Debian 13 su disco, con possibilità di personalizzazione
> completa tramite file di configurazione in `config/`.

---

## Requisiti

Per compilare l’ISO serve una macchina **Debian 13 (trixie)** o superiore
(anche Debian 12 funziona, ma trixie è consigliato per allineare i pacchetti).

```bash
sudo apt update
sudo apt install -y live-build debootstrap squashfs-tools xorriso isolinux \
  syslinux-common grub-pc-bin grub-efi-amd64-bin mtools dosfstools \
  qemu-system-x86 ovmf  # solo per i test in VM
```

> **Nota:** `live-build` deve essere la versione di trixie (`live-build >= 20250505`).
> Su Debian 12 potrebbe funzionare, ma alcuni flag di `lb config` sono diversi.
>
> **Su Ubuntu** il pacchetto `live-build` è fermo al 2013 (`3.0~a57`) e **non**
> può costruire Debian 13. Con docker/podman installato, `sudo make build`
> esegue automaticamente la build in un container Debian 13
> (`./build-docker.sh`); in alternativa compila via GitHub Actions.
> Vedi [`docs/BUILD.md`](docs/BUILD.md) §8.

---

## Quick start

```bash
git clone https://github.com/AvancerDev/ZinimalOS.git
cd ZinimalOS

# 1. Configura (genera config/ da auto/config)
make config
# oppure: ./auto/config

# 2. Compila l’ISO (richiede root)
sudo make build
# oppure: sudo ./auto/build

# L’ISO si trova nella radice del progetto:
ls -lh zinimalos-amd64.hybrid.iso
```

### Test rapido in VM (QEMU)

```bash
make run        # BIOS
make run-uefi   # UEFI (richiede OVMF)
```

### Scrivere su USB

```bash
# Sostituisci /dev/sdX con la tua chiavetta (ATTENZIONE: cancella tutto!)
sudo dd if=zinimalos-amd64.hybrid.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

Oppure con `Ventoy`, `balenaEtcher`, `GNOME Disks`, ecc.

---

## Cosa contiene l’immagine

| Componente | Dettagli |
|---|---|
| Base | Debian 13 trixie, `main + contrib + non-free + non-free-firmware` |
| Kernel | `linux-image-amd64` (kernel Debian standard) |
| Init | `systemd` |
| Bootloader | GRUB (UEFI + BIOS) + Syslinux/Isolinux (BIOS), Memtest86+ |
| Live user | `user` / password `live`, accesso sudo senza password nel live |
| Installer | Debian Installer testuale (`debian-installer`) |
| Rete | NetworkManager + iwd + wpasupplicant (Wi-Fi e Ethernet) |
| Firmware | `firmware-linux`, microcode Intel/AMD |
| Tools | `nano`, `vim-tiny`, `htop`, `tmux`, `curl`, `wget`, `openssh-server`, `mc`, `parted`, `cryptsetup`, `lvm2`, … |
| Logo | `Z` blu in `usr/share/zinimalos/logo.png`; versione ASCII in `fastfetch` (bianca) |
| Banner | `fastfetch` solo su richiesta, mai all’accesso; all’avvio solo il MOTD |
| Crediti | comando `made by` → creatore (`AvancerDev`) e progetto (`ZinimalOS`) |

Vedi `config/package-lists/` per l’elenco completo e modificabile.

---

## Personalizzazione rapida

Tutto si modifica senza toccare `auto/config` (che è solo un wrapper di `lb config`):

| Cosa | File |
|---|---|
| Pacchetti live | `config/package-lists/packages.list.chroot` |
| Pacchetti installati sul target | `config/package-lists/packages.list.chroot_install` |
| Hostname / hosts | `config/includes.chroot/etc/` |
| MOTD, `/etc/issue` (template) | `branding/rootfs/usr/share/zinimalos/{motd,issue}` |
| Metadati di release | `branding/rootfs/etc/zinimalos-release` |
| Sorgenti APT (sicurezza) | `config/archives/zinimalos-security.list` |
| Utente live, locale | `config/hooks/live/` |
| Preseed installer | `config/preseed/preseed.cfg` |
| Script extra | `config/includes.chroot/usr/local/bin/` |
| Logo (PNG + ASCII) | `branding/rootfs/usr/share/zinimalos/` |
| Banner `fastfetch` | `branding/rootfs/etc/fastfetch/config.jsonc` |
| Crediti `made by` | `branding/rootfs/etc/zinimalos-release` |
| Aggiornamenti (pacchetto + repo apt) | `packaging/` |

Guida completa: [`docs/CUSTOMIZE.md`](docs/CUSTOMIZE.md) ·
Build & test: [`docs/BUILD.md`](docs/BUILD.md) ·
Aggiornamenti (`apt upgrade`): [`docs/UPDATES.md`](docs/UPDATES.md)

---

## Struttura del progetto

```
.
├── auto/                  # Wrapper lb config/build/clean
│   ├── config
│   ├── build
│   └── clean
├── branding/rootfs/       # Contenuto del pacchetto zinimalos-branding
│   ├── etc/fastfetch/     # configurazione del banner
│   ├── etc/issue          # riga mostrata prima del login
│   ├── etc/zinimalos-release      # credito/versione (comando `made by`)
│   ├── etc/apt/           # repo apt firmato (chiave + .sources)
│   ├── usr/local/bin/     # made, made-by, zinimalos-info
│   └── usr/share/zinimalos/  # logo.png + logo-ascii.txt
├── packaging/             # build-deb.sh, setup-gpg.sh, publish-repo.sh
├── config/
│   ├── package-lists/     # Elenchi pacchetti (.chroot / .chroot_install)
│   ├── includes.chroot/   # File copiati nel live system (non pacchettizzati)
│   ├── includes.binary/   # File copiati nella ISO (bootloader, splash…)
│   ├── hooks/             # Script chroot/live eseguiti in build
│   ├── preseed/           # preseed.cfg per Debian Installer
│   ├── archives/          # Sorgenti APT extra + .deb locali opzionali
│   └── bootloaders/       # Config bootloader custom (opzionale)
├── docs/
├── .github/workflows/     # CI per build automatica ISO
├── Makefile
├── build.sh
└── README.md
```

---

## Aggiornamenti (apt upgrade)

Le personalizzazioni (logo, `/etc/issue`, MOTD, config di fastfetch, script)
vivono in `branding/rootfs/` e vengono distribuite come **pacchetto .deb**
`zinimalos-branding`, pubblicato in un repository apt firmato su GitHub Pages.

```bash
make deb        # costruisce dist/zinimalos-branding_<ver>_all.deb
make publish    # reprepro: inserisce, firma e pubblica su gh-pages

# sulle macchine ZinimalOS installate
sudo apt update && sudo apt upgrade
```

L'ISO installa lo **stesso** pacchetto (viene messo in
`config/includes.chroot/opt/zinimalos/packages/` e l'hook `0400` lo installa nel
chroot), quindi ciò che aggiorni con `apt` è identico a ciò che finisce
nell'immagine. Guida completa:
[`docs/UPDATES.md`](docs/UPDATES.md).

---

## CI/CD

Il workflow [`.github/workflows/build.yml`](.github/workflows/build.yml)
compila l’ISO su `debian:trixie` a ogni push/tag e la carica come artifact.
Per una release:

```bash
git tag v1.0.0
git push origin v1.0.0
```

---

## FAQ

**L’ISO non si avvia in UEFI?**
Verifica che `OVMF` sia installato e usa `make run-uefi`. Sull’hardware reale
assicurati che il Secure Boot sia disattivato oppure usa immagini con
`shim-signed` (già inclusi `shim-signed` e `grub-efi-amd64-signed`).

**Come cambio la password dell’utente live?**
Modifica `config/hooks/live/0300-create-user.hook.chroot` (riga `chpasswd`)
oppure rimuovilo per usare l’utente `debian` di default di live-config.

**Come aggiungo un desktop (es. Xfce)?**
Aggiungi `xfce4 xfce4-goodies lightdm` a `packages.list.chroot` e rimuovi
l’autologin console in `config/includes.chroot/etc/systemd/system/getty@tty1.service.d/`.
Vedi `docs/CUSTOMIZE.md`.

**Build fallisce con “Errore 100” e `trixie/updates Release` non trovato?**
È il vecchio schema del repository di sicurezza generato da alcune versioni di
live-build per `trixie`. In questo progetto la riga è fornita esplicitamente da
`config/archives/zinimalos-security.list` (suite `trixie-security` su
`security.debian.org/debian-security`) e la generazione automatica è disattivata
in `auto/config` (`--security false`). Dopo un aggiornamento del progetto:
`make config && sudo make distclean && sudo make build`.
Dettagli: [`docs/BUILD.md`](docs/BUILD.md) §6.1.

**Sono su Ubuntu e `lb --version` mostra `3.0~a57`?**
Ubuntu impacchetta una live-build del 2013, che non può costruire Debian 13.
Usa un ambiente Debian 13:

```bash
sudo apt install docker.io
./build-docker.sh          # oppure: make docker
```

In alternativa compila la ISO con GitHub Actions (Actions → Build ZinimalOS ISO
→ Run workflow) oppure installa la live-build di Debian sull'host.
Dettagli: [`docs/BUILD.md`](docs/BUILD.md) §6.3 e §8.

**Non riesco a scaricare l’ISO dalla CI (`fatal: .git non è un repository Git`
oppure `unzip: cannot find …zip`)?**
`gh run download` va lanciato **dentro il repo** (oppure con
`-R AvancerDev/ZinimalOS`): fuori da Git non sa quale repository interrogare.
Inoltre scarica **ed estrae** l’artifact, quindi lo `unzip` non serve — con `-n`
l’ISO finisce nella directory corrente:

```bash
cd ~/ZinimalOS
gh run download 45041861620 -n zinimalos-amd64-arena-e324deaa-zinimalos
ls -lh zinimalos-amd64.hybrid.iso
```

Dall’interfaccia web invece si scarica uno `.zip` da estrarre a mano.
Dettagli: [`docs/BUILD.md`](docs/BUILD.md) §7.

**Devo scaricare 1,45 GB di ISO a ogni modifica?**
No. Compilando in locale l’ISO compare direttamente nella cartella del
progetto (`./build-docker.sh`, oppure `sudo make build` su Debian 13) e le
build successive riusano `cache/` e `chroot/`: si riscaricano solo i pacchetti
cambiati, non l’ISO. Evita `make distclean` e `--clean`, che svuotano la cache.
Dettagli: [`docs/BUILD.md`](docs/BUILD.md) §9.

**`Do you want to continue? [Y/n] Abort.` / build che esce con 1?**
Apt si ferma perché manca `--yes` in `--apt-options` (sostituisce il default di
live-build). Nel progetto `auto/config` ora lo aggiunge **da solo**, anche se
sovrascrivi `APT_OPTIONS`: aggiorna con `git pull`. Se fallisce ancora,
`./build-docker.sh` salva tutto in `build.log`: controlla con
`grep -n 'Y/n\|Abort\|unexpected failure' build.log` e allegalo per l’analisi.
Dettagli: [`docs/BUILD.md`](docs/BUILD.md) §6.6.

**`ln: failed to create symbolic link 'binary/dists/testing/trixie': File exists`?**
Residuo dello stadio `binary` di una build interrotta. Rimedio senza
riscaricare il chroot: `rm -rf binary && rm -f .build/*binary* && ./build-docker.sh`.
Dettagli: [`docs/BUILD.md`](docs/BUILD.md) §6.10.

**Devo aggiornare le altre macchine?**
`sudo apt update && sudo apt upgrade`: il pacchetto `zinimalos-branding` porta
logo, banner, MOTD e script, Debian porta il resto. Vedi
[`docs/UPDATES.md`](docs/UPDATES.md).

**Ho modificato `config/` ma la ISO è identica?**
live-build salta gli stadi già fatti (`W: Skipping …, already done`), quindi le
modifiche a `config/includes.chroot/` non entrano nell’immagine. `auto/build`
ora se ne accorge e riesegue chroot + binary da solo; per forzare a mano:
`rm -f .build/chroot_* .build/binary*` (oppure `./build-docker.sh --force`).
Dettagli: [`docs/BUILD.md`](docs/BUILD.md) §3.1.

**`Cannot stat source directory "chroot"`?**
Build uccisa a metà: `.build/` dichiara completati stadi che non esistono più.
Rimedio che **non riscarica nulla**: `rm -rf .build && ./build-docker.sh`
(non serve `--reset`, la cache `cache/` non va toccata). Dettagli:
[`docs/BUILD.md`](docs/BUILD.md) §6.9.

**`E: lb bootstrap_cache already locked`?**
Lock rimasto da una build interrotta (Ctrl-C, container ucciso): è il file
`.lock` nella radice del progetto. Rimedio immediato:
`rm -f .lock && ./build-docker.sh --reset` — non riscarica nulla. Da questa
versione `build-docker.sh` lo rimuove da sé. Dettagli:
[`docs/BUILD.md`](docs/BUILD.md) §6.8.

**`error: unable to create file config/…: Permesso negato`?**
I file generati da `lb config` sono di proprietà di `root` (build lanciata con
`sudo`): `git` non può aggiornarli. Rimedio una volta sola:
`sudo chown -R "$USER:$USER" .` poi `git reset --hard origin/<branch>`.
Dettagli: [`docs/BUILD.md`](docs/BUILD.md) §6.7.

**`E: Unable to locate package …`?**
Un nome nella lista pacchetti non esiste in Debian (spesso è il nome Ubuntu:
`gptfdisk` → `gdisk`). Se il tuo albero è aggiornato questo non può più
succedere: `auto/config` ferma la build **subito**, indicando file e nome
corretto. Se compare ancora `gptfdisk`, il tuo clone è vecchio — `git pull`.
Verifica completa della lista: `make check-packages` (container Debian 13).
Dettagli: [`docs/BUILD.md`](docs/BUILD.md) §6.5.

**`Temporary failure resolving 'deb.debian.org'`?**
È la rete/DNS della macchina che compila, non la configurazione. In container:
`./build-docker.sh --net-host` (o `--dns 1.1.1.1`). Su rete lenta alza i
timeout con `sudo env APT_OPTIONS="--option Acquire::Retries=10 --option Acquire::http::Timeout=300" make build`
e/o usa un mirror vicino. Dettagli: [`docs/BUILD.md`](docs/BUILD.md) §6.4.

**`gzip: stdin: unexpected end of file` / `make: *** Errore 1`?**
Di solito è un download troncato o una cache corrotta: `sudo make distclean && sudo rm -rf chroot binary cache .build && sudo env CACHE=false make build`. Per diagnosi: `sudo make debug` (log in `build.log`). Vedi [`docs/BUILD.md`](docs/BUILD.md) §6.2.

**`lb config: opzione non riconosciuta "--xxx"`?**
`auto/config` passa solo le opzioni elencate da `lb config --help` della tua
versione di live-build (le altre vengono saltate con un avviso). Se compare
ancora questo errore, aggiorna il progetto (`git pull`) e fornisci l'output di
`lb --version`.

**Build fallisce con “lb: command not found”?**
Installa `live-build` (vedi Requisiti) e ricompila da una directory pulita:
`sudo make distclean && sudo make build`.

---

## Licenza

Questo progetto è rilasciato sotto **GPL-3.0-or-later** (stessa licenza di
`live-build`). Debian è un marchio dei rispettivi proprietari.
