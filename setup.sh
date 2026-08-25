#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 Corley S.r.l.
#
# setup.sh — prepara un clone pulito per la build.
#
# Fa tre cose, tutte idempotenti:
#   1. inizializza il submodule buildroot al tag LTS pinnato;
#   2. verifica che l'SDK Luckfox sia raggiungibile (serve per rkbin e per
#      i tool di packaging: sono binari vendor, non ricompilabili);
#   3. costruisce l'immagine Docker di build.
#
# Dopo:  make lyra_plus_defconfig && make
#
set -euo pipefail

TOPDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SDK_DIR="${SDK_DIR:-$HOME/git/luckfox-lyra}"
IMAGE="${IMAGE:-rk3506-framework:build}"

# Revisione rkbin attesa (manifest SDK Luckfox v1.4, tag linux-6.1-stan-rkr4.2).
RKBIN_SHA="32ccaf811ae70ce050aa810869c63c2b34324d59"

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

# --- 2. SDK Luckfox: dipendenze binarie vendor -------------------------------
# Non serve come build system — build.sh non viene mai lanciato — ma da qui
# arrivano il blob DDR e i tool di packaging Rockchip.
if [ ! -d "$SDK_DIR" ]; then
	die "SDK Luckfox non trovato in '$SDK_DIR'.
        Serve per rkbin (blob DDR, boot_merger, mkimage, OP-TEE) e per
        afptool/rkImageMaker. Indicane un altro con:
            SDK_DIR=/percorso/al/sdk ./setup.sh
        e poi:
            make SDK_DIR=/percorso/al/sdk ..."
fi

MISSING=0
for f in rkbin/RKBOOT/RK3506MINIALL.ini \
         rkbin/RKTRUST/RK3506TOS.ini \
         rkbin/tools/boot_merger \
         rkbin/tools/mkimage \
         rkbin/bin/rk35/rk3506_ddr_750MHz_v1.04.bin; do
	[ -e "$SDK_DIR/$f" ] || { warn "manca $SDK_DIR/$f"; MISSING=1; }
done
[ "$MISSING" = 0 ] || die "il checkout rkbin dentro l'SDK e' incompleto"
ok "rkbin trovato in $SDK_DIR/rkbin"

if [ -d "$SDK_DIR/rkbin/.git" ]; then
	HAVE="$(git -C "$SDK_DIR/rkbin" rev-parse HEAD 2>/dev/null || echo '?')"
	if [ "$HAVE" != "$RKBIN_SHA" ]; then
		warn "rkbin e' a $HAVE, atteso $RKBIN_SHA (tag linux-6.1-stan-rkr4.2)"
		warn "post-image.sh confrontera' comunque gli sha256 dei blob"
	else
		ok "rkbin al commit atteso"
	fi
fi

if [ -x "$SDK_DIR/tools/linux/Linux_Pack_Firmware/rockdev/afptool" ] &&
   [ -x "$SDK_DIR/tools/linux/Linux_Pack_Firmware/rockdev/rkImageMaker" ]; then
	ok "afptool + rkImageMaker trovati (update.img verra' generato)"
else
	warn "afptool/rkImageMaker non trovati: update.img verra' SALTATO.
        Tutti gli altri artefatti vengono prodotti lo stesso e restano
        flashabili per partizione con rkdeveloptool."
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
