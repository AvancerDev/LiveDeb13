# Personalizzazione — LiveDeb13

Tutto si personalizza modificando i file in `config/` (nessuna modifica a `auto/config`
salvo per mirror/distribuzione).

## Aggiungere pacchetti

**Sistema live:**

```
# config/package-lists/packages.list.chroot
nano
htop
tmux
```

**Sistema installato (target):**

```
# config/package-lists/packages.list.chroot_install
openssh-server
```

Poi ricompila: `sudo make build`.

## Cambiare hostname / MOTD / sorgenti APT

```
config/includes.chroot/etc/hostname
config/includes.chroot/etc/motd
config/includes.chroot/etc/apt/sources.list.d/debian.sources
```

## Utente live e password

```
config/hooks/live/0300-create-user.hook.chroot
```

Cambia `user:live` con la password desiderata. Per disabilitare l’autologin
console, rimuovi:

```
config/includes.chroot/etc/systemd/system/getty@tty1.service.d/autologin.conf
```

## Locale, tastiera, fuso orario

In live-build 4.x (trixie) le opzioni `--locale`, `--keyboard-layout`,
`--timezone`, `--hostname`, `--username` sono state rimosse da `lb config`.
Si impostano con:

- Boot-time: `--bootappend-live` in `auto/config`
  (`hostname=`, `username=`, `locales=`, `keyboard-layouts=`, `timezone=`)
- Runtime: `config/hooks/normal/0200-set-locale.hook.chroot`
- Installer: `config/preseed/preseed.cfg`

## Preseed installer (unattended)

Decommenta le righe utente/partizionamento in `config/preseed/preseed.cfg`
per un’installazione completamente automatica. Vedi
<https://wiki.debian.org/DebianInstaller/Preseed>.

## Aggiungere un desktop (es. Xfce)

1. Aggiungi a `packages.list.chroot`:
   ```
   xfce4 xfce4-goodies lightdm
   ```
2. Rimuovi l’autologin console (vedi sopra).
3. Ricompila.

## Script e file extra

Metti script in:

```
config/includes.chroot/usr/local/bin/
```

Saranno disponibili nel live come comandi (`livedeb13-info`, ecc.).
Assicurati che siano eseguibili:

```bash
chmod +x config/includes.chroot/usr/local/bin/mio-script
```

## Pacchetti .deb locali

```
cp mio.deb config/archives/
```

Poi aggiungi `mio` a `packages.list.chroot`.

## Bootloader (menu di avvio)

Per impostazione predefinita live-build genera i menu. Per personalizzarli:

```
config/bootloaders/isolinux/isolinux.cfg
config/bootloaders/grub-efi/grub.cfg
config/bootloaders/grub-pc/grub.cfg
```

Vedi <https://wiki.debian.org/Live/Build/Customization#Bootloaders>.

## Cambiare mirror / distribuzione

Modifica `auto/config` (`--mirror-*`, `--distribution`, `--parent-distribution`)
e riesegui `make config`.

## Riferimenti

- <https://wiki.debian.org/Live/Build/GettingStarted>
- <https://wiki.debian.org/Live/Build/Customization>
- <https://manpages.debian.org/trixie/live-build/lb-config.1.en.html>
- <https://wiki.debian.org/DebianInstaller/Preseed>
