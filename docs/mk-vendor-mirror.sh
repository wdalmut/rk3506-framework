#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 Corley S.r.l.
#
# mk-vendor-mirror.sh — ricostruisce kernel e U-Boot vendor come repository
# git autonomi, pubblicabili su GitHub.
#
# PERCHE' SERVE
# -------------
# I progetti dell'SDK Luckfox sono clonati con `clone-depth="1"` (attributo su
# ogni <project> del manifest). Un clone shallow ha i parent del suo unico
# commit "tagliati", e GitHub rifiuta i push da repository shallow:
#
#     ! [remote rejected] ... (shallow update not allowed)
#
# Non e' aggirabile lato client: serve `receive.shallowUpdate=true` sul server,
# che GitHub non espone.
#
# COSA FA QUESTO SCRIPT
# ---------------------
# Ricrea il commit come **commit senza parent** (root commit), riutilizzando
# l'oggetto tree originale. Il tree e' lo stesso oggetto git, quindi il
# contenuto e' identico bit per bit al commit vendor: stessi path, stessi mode,
# stessi blob. Cambia solo lo SHA del commit, perche' cambiano i parent.
#
# Lo script lo verifica da solo e si ferma se il tree non combacia.
#
# Autore, email e date sono quelli del commit vendor, quindi lo SHA prodotto e'
# **deterministico**: rieseguire lo script da' sempre lo stesso risultato.
#
# COSA NON FA
# -----------
# Non tocca l'SDK. Legge gli oggetti in sola lettura via `objects/info/
# alternates`, e alla fine fa `repack` per rendersi autonomo.
#
# Non include le modifiche locali non committate presenti nel checkout SDK
# (per il kernel: rk3506-luckfox-lyra.dtsi modificato, rk3506g-corley-lyra-plus.dts
# e miranda_amp.config non tracciati). E' voluto: il mirror deve corrispondere
# al baseline vendor. Quelle modifiche, se servono, vanno come patch numerate
# in external/board/lyra-plus/patches/linux/.
#
# E IL VENDOR KIT?
# ----------------
# Questo script rigenera i mirror di kernel e U-Boot. Il terzo mirror,
# github.com/wdalmut/rk3506-vendor-kit (submodule `vendor`), non c'entra con
# il problema dello shallow: sono file, non storia git. Si rifa' cosi', da un
# checkout dell'SDK:
#
#     cd <vendor-kit>
#     rm -rf rkbin packtool && mkdir -p rkbin packtool
#     cp -a "$SDK/rkbin/." rkbin/ && rm -rf rkbin/.git
#     cp -a "$SDK/tools/linux/Linux_Pack_Firmware/rockdev/"{afptool,rkImageMaker} packtool/
#
# Poi in questo repository va rigenerato
# external/board/lyra-plus/rkbin.sha256, perche' post-image.sh verifica gli
# sha256 a ogni build e si ferma se non combaciano.
#
# ALTERNATIVA MIGLIORE, SE HAI ACCESSO ALLA RETE DI ORIGINE
# ---------------------------------------------------------
# Se riesci a raggiungere ssh://git@192.168.10.75/, non serve niente di tutto
# questo: basta ripristinare la storia vera e pushare, mantenendo lo SHA
# vendor e lasciando i defconfig invariati.
#
#     git -C <sdk>/kernel-6.1 fetch --unshallow rk
#     git -C <sdk>/kernel-6.1 push https://github.com/<tu>/rk3506-kernel.git \
#         696a8549d1a582337c8032c02a2aea35790047a4:refs/heads/luckfox-linux-6.1-rk3506
#
set -euo pipefail

SDK_DIR="${SDK_DIR:-$HOME/git/luckfox-lyra}"
OUT_DIR="${OUT_DIR:-$HOME/git}"
BRANCH="luckfox-linux-6.1-rk3506"

# progetto : path nell'SDK : path objects sotto .repo/project-objects : sha vendor
PROJECTS=(
  "rk3506-kernel:kernel-6.1:rk/kernel.git:696a8549d1a582337c8032c02a2aea35790047a4"
  "rk3506-uboot:u-boot:android/rk/u-boot.git:4d88b0a83c87488f343fb4cc4f56ffc598b2e0a3"
)

ok()   { printf '  \033[32mok\033[0m    %s\n' "$*"; }
info() { printf '  \033[36m..\033[0m    %s\n' "$*"; }
die()  { printf '  \033[31merrore\033[0m %s\n' "$*" >&2; exit 1; }

[ -d "$SDK_DIR" ] || die "SDK non trovato in '$SDK_DIR' (usa SDK_DIR=...)"

for entry in "${PROJECTS[@]}"; do
	IFS=: read -r NAME SDKPATH OBJPATH SHA <<<"$entry"
	DEST="$OUT_DIR/$NAME"

	echo
	echo "### $NAME  (da $SDKPATH @ ${SHA:0:12})"

	SRC="$SDK_DIR/$SDKPATH"
	[ -d "$SRC" ] || die "manca $SRC"

	OBJ="$SDK_DIR/.repo/project-objects/$OBJPATH/objects"
	[ -d "$OBJ" ] || die "manca l'object store $OBJ"

	# Tree e metadati del commit vendor, letti dall'SDK.
	TREE="$(git -C "$SRC" rev-parse "$SHA^{tree}")"
	SUBJECT="$(git -C "$SRC" log -1 --format=%s "$SHA")"
	export GIT_AUTHOR_NAME="$(git -C "$SRC" log -1 --format=%an "$SHA")"
	export GIT_AUTHOR_EMAIL="$(git -C "$SRC" log -1 --format=%ae "$SHA")"
	export GIT_AUTHOR_DATE="$(git -C "$SRC" log -1 --format=%aI "$SHA")"
	export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
	export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
	export GIT_COMMITTER_DATE="$(git -C "$SRC" log -1 --format=%cI "$SHA")"
	info "tree vendor: $TREE"

	[ ! -e "$DEST" ] || die "$DEST esiste gia': spostalo o cancellalo prima"
	git init -q -b "$BRANCH" "$DEST"
	cd "$DEST"

	# Sola lettura sull'object store dell'SDK, il tempo di creare il commit.
	echo "$OBJ" > .git/objects/info/alternates
	git cat-file -e "$SHA" 2>/dev/null || die "il commit $SHA non e' visibile in $OBJ"

	NEW="$(git commit-tree "$TREE" -m "$SUBJECT

Mirror del commit $SHA
del ramo $BRANCH, SDK Luckfox v1.4
(manifest luckfox_linux6.1_rk3506_release_v1.4_20250620.xml).

Origine: ssh://git@192.168.10.75/RK3506_Linux610_mirror_241206/${OBJPATH%.git}
Il clone dell'SDK e' depth=1, quindi la storia originale non e'
ripubblicabile. Questo commit non ha parent, ma riusa lo stesso oggetto
tree del commit vendor, percio' il contenuto e' identico bit per bit:

    tree $TREE

Verifica:
    git rev-parse HEAD^{tree}   ->  $TREE")"

	git update-ref "refs/heads/$BRANCH" "$NEW"
	git tag -a "vendor-${SHA:0:12}" "$NEW" \
		-m "Contenuto del commit vendor $SHA" >/dev/null

	# Rende il repository autonomo: copia in un pack locale tutti gli oggetti
	# raggiungibili, poi stacca l'alternate.
	info "repack (puo' richiedere qualche minuto sul kernel)"
	git repack -a -d -q
	rm -f .git/objects/info/alternates

	# Verifiche: niente shallow, integrita', e soprattutto tree invariato.
	[ "$(git rev-parse --is-shallow-repository)" = false ] || die "$NAME risulta ancora shallow"
	git fsck --no-dangling --no-progress >/dev/null 2>&1 || die "$NAME non passa fsck"
	[ "$(git rev-parse HEAD^{tree})" = "$TREE" ] || die "$NAME: il tree non combacia!"

	git reset -q --hard "$BRANCH"

	ok "$DEST"
	ok "commit  $NEW"
	ok "tree    $TREE  (identico al vendor)"
	ok "file    $(git ls-files | wc -l)   dimensione .git $(du -sh .git | cut -f1)"

	echo
	echo "  Per pubblicarlo:"
	echo "      cd $DEST"
	echo "      gh repo create $NAME --public --source=. --remote=origin \\"
	echo "          --description 'Mirror ${SDKPATH} da SDK Luckfox v1.4 per RK3506G2 (Lyra Plus)'"
	echo "      git push -u origin $BRANCH"
	echo "      git push origin vendor-${SHA:0:12}"
	echo
	echo "  Poi nel defconfig, al posto di $SHA:"
	echo "      $NEW"
done

echo
echo "Ricorda: gli SHA nei defconfig cambiano, perche' cambiano i parent."
echo "Aggiornali in entrambi:"
echo "    external/configs/lyra_plus_defconfig"
echo "    external/configs/lyra_plus_initramfs_defconfig"
echo "e in docs/BOARD-FACTS.md e README.md, dove sono citati come provenienza."
