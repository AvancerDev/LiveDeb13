#!/bin/sh
# ZinimalOS — PATH con le directory di sistema anche per l'utente normale.
#
# Su Debian /etc/profile mette /usr/sbin e /sbin nel PATH solo per root. Nella
# live si usa l'utente "user", quindi comandi come `reboot`, `poweroff`,
# `fdisk`, `ifconfig`, `parted` risultano "comando non trovato" — anche se i
# binari esistono. Qui le aggiungiamo in coda, senza togliere nulla e senza
# stampare niente all'accesso.

case ":${PATH}:" in
  *:/usr/sbin:*) ;;
  *) PATH="${PATH}:/usr/sbin" ;;
esac
case ":${PATH}:" in
  *:/sbin:*) ;;
  *) PATH="${PATH}:/sbin" ;;
esac
export PATH
