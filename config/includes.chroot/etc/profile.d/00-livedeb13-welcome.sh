#!/bin/sh
# LiveDeb13 — mostra fastfetch all'accesso sulla console.
# File installato in /etc/profile.d/, quindi viene letto da /etc/profile per le
# shell di login: all'autologin su tty1, a `login` e a `ssh` con terminale.
#
# Disattivare:  export LIVEDEB13_NO_WELCOME=1   (oppure rimuovere questo file)

_livedeb13_welcome() {
    # solo shell interattive, con terminale vero
    case $- in
        *i*) ;;
        *) return 0 ;;
    esac
    [ -t 1 ] || return 0
    # TERM assente va bene (console seriale); salta solo se è "dumb"
    [ "${TERM:-}" = "dumb" ] && return 0

    # opt-out
    [ -n "${LIVEDEB13_NO_WELCOME:-}" ] && return 0

    # una sola volta per sessione
    [ -n "${LIVEDEB13_WELCOME_SHOWN:-}" ] && return 0

    command -v fastfetch >/dev/null 2>&1 || return 0

    LIVEDEB13_WELCOME_SHOWN=1
    export LIVEDEB13_WELCOME_SHOWN

    # se la configurazione del progetto desse problemi, si rientra nel default
    fastfetch --config /etc/fastfetch/config.jsonc 2>/dev/null || fastfetch || true
}

_livedeb13_welcome
