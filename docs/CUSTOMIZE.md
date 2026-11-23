# Personalizzazione — ZinimalOS

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
config/archives/zinimalos-security.list
```

Questo file viene installato come `/etc/apt/sources.list.d/zinimalos-security.list`
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

Saranno disponibili nel live come comandi (`zinimalos-info`, ecc.).
Assicurati che siano eseguibili:

```bash
chmod +x config/includes.chroot/usr/local/bin/mio-script
```

## Logo di sistema

| Cosa | File |
|---|---|
| Logo PNG (512×512) | `config/includes.chroot/usr/share/zinimalos/logo.png` |
| Logo ASCII (console) | `config/includes.chroot/usr/share/zinimalos/logo-ascii.txt` |
| Schermata pre-login (`/etc/issue`) | `config/includes.chroot/etc/issue` |
| Anteprima per il README | `docs/images/zinimalos-logo.png` |

Per sostituire il logo: rimpiazza `logo.png` (meglio ≤ 512×512, PNG, con
`-colors 128` per non gonfiare l’ISO) e, se vuoi cambiare anche l’arte su
console, `logo-ascii.txt` (ogni riga è stampata così com’è; meglio restare
sotto le 40 colonne di larghezza).

`/etc/issue` è ciò che `agetty` mostra **prima** del login, quindi il logo
compare già sulla schermata di accesso, senza attendere il banner.

## Banner fastfetch all’accesso

Il pacchetto `fastfetch` è incluso (in `packages.list.chroot` e
`packages.list.chroot_install`): all’accesso lo script di welcome stampa prima
il logo ASCII a colori, poi le info di sistema.

| Cosa | File |
|---|---|
| Configurazione (moduli, ordine, righe custom) | `config/includes.chroot/etc/fastfetch/config.jsonc` |
| Script che stampa logo + banner | `config/includes.chroot/etc/profile.d/00-zinimalos-welcome.sh` |

Personalizzare i moduli: modifica l’array `modules` nel `.jsonc`. Per esempio
per aggiungere la temperatura o togliere i colori finali:

```jsonc
"modules": ["title", "os", "kernel", "uptime", "cpu", "gpu", "cputemp", "memory"]
```

Elenco completo dei moduli: <https://github.com/fastfetch-cli/fastfetch/wiki/Configuration>.

Comportamento dello script di welcome:

- si attiva solo su **shell interattiva con terminale** (tty1 in autologin,
  `login`, `ssh`), mai per script, `scp`, cron o comandi non interattivi;
- una sola volta per sessione;
- disattivazione al volo: `export ZINIMALOS_NO_WELCOME=1`
  (per disattivarlo sempre aggiungi quella riga a
  `config/includes.chroot/etc/profile.d/`);
- se la configurazione desse problemi, ricade su `fastfetch` senza opzioni.

Per vedere il banner senza riavviare: `fastfetch` oppure
`fastfetch --config /etc/fastfetch/config.jsonc`.

## Crediti: comando `made by`

Nel live sono disponibili:

```bash
made by      # creatore (AvancerDev) + progetto (ZinimalOS)
made         # identico
made-by      # identico (nome senza spazio, comodo negli script)
```

`made by` funziona perché `made` è un piccolo comando in `/usr/local/bin/made`
che interpreta `by` come argomento: funziona in bash, dash, zsh, `ssh`, `sudo`
e anche incollata in uno script — non è un alias di shell.

I valori stampati vengono da un unico file:

```sh
# config/includes.chroot/etc/zinimalos-release  →  /etc/zinimalos-release
ZINIMALOS_PROJECT="ZinimalOS"
ZINIMALOS_CREATOR="AvancerDev"
ZINIMALOS_URL="https://github.com/AvancerDev/ZinimalOS"
ZINIMALOS_TAGLINE="Debian 13 (trixie) — live + installer"
ZINIMALOS_VERSION="1.0"
```

Per cambiare nome, URL o versione modifica quel file (e bumpa
`ZINIMALOS_VERSION` a ogni tag `vX.Y.Z`). Rispetta `NO_COLOR=1` e non usa
colori quando l’output è rediretto in un file o in una pipe.

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
