#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 Corley S.r.l.
#
# flash-layout.sh — parser unico di parameter.txt.
#
# Gli offset delle partizioni compaiono in piu' posti indipendenti:
# parameter.txt, la configurazione di U-Boot, il CONFIG_CMDLINE dei due
# fragment mainline, /etc/fw_env.config e genimage.cfg. Se divergono il
# sintomo e' subdolo (fw_setenv "riesce" e U-Boot legge altro), quindi
# parameter.txt e' la fonte unica e questo e' l'unico parser che la legge:
# fw_env.config e gli offset di genimage sono GENERATI da qui (post-build.sh e
# post-image.sh), U-Boot e il CONFIG_CMDLINE del kernel sono CONFRONTATI con
# questa fonte da post-image.sh (blocchi 1a e 2a), che uccide la build se
# divergono.
#
# La conversione settori (512 B) -> byte sta QUI e solo qui.
#
# Uso, sorgendolo:
#     . "$BOARD_DIR/flash-layout.sh"
#     flash_layout parameter.txt            # tutte le partizioni
#     flash_part   parameter.txt rootfs     # una sola
#
# Uso, eseguendolo (stampa la tabella, comodo a mano):
#     ./flash-layout.sh parameter.txt

# Erase block della SPI NAND. NON e' ricavabile da parameter.txt: e' un fatto
# della board, misurato. Fonte: docs/BOARD-FACTS.md.
export LYRA_ERASE_BLOCK=131072

# Unita' della riga CMDLINE di parameter.txt.
export LYRA_SECTOR=512

# flash_layout <parameter.txt>
#
# Stampa una riga per partizione, TAB-separata, nell'ordine di dichiarazione:
#     <indice mtd>  <nome>  <offset in byte>  <size in byte, oppure "grow">
flash_layout() {
	local param="$1"
	local parts ent size off name idx=0
	local output=()

	if [ ! -r "$param" ]; then
		printf 'flash-layout: parameter.txt non leggibile: %s\n' "$param" >&2
		return 1
	fi

	# La riga e':
	#     CMDLINE:mtdparts=<mtd-id>:<size>@<off>(<nome>[:flag]),...
	# L'mtd-id e' vuoto in questo repository, ma il parser non ci conta.
	parts="$(sed -n 's/^CMDLINE:.*mtdparts=[^:]*:\(.*\)$/\1/p' "$param" | tail -1)"
	parts="${parts%%[[:space:]]}"
	if [ -z "$parts" ]; then
		printf 'flash-layout: nessuna riga CMDLINE con mtdparts= in %s\n' "$param" >&2
		return 1
	fi

	local IFS=,
	for ent in $parts; do
		if [[ ! "$ent" =~ ^(-|0x[0-9a-fA-F]+)@(0x[0-9a-fA-F]+)\(([^\):]+) ]]; then
			printf 'flash-layout: voce mtdparts non riconosciuta: %s\n' "$ent" >&2
			return 1
		fi
		size="${BASH_REMATCH[1]}"
		off="${BASH_REMATCH[2]}"
		name="${BASH_REMATCH[3]}"

		if [ "$size" = - ]; then
			# "grow": la dimensione la calcola U-Boot a runtime, perche'
			# dipende da dove finisce la GPT di backup.
			output+=("$(printf '%d\t%s\t%d\tgrow' \
				"$idx" "$name" "$(( off * LYRA_SECTOR ))")")
		else
			output+=("$(printf '%d\t%s\t%d\t%d' \
				"$idx" "$name" "$(( off * LYRA_SECTOR ))" \
				"$(( size * LYRA_SECTOR ))")")
		fi
		idx=$(( idx + 1 ))
	done

	# Stampa solo dopo aver convalidato tutto.
	printf '%s\n' "${output[@]}"
}

# flash_part <parameter.txt> <nome>
#
# Stampa "<indice> <offset in byte> <size in byte|grow>" per una partizione.
# Ritorna 1 se flash_layout fallisce o se quel nome non e' dichiarato.
flash_part() {
	local output
	output="$(flash_layout "$1")" || return 1
	echo "$output" | awk -F'\t' -v n="$2" \
		'$2 == n { print $1, $3, $4; found = 1 } END { exit !found }'
}

# Eseguito direttamente: stampa la tabella.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
	param="${1:-}"
	if [ -z "$param" ]; then
		printf 'uso: %s <parameter.txt>\n' "$0" >&2
		exit 1
	fi
	printf '%-4s %-10s %14s %14s\n' idx nome offset size
	while IFS=$'\t' read -r idx name off size; do
		printf 'mtd%-1s %-10s %14s %14s\n' "$idx" "$name" "$off" "$size"
	done < <(flash_layout "$param")
fi
