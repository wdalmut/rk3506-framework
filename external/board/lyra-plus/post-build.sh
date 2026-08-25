#!/usr/bin/env bash
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

# La console e' ttyFIQ0 (fiq-debugger Rockchip su UART0 @ 0xff0a0000).
# Buildroot genera la riga di inittab da BR2_TARGET_GENERIC_GETTY_PORT, ma
# securetty non lo conosce: senza questa riga il login di root sulla
# seriale viene rifiutato.
if [ -f "$TARGET_DIR/etc/securetty" ] && ! grep -qx 'ttyFIQ0' "$TARGET_DIR/etc/securetty"; then
	echo 'ttyFIQ0' >> "$TARGET_DIR/etc/securetty"
fi
