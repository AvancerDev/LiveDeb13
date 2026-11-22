# LiveDeb13 — Makefile
# Wrapper comodo attorno a live-build (lb). La build richiede root.

SHELL := /bin/bash
LB := lb
ISO := binary/live/livedeb13-amd64.iso

.PHONY: help config build clean distclean run run-uefi usb check iso

help: ## Mostra questo help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

config: ## Configura il build (lb config via auto/config)
	./auto/config

build: ## Compila l'ISO (richiede root)
	sudo ./auto/build

clean: ## Pulisce gli artefatti di build (lb clean)
	sudo ./auto/clean

distclean: ## Pulizia completa (lb clean --purge)
	sudo ./auto/clean --purge

iso: build ## Alias di build + mostra info ISO
	@echo "ISO pronta: $(ISO)"
	@ls -lh $(ISO) 2>/dev/null || echo "ISO non trovata, build fallita?"

run: iso ## Avvia l'ISO in QEMU (BIOS)
	qemu-system-x86_64 -m 2048 -cdrom $(ISO) -boot d -enable-kvm -vga std

run-uefi: iso ## Avvia l'ISO in QEMU (UEFI, richiede OVMF)
	qemu-system-x86_64 -m 2048 -cdrom $(ISO) -boot d -enable-kvm \
	  -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
	  -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_VARS_4M.fd

usb: iso ## Scrive l'ISO su USB (USB=/dev/sdX make usb)
	@if [ -z "$(USB)" ]; then echo "Uso: USB=/dev/sdX make usb"; exit 1; fi
	@echo "Scrittura su $(USB) — i dati saranno cancellati. Continuo tra 5s (Ctrl+C per annullare)..."
	@sleep 5
	sudo dd if=$(ISO) of=$(USB) bs=4M status=progress oflag=sync

check: ## Verifica prerequisiti (lb, debootstrap, xorriso…)
	@command -v $(LB) >/dev/null || (echo "ERRORE: live-build non installato. Vedi README."; exit 1)
	@command -v debootstrap >/dev/null || (echo "ERRORE: debootstrap non installato."; exit 1)
	@command -v xorriso >/dev/null || (echo "ERRORE: xorriso non installato."; exit 1)
	@echo "Prerequisiti OK."
