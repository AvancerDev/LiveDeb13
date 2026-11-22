# LiveDeb13 — Debian 13 (trixie) Minimal Live + Installer

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

---

## Quick start

```bash
git clone https://github.com/AvancerDev/LiveDeb13.git
cd LiveDeb13

# 1. Configura (genera config/ da auto/config)
make config
# oppure: ./auto/config

# 2. Compila l’ISO (richiede root)
sudo make build
# oppure: sudo ./auto/build

# L’ISO si trova nella radice del progetto:
ls -lh livedeb13-amd64.hybrid.iso
```

### Test rapido in VM (QEMU)

```bash
make run        # BIOS
make run-uefi   # UEFI (richiede OVMF)
```

### Scrivere su USB

```bash
# Sostituisci /dev/sdX con la tua chiavetta (ATTENZIONE: cancella tutto!)
sudo dd if=livedeb13-amd64.hybrid.iso of=/dev/sdX bs=4M status=progress oflag=sync
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

Vedi `config/package-lists/` per l’elenco completo e modificabile.

---

## Personalizzazione rapida

Tutto si modifica senza toccare `auto/config` (che è solo un wrapper di `lb config`):

| Cosa | File |
|---|---|
| Pacchetti live | `config/package-lists/packages.list.chroot` |
| Pacchetti installati sul target | `config/package-lists/packages.list.chroot_install` |
| Hostname, MOTD | `config/includes.chroot/etc/` |
| Sorgenti APT (sicurezza) | `config/archives/livedeb13-security.list` |
| Utente live, locale | `config/hooks/live/` |
| Preseed installer | `config/preseed/preseed.cfg` |
| Script extra | `config/includes.chroot/usr/local/bin/` |

Guida completa: [`docs/CUSTOMIZE.md`](docs/CUSTOMIZE.md) ·
Build & test: [`docs/BUILD.md`](docs/BUILD.md)

---

## Struttura del progetto

```
.
├── auto/                  # Wrapper lb config/build/clean
│   ├── config
│   ├── build
│   └── clean
├── config/
│   ├── package-lists/     # Elenchi pacchetti (.chroot / .chroot_install)
│   ├── includes.chroot/   # File copiati nel live system
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
`config/archives/livedeb13-security.list` (suite `trixie-security` su
`security.debian.org/debian-security`) e la generazione automatica è disattivata
in `auto/config` (`--security false`). Dopo un aggiornamento del progetto:
`make config && sudo make distclean && sudo make build`.
Dettagli: [`docs/BUILD.md`](docs/BUILD.md) §6.1.

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
