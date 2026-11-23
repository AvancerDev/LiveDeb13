#!/bin/sh
# ZinimalOS — logo e banner all'accesso sulla console.
# File installato in /etc/profile.d/, letto da /etc/profile per le shell di
# login: autologin su tty1, `login`, `ssh` con terminale.
#
# Disattivare:  export ZINIMALOS_NO_WELCOME=1   (oppure rimuovere questo file)

_zinimalos_welcome() {
    # solo shell interattive, con terminale vero
    case $- in
        *i*) ;;
        *) return 0 ;;
    esac
    [ -t 1 ] || return 0
    # TERM assente va bene (console seriale); salta solo se è "dumb"
    [ "${TERM:-}" = "dumb" ] && return 0

    # opt-out
    [ -n "${ZINIMALOS_NO_WELCOME:-}" ] && return 0

    # una sola volta per sessione
    [ -n "${ZINIMALOS_WELCOME_SHOWN:-}" ] && return 0
    ZINIMALOS_WELCOME_SHOWN=1
    export ZINIMALOS_WELCOME_SHOWN

    # Logo del sistema (ASCII, in ciano) + riga di presentazione
    if [ -r /usr/share/zinimalos/logo-ascii.txt ]; then
        printf '\033[1;36m'
        cat /usr/share/zinimalos/logo-ascii.txt
        printf '\033[0m\n    \033[1mZinimalOS\033[0m \033[2m— Debian 13 (trixie), live + installer\033[0m\n\n'
    fi

    command -v fastfetch >/dev/null 2>&1 || return 0

    # se la configurazione del progetto desse problemi, si rientra nel default
    fastfetch --config /etc/fastfetch/config.jsonc 2>/dev/null || fastfetch 2>/dev/null || true
}

_zinimalos_welcome
