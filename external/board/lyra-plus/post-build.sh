#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 Corley S.r.l.
#
# post-build.sh — ritocchi al TARGET_DIR prima che venga impacchettato.
# Gira dentro fakeroot, dopo l'overlay e dopo l'install dei package.
#
set -euo pipefail

TARGET_DIR="${1:?post-build.sh: manca TARGET_DIR}"
BOARD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# git non conserva i permessi oltre il bit +x, e BR2_ROOTFS_OVERLAY copia
# cosi' com'e': ci assicuriamo che gli script init siano eseguibili.
if [ -d "$TARGET_DIR/etc/init.d" ]; then
	find "$TARGET_DIR/etc/init.d" -type f -name 'S??*' -exec chmod 0755 {} +
fi

# Traccia di cosa e' stato costruito: utile quando sulla scrivania ci sono
# tre board con tre immagini diverse.
{
	echo "BOARD=lyra-plus"
	echo "SOC=rk3506g2"
	echo "BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	if [ -r "${BR2_CONFIG:-/dev/null}" ]; then
		sed -n 's/^BR2_LINUX_KERNEL_CUSTOM_REPO_VERSION="\(.*\)"$/KERNEL_COMMIT=\1/p' "$BR2_CONFIG"
		sed -n 's/^BR2_TARGET_UBOOT_CUSTOM_REPO_VERSION="\(.*\)"$/UBOOT_COMMIT=\1/p' "$BR2_CONFIG"
	fi
} > "$TARGET_DIR/etc/lyra-release"

# Buildroot genera la riga di inittab da BR2_TARGET_GENERIC_GETTY_PORT, ma
# securetty non conosce le console fuori standard: senza la riga
# corrispondente, il login di root sulla seriale viene rifiutato
# ("root login refused on this terminal").
#
# La porta NON e' cablata, perche' questo script e' condiviso fra i
# defconfig e ognuno ha la sua console:
#
#   lyra_plus_defconfig            ttyFIQ0  fiq-debugger vendor su UART0
#   lyra_plus_initramfs_defconfig  ttyFIQ0  idem
#   lyra_plus_mainline_..._defconfig  ttyS0  mainline non ha il fiq-debugger
#                                           (CONFIG_FIQ_DEBUGGER e' vendor-only)
#
# NOTA, verificata su questo albero: /etc/securetty NON viene creato ne'
# dallo skeleton di Buildroot ne' da BusyBox, quindi oggi il blocco qui
# sotto e' un no-op in tutti e tre i defconfig e il login di root passa
# perche' `login` di BusyBox controlla securetty solo se il file esiste.
# Resta perche' basta un package (shadow, util-linux con login) per farlo
# comparire, e allora la riga giusta deve esserci: quando succedera' sara'
# quella della console effettiva, non "ttyFIQ0" cablato.
GETTY_PORT=""
if [ -r "${BR2_CONFIG:-/dev/null}" ]; then
	GETTY_PORT="$(sed -n 's/^BR2_TARGET_GENERIC_GETTY_PORT="\(.*\)"$/\1/p' "$BR2_CONFIG" | tail -1)"
fi

if [ -z "$GETTY_PORT" ]; then
	# Non e' fatale: significa solo che il login di root sulla seriale
	# potrebbe essere rifiutato. Meglio dirlo che fallire la build.
	echo "post-build.sh: BR2_TARGET_GENERIC_GETTY_PORT non leggibile, securetty non aggiornato" >&2
elif [ -f "$TARGET_DIR/etc/securetty" ] \
     && ! grep -qx "$GETTY_PORT" "$TARGET_DIR/etc/securetty"; then
	echo "$GETTY_PORT" >> "$TARGET_DIR/etc/securetty"
fi
