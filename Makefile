# LiveDeb13 — Makefile
# Wrapper comodo attorno a live-build (lb). La build richiede root.
#
# L'ISO prodotta da live-build (--binary-image iso-hybrid, --image-name livedeb13)
# si trova nella radice del progetto: livedeb13-amd64.hybrid.iso

SHELL := /bin/bash
LB := lb
ISO := livedeb13-amd64.hybrid.iso

# Usa KVM solo se disponibile, altrimenti QEMU va in emulazione (lento ma funziona)
QEMU_KVM := $(shell [ -w /dev/kvm ] && echo "-enable-kvm")
OVMF_CODE := $(firstword $(wildcard /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd))
OVMF_VARS_SRC := $(firstword $(wildcard /usr/share/OVMF/OVMF_VARS_4M.fd /usr/share/OVMF/OVMF_VARS.fd))

.PHONY: help config build docker debug clean distclean run run-uefi usb check iso

help: ## Mostra questo help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

config: ## Configura il build (lb config via auto/config)
	./auto/config

# auto/build rimuove lo stage file `.build/config`, così live-build riesegue
# sempre auto/config: le modifiche alla configurazione sono sempre applicate.
build: ## Compila l'ISO (richiede root)
	sudo ./auto/build

clean: ## Pulisce gli artefatti di build (lb clean)
	sudo ./auto/clean

distclean: ## Pulizia completa (lb clean --purge: rimuove anche cache e stage)
	sudo ./auto/clean --purge

docker: ## Compila l'ISO in un container Debian 13 (docker/podman; per host Ubuntu)
	./build-docker.sh

debug: ## Build con log completo in build.log (da allegare in caso di errore)
	sudo ./auto/build --debug 2>&1 | tee build.log; exit $${PIPESTATUS[0]}

iso: build ## Alias di build + mostra info ISO
	@echo "ISO pronta: $(ISO)"
	@ls -lh $(ISO) 2>/dev/null || { echo "ISO non trovata: la build è fallita?"; exit 1; }

run: iso ## Avvia l'ISO in QEMU (BIOS)
	qemu-system-x86_64 -m 2048 -cdrom $(ISO) -boot d $(QEMU_KVM) -vga std

run-uefi: iso ## Avvia l'ISO in QEMU (UEFI, richiede OVMF)
	@if [ -z "$(OVMF_CODE)" ] || [ -z "$(OVMF_VARS_SRC)" ]; then echo "ERRORE: OVMF non trovato (sudo apt install ovmf)"; exit 1; fi
	cp "$(OVMF_VARS_SRC)" /tmp/OVMF_VARS_livedeb13.fd
	qemu-system-x86_64 -m 2048 -cdrom $(ISO) -boot d $(QEMU_KVM) \
	  -drive if=pflash,format=raw,readonly=on,file=$(OVMF_CODE) \
	  -drive if=pflash,format=raw,file=/tmp/OVMF_VARS_livedeb13.fd

usb: iso ## Scrive l'ISO su USB (USB=/dev/sdX make usb)
	@if [ -z "$(USB)" ]; then echo "Uso: USB=/dev/sdX make usb"; exit 1; fi
	@echo "Scrittura su $(USB) — i dati saranno cancellati. Continuo tra 5s (Ctrl+C per annullare)..."
	@sleep 5
	sudo dd if=$(ISO) of=$(USB) bs=4M status=progress oflag=sync

check: ## Verifica prerequisiti (lb, debootstrap, xorriso…)
	@command -v $(LB) >/dev/null || (echo "ERRORE: live-build non installato. Vedi README."; exit 1)
	@command -v debootstrap >/dev/null || (echo "ERRORE: debootstrap non installato."; exit 1)
	@command -v xorriso >/dev/null || (echo "ERRORE: xorriso non installato."; exit 1)
	@command -v mksquashfs >/dev/null || (echo "ERRORE: squashfs-tools non installato."; exit 1)
	@v=$$($(LB) --version 2>/dev/null | head -n1); echo "live-build: $${v:-sconosciuta}"; \
	 case "$${v#live-build }" in \
	   2.*|3.*) echo "ERRORE: live-build troppo vecchia (serie 2.x/3.x): serve quella di trixie (1:20250505+deb13u1)."; \
	            echo "        Vedi docs/BUILD.md §6.3"; exit 1 ;; \
	 esac
	@echo "Prerequisiti OK."
