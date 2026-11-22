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

## Cambiare hostname / MOTD

```
config/includes.chroot/etc/hostname
config/includes.chroot/etc/motd
```

## Sorgenti APT (build e sistema live)

I mirror principali si impostano in `auto/config` (`--mirror-bootstrap`,
`--mirror-chroot`, `--mirror-binary`): live-build genera da sé
`/etc/apt/sources.list` nel chroot e nel sistema live.

Il repository di **sicurezza** invece è fornito esplicitamente da:

```
config/archives/livedeb13-security.list
```

Questo file viene installato come `/etc/apt/sources.list.d/livedeb13-security.list`
**sia nel chroot di build sia nel sistema live**. In `auto/config` la generazione
automatica della riga di sicurezza è disattivata (`--security false`), perché per
`trixie` alcune versioni di live-build producono ancora il vecchio schema
`trixie/updates` (vedi troubleshooting in `docs/BUILD.md`).

Per cambiare mirror di sicurezza, modifica il file qui sopra (o i parametri
`--mirror-chroot-security` / `--mirror-binary-security` in `auto/config`).

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
