#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 Corley S.r.l.
#
# setup.sh — prepara un clone pulito per la build.
#
# Fa tre cose, tutte idempotenti:
#   1. inizializza il submodule buildroot al tag LTS pinnato;
#   2. inizializza il submodule vendor, con i binari Rockchip non
#      ricompilabili (blob DDR, OP-TEE, boot_merger, mkimage, afptool);
#   3. costruisce l'immagine Docker di build.
#
# Dopo:  make lyra_plus_defconfig && make
#
set -euo pipefail

TOPDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SDK_DIR="${SDK_DIR:-$HOME/git/luckfox-lyra}"
IMAGE="${IMAGE:-rk3506-framework:build}"

ok()   { printf '  \033[32mok\033[0m    %s\n' "$*"; }
info() { printf '  \033[36m..\033[0m    %s\n' "$*"; }
warn() { printf '  \033[33mattenzione\033[0m %s\n' "$*" >&2; }
die()  { printf '  \033[31merrore\033[0m %s\n' "$*" >&2; exit 1; }

echo
echo "setup — rk3506-framework (Luckfox Lyra Plus / RK3506G2)"
echo

# --- 1. submodule Buildroot --------------------------------------------------
cd "$TOPDIR"
if [ ! -f buildroot/Makefile ]; then
	info "inizializzo il submodule buildroot (puo' richiedere qualche minuto)"
	git submodule update --init --depth 1 buildroot
fi
BR_VER="$(sed -n 's/^export BR2_VERSION := //p' buildroot/Makefile | head -1)"
[ -n "$BR_VER" ] || die "buildroot/ non sembra un checkout valido"
ok "buildroot $BR_VER"

case "$BR_VER" in
	*.02|*.02.*) : ;;  # le LTS Buildroot sono le release YYYY.02.x
	*) warn "buildroot $BR_VER non e' una LTS (le LTS sono le YYYY.02.x)" ;;
esac

# --- 2. binari vendor -------------------------------------------------------
# Non ricompilabili dai sorgenti: blob DDR, OP-TEE, boot_merger, mkimage,
# afptool, rkImageMaker. Stanno nel submodule `vendor`, estratti dall'SDK
# Luckfox: per costruire NON serve avere l'SDK (30 GB, di cui questi sono
# lo 0,2%).
if [ ! -e vendor/rkbin/RKBOOT/RK3506MINIALL.ini ]; then
	info "inizializzo il submodule vendor (62 MB)"
	git submodule update --init --depth 1 vendor
fi

MISSING=0
for f in rkbin/RKBOOT/RK3506MINIALL.ini \
         rkbin/RKTRUST/RK3506TOS.ini \
         rkbin/tools/boot_merger \
         rkbin/tools/mkimage \
         rkbin/bin/rk35/rk3506_ddr_750MHz_v1.04.bin \
         packtool/afptool \
         packtool/rkImageMaker; do
	[ -e "vendor/$f" ] || { warn "manca vendor/$f"; MISSING=1; }
done
[ "$MISSING" = 0 ] || die "il submodule vendor e' incompleto: git submodule update --init vendor"
ok "binari vendor in vendor/"

# Gli sha256 li verifica comunque post-image.sh a ogni build, ma dirlo qui
# evita di scoprire un kit sbagliato dopo mezz'ora di compilazione.
if (cd vendor/rkbin && sha256sum -c --quiet "$TOPDIR/external/board/lyra-plus/rkbin.sha256" 2>/dev/null); then
	ok "sha256 dei blob corrispondenti"
else
	warn "sha256 dei blob NON corrispondenti: post-image.sh si fermera'"
fi

# L'SDK non serve alla build. Resta utile solo per rigenerare i mirror con
# docs/mk-vendor-mirror.sh e per confrontare gli artefatti in check-artifacts.sh.
if [ -d "$SDK_DIR" ]; then
	ok "SDK trovato in $SDK_DIR (non serve per costruire, solo per i confronti)"
fi

# --- 3. immagine Docker ------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
	die "docker non trovato nel PATH"
fi

if docker image inspect "$IMAGE" >/dev/null 2>&1; then
	ok "immagine docker $IMAGE gia' presente (ricostruiscila con: make image)"
else
	info "costruisco l'immagine docker $IMAGE"
	docker build -t "$IMAGE" \
		--build-arg UID="$(id -u)" --build-arg GID="$(id -g)" \
		"$TOPDIR/docker"
	ok "immagine docker $IMAGE"
fi

cat <<EOF

Pronto. Prossimi passi:

    make lyra_plus_defconfig       # SPI NAND + UBIFS (immagine di produzione)
    make                           # build completa

oppure, per il primo bring-up senza dipendere dalla NAND:

    make lyra_plus_initramfs_defconfig
    make

Gli artefatti finiscono in output/images/.
Console seriale: ttyFIQ0 (UART0 @ 0xff0a0000), 1500000 8N1.

EOF
