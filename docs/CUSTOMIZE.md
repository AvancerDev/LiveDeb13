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
branding/rootfs/etc/motd
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
| Logo PNG (512×512) | `branding/rootfs/usr/share/zinimalos/logo.png` |
| Logo ASCII per `fastfetch` | `branding/rootfs/usr/share/zinimalos/logo-ascii.txt` |
| Riga mostrata prima del login (`/etc/issue`) | `branding/rootfs/etc/issue` |
| Anteprima per il README | `docs/images/zinimalos-logo.png` |

Dove compare il logo:

| Momento | Cosa si vede |
|---|---|
| Schermata di login (prima di autenticarsi) | **solo una riga di testo** (`/etc/issue`), nessun logo |
| Dopo il login | **solo il testo** del MOTD (`/etc/motd`) |
| `fastfetch` lanciato a mano | logo ASCII **bianco** a sinistra + info di sistema a destra |

Il logo ASCII è deliberatamente composto **solo da caratteri ASCII** (`#` e
`*`): i caratteri a blocchi Unicode (`█ ▄ ▀ ✦`) vengono spesso disegnati male
dalla console (finiscono in rombi "di sostituzione" se il font non li ha).
La riga che inizia con `$1` indica a fastfetch il colore del logo: il bianco è
impostato in `/etc/fastfetch/config.jsonc` con `"color": { "1": "white" }`.

Per sostituire il logo:

```bash
# PNG (≤ 512×512, pochi colori per non gonfiare l'ISO)
convert nuovo.png -resize 512x512 -colors 128 -strip \
  branding/rootfs/usr/share/zinimalos/logo.png

# ASCII: una riga di file = una riga di logo, prefisso $1 per il colore
$EDITOR branding/rootfs/usr/share/zinimalos/logo-ascii.txt
```

### File rimossi dal progetto: attenzione

live-build **copia** `config/includes.chroot/` nel chroot ma **non cancella**
i file che togli dal progetto: su un chroot già esistente restano per sempre.
Per questo c’è `config/hooks/normal/0300-remove-stale-files.hook.chroot`, che
rimuove i residui noti (vecchio banner `00-*-welcome.sh`, file `livedeb13-*`).
Se rimuovi altri file, aggiungili a quell’hook oppure ricrea il chroot da zero.

Con l’introduzione del pacchetto `zinimalos-branding` (vedi
[`docs/UPDATES.md`](UPDATES.md)) il problema riguarda solo i file rimasti in
`config/includes.chroot/`: logo, `/etc/issue`, MOTD, config fastfetch e script
`made*` viaggiano dentro il `.deb` e passano da dpkg.

## Banner fastfetch

`fastfetch` è installato (in `packages.list.chroot` e
`packages.list.chroot_install`) ma **non viene eseguito all’accesso**: lo lanci
tu quando vuoi. Configurazione: `branding/rootfs/etc/fastfetch/config.jsonc`.

- **logo**: `logo-ascii.txt`, colore bianco;
- **moduli**: `title`, `os`, `host`, `kernel`, `uptime`, `packages`, `shell`,
  `terminal`, `cpu`, `gpu`, `memory`, `disk`, `localip`, `colors`, più due
  righe custom con nome e crediti.

Per personalizzare i moduli modifica l’array `modules`; elenco completo su
<https://github.com/fastfetch-cli/fastfetch/wiki/Configuration>.

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
# branding/rootfs/etc/zinimalos-release  →  /etc/zinimalos-release
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
