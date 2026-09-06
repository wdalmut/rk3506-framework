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

# ---------------------------------------------------------------------------
# /etc/fw_env.config
# ---------------------------------------------------------------------------
# Dice a fw_printenv/fw_setenv dove sta l'ambiente. E' GENERATO, non tenuto
# allineato a mano: gli stessi offset stanno in parameter.txt (e quindi nella
# GPT, e quindi in /proc/mtd) e in uboot.config. Se divergessero, fw_setenv
# "riuscirebbe" e U-Boot leggerebbe un'altra area — nessun errore, solo un
# ambiente che non torna. post-image.sh verifica gli altri due lati.
#
# Una riga per copia, cioe' una per partizione: e' cosi' che le due semantiche
# di skip dei blocchi guasti coincidono. fw_env su un device MTD_NANDFLASH usa
# lo schema FLAG_INCREMENTAL — lo stesso serial byte che scrive env_export() —
# e salta i blocchi guasti entro il numero di settori dichiarato qui.
#
# Il file si genera solo se fw_printenv e' nel .config: un fork che non lo
# vuole non deve trovarsi un file che punta a partizioni che non usa.
if grep -q '^BR2_PACKAGE_UBOOT_TOOLS_FWPRINTENV=y$' "${BR2_CONFIG:-/dev/null}"; then
	# shellcheck source=flash-layout.sh
	. "$BOARD_DIR/flash-layout.sh"

	# CONFIG_ENV_SIZE viene da U-Boot, non si cabla: post-image.sh ha gia'
	# verificato che ci stia dentro la partizione.
	#
	# La leggibilita' si controlla PRIMA di leggere, non affidandosi a un
	# valore vuoto lasciato da un comando fallito: sotto "set -euo pipefail"
	# un sed su un file inesistente fa fallire l'intera pipeline (il
	# "2>/dev/null" di prima sopprimeva solo il messaggio, non lo stato di
	# uscita) e "set -e" avrebbe ucciso lo script qui, in silenzio, prima di
	# arrivare ai due rami sotto che devono gestire proprio questo caso.
	uboot_ver="$(sed -n 's/^BR2_TARGET_UBOOT_CUSTOM_REPO_VERSION="\(.*\)"$/\1/p' "$BR2_CONFIG")"
	uboot_autoconf="${BASE_DIR:-}/build/uboot-$uboot_ver/include/generated/autoconf.h"
	if [ -r "$uboot_autoconf" ]; then
		env_size="$(sed -n 's/^#define CONFIG_ENV_SIZE \(.*\)$/\1/p' "$uboot_autoconf" | tail -1)"
	else
		env_size=""
	fi

	# flash_layout emette tutto o niente e il suo stato di uscita si perde
	# dentro una process substitution: si raccoglie qui. Un fw_env.config
	# troncato punterebbe a partizioni sbagliate senza dirlo a nessuno.
	layout="$(flash_layout "$BOARD_DIR/parameter.txt")" || {
		echo "post-build.sh: parameter.txt non parsabile, /etc/fw_env.config non generato" >&2
		exit 1
	}

	if [ -z "$env_size" ] && ! grep -q '^BR2_TARGET_UBOOT=y$' "$BR2_CONFIG"; then
		# Un fork che tiene fw_printenv ma toglie U-Boot dal build: non c'e'
		# un CONFIG_ENV_SIZE da leggere e non e' un errore.
		echo "post-build.sh: U-Boot non e' nel build, /etc/fw_env.config non generato" >&2
	elif [ -z "$env_size" ]; then
		# Qui invece U-Boot c'e' e l'header non si legge: un fw_env.config
		# mancante non da' sintomi fino alla board, quindi si muore adesso.
		echo "post-build.sh: CONFIG_ENV_SIZE non leggibile da" >&2
		echo "               $uboot_autoconf" >&2
		echo "               /etc/fw_env.config non puo' essere generato." >&2
		exit 1
	else
		# 'env' ed 'env_r' devono essere dichiarate per nome: flash_layout da
		# solo non lo garantisce, filtra soltanto la sintassi di mtdparts=.
		# Senza questo controllo un parameter.txt senza le due partizioni
		# produrrebbe un fw_env.config con la sola intestazione e zero righe
		# dati — lo stesso guasto silenzioso che questo file esiste per
		# eliminare (vedi post-image.sh, che fa lo stesso controllo con
		# flash_part per lo stesso motivo).
		for p in env env_r; do
			flash_part "$BOARD_DIR/parameter.txt" "$p" >/dev/null || {
				echo "post-build.sh: parameter.txt non dichiara la partizione '$p'," >&2
				echo "               /etc/fw_env.config non puo' essere generato." >&2
				exit 1
			}
		done

		{
			echo "# Generato da board/lyra-plus/post-build.sh da parameter.txt."
			echo "# NON modificare a mano: gli offset devono restare quelli"
			echo "# della GPT e di uboot.config."
			printf '# %-16s %-8s %-9s %-12s %s\n' \
				Device Offset Env.size 'Sector size' '#sectors'
			while IFS=$'\t' read -r idx name _off size; do
				case "$name" in env|env_r) ;; *) continue ;; esac
				printf '/dev/mtd%-10s %-8s %-9s %-12s %s\n' \
					"$idx" 0x0000 \
					"$(printf '0x%x' "$(( env_size ))")" \
					"$(printf '0x%x' "$LYRA_ERASE_BLOCK")" \
					"$(( size / LYRA_ERASE_BLOCK ))"
			done <<<"$layout"
		} > "$TARGET_DIR/etc/fw_env.config"
	fi
fi
