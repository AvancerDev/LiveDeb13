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

Questo genera la directory `config/` a partire da `auto/config`.
Se modifichi `auto/config`, riesegui `make config` (o `lb config`).

## 3. Build

```bash
sudo make build
# equivale a: sudo ./auto/build
```

- Durata tipica: 10–30 minuti (dipende da rete/CPU).
- Output: `binary/live/livedeb13-amd64.iso`
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
qemu-system-x86_64 -m 2048 -cdrom binary/live/livedeb13-amd64.iso -boot d -enable-kvm
```

## 5. Scrittura su USB

```bash
# ATTENZIONE: sostituisci /dev/sdX con la chiavetta corretta!
sudo dd if=binary/live/livedeb13-amd64.iso of=/dev/sdX bs=4M status=progress oflag=sync
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
| Build sporca / errori strani | `sudo make distclean && make config && sudo make build` |
| Pacchetto non trovato | Verifica nome in trixie e componenti in `auto/config` (`--archive-areas`) |

## 7. Build in CI

Il workflow `.github/workflows/build.yml` compila l’ISO su `debian:trixie`.
Per rilasciare una versione:

```bash
git tag v1.0.0
git push origin v1.0.0
```
