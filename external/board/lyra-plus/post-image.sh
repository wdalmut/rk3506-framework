#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 Corley S.r.l.
#
# post-image.sh — riproduce la catena di packaging Rockchip che build.sh
# esegue dopo la compilazione, e che Buildroot non conosce.
#
# Riferimento: docs/BOARD-FACTS.md §1c, ricostruito dai trace in docs/traces/,
# prodotti con `env SHELLOPTS=xtrace bash ./build.sh` sull'SDK Luckfox.
# Ogni passo qui sotto cita la riga del trace da cui e' stato derivato.
#
# Ordine (identico a quello dell'SDK):
#   1. loader + uboot.img   <- u-boot/scripts/fit.sh -> rkbin: boot_merger, mkimage
#   2. resource.img         <- kernel/scripts/resource_tool
#   3. boot.img (FIT)       <- rkbin/tools/mkimage -f boot.its -E -p 0x800
#   4. rootfs.ubi           <- gia' prodotto da Buildroot (fs/ubi + fs/ubifs)
#   5. update.img           <- afptool -pack + rkImageMaker -RK350F
#   6. flash.img            <- genimage (immagine raw full-chip, extra)
#
set -euo pipefail

BINARIES_DIR="${1:?post-image.sh: manca BINARIES_DIR}"
BOARD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${BASE_DIR}/build"

msg()  { printf '\n>>> lyra-plus: %s\n' "$*"; }
warn() { printf '\n!!! lyra-plus: %s\n' "$*" >&2; }
die()  { printf '\n*** lyra-plus: %s\n' "$*" >&2; exit 1; }

# Legge una stringa dal .config di Buildroot.
cfg() {
	sed -n "s/^$1=\"\\(.*\\)\"$/\\1/p; s/^$1=\\([^\"].*\\)$/\\1/p" "$BR2_CONFIG" | tail -1
}

RKBIN_DIR="$(cfg BR2_LYRA_RKBIN_DIR)"
PACKTOOL_DIR="$(cfg BR2_LYRA_PACKTOOL_DIR)"

# Buildroot esporta agli script post-image solo BR2_CONFIG, BASE_DIR,
# HOST_DIR, TARGET_DIR e BINARIES_DIR (buildroot/Makefile:504-510).
# Il prefisso della cross-toolchain non c'e': lo ricaviamo da host/bin.
TARGET_CC="$(ls "$HOST_DIR"/bin/*-linux-*-gcc 2>/dev/null | head -1)"
[ -n "$TARGET_CC" ] || die "toolchain target non trovata in $HOST_DIR/bin"
TARGET_CROSS="${TARGET_CC%gcc}"

# Nome del DTB: in-tree per lyra_plus_defconfig, custom per la variante
# initramfs. Uno solo dei due e' impostato.
DTB_NAME="$(cfg BR2_LINUX_KERNEL_INTREE_DTS_NAME)"
if [ -z "$DTB_NAME" ]; then
	CUSTOM_DTS="$(cfg BR2_LINUX_KERNEL_CUSTOM_DTS_PATH)"
	DTB_NAME="$(basename "${CUSTOM_DTS%.dts}")"
fi
[ -n "$DTB_NAME" ] || die "non riesco a determinare il nome del DTB dal .config"

# ---------------------------------------------------------------------------
# 0. Validazione delle dipendenze binarie vendor
# ---------------------------------------------------------------------------
# Requisito: "il blob DDR e' binario, dipendenza dichiarata con path
# configurabile, non copiato alla cieca". Qui il path e' configurabile
# (BR2_LYRA_RKBIN_DIR), la presenza e' verificata e il contenuto e'
# confrontato con gli sha256 registrati in rkbin.sha256.

[ -n "$RKBIN_DIR" ] || die "BR2_LYRA_RKBIN_DIR non impostato (make menuconfig -> Luckfox Lyra Plus)"
[ -d "$RKBIN_DIR" ] || die "BR2_LYRA_RKBIN_DIR punta a '$RKBIN_DIR', che non esiste"

for f in RKBOOT/RK3506MINIALL.ini RKTRUST/RK3506TOS.ini \
         tools/boot_merger tools/mkimage \
         bin/rk35/rk3506_ddr_750MHz_v1.04.bin; do
	[ -e "$RKBIN_DIR/$f" ] || die "manca '$f' in '$RKBIN_DIR' (rkbin sbagliato o incompleto?)"
done

msg "verifica sha256 dei blob rkbin"
if ! ( cd "$RKBIN_DIR" && sha256sum -c --quiet "$BOARD_DIR/rkbin.sha256" ); then
	if [ "${LYRA_ALLOW_RKBIN_MISMATCH:-0}" = 1 ]; then
		warn "sha256 rkbin NON corrispondenti, proseguo perche' LYRA_ALLOW_RKBIN_MISMATCH=1"
	else
		die "sha256 dei blob rkbin diversi da quelli attesi.
    Atteso il checkout rkbin al tag linux-6.1-stan-rkr4.2
    (sha 32ccaf811ae70ce050aa810869c63c2b34324d59).
    Se l'aggiornamento e' voluto: aggiorna board/lyra-plus/rkbin.sha256
    e ripeti, oppure forza con LYRA_ALLOW_RKBIN_MISMATCH=1."
	fi
fi

# ---------------------------------------------------------------------------
# 1. Loader (MiniLoaderAll.bin) e uboot.img
# ---------------------------------------------------------------------------
# u-boot/make.sh vuole rkbin come directory FRATELLO: prepare() controlla
# `-d ../rkbin` e aborta con "ERROR: No ../rkbin repository" (make.sh:105).
UBOOT_DIR="$(find "$BUILD_DIR" -maxdepth 1 -type d -name 'uboot-*' | head -1)"
[ -n "$UBOOT_DIR" ] || die "directory di build di U-Boot non trovata sotto $BUILD_DIR"

# Serve una COPIA, non un symlink: la catena vendor scrive dentro rkbin.
# spl.sh fa `rm tmp -rf && mkdir tmp -p` nella radice di rkbin
# (scripts/spl.sh:54), ci copia lo SPL e l'ini, e boot_merger ci deposita
# il loader prodotto prima che make.sh lo sposti via. Con l'SDK montato
# read-only si ottiene:
#     mkdir: cannot create directory 'tmp': Read-only file system
# Sono 57 MB, la copia costa poco e tiene il checkout puntato da
# BR2_LYRA_RKBIN_DIR davvero intatto.
msg "copia di lavoro di rkbin in $BUILD_DIR/rkbin"
# rm -rf su un symlink rimuove il link, non il bersaglio: serve a non
# scriverci attraverso se una versione precedente ne aveva lasciato uno.
[ -L "$BUILD_DIR/rkbin" ] && rm -f "$BUILD_DIR/rkbin"
mkdir -p "$BUILD_DIR/rkbin"
rsync -a --delete "$RKBIN_DIR"/ "$BUILD_DIR/rkbin"/

# Il chip si legge dal .config di U-Boot, non si cabla.
UBOOT_CHIP="$(sed -n 's/^CONFIG_ROCKCHIP_\(RK[0-9A-Z]*\)=y$/\1/p' "$UBOOT_DIR/.config" | head -1)"
[ -n "$UBOOT_CHIP" ] || die "nessun CONFIG_ROCKCHIP_RK* in $UBOOT_DIR/.config"

# make.sh esegue select_toolchain() a ogni invocazione (make.sh:797), quindi
# anche nei sotto-comandi `itb` e `--spl` che fit.sh richiama al suo interno.
# Senza CROSS_COMPILE sulla riga di comando ripiega sul path hardcoded dei
# prebuilt dell'SDK (make.sh:15) e muore con "ERROR: No find ...gcc".
# Il meccanismo previsto e' il file cache ".cc" (make.sh:274-276): se c'e',
# select_toolchain() prende da li' il prefisso invece di indovinarlo.
# Glielo scriviamo con la toolchain di Buildroot.
printf '%s' "$TARGET_CROSS" > "$UBOOT_DIR/.cc"

msg "packing loader + uboot.img (scripts/fit.sh, chip $UBOOT_CHIP)"
(
	cd "$UBOOT_DIR"
	# Si chiama scripts/fit.sh direttamente invece di ./make.sh <board>,
	# per due motivi:
	#
	#  1. `./make.sh <board>` rifa' `make <board>_defconfig`, che
	#     sovrascriverebbe il .config gia' prodotto da Buildroot e
	#     butterebbe via il merge di uboot.config. Silenzioso e cattivo.
	#  2. fit.sh non ricompila: fit_raw_compile() ricostruisce solo con
	#     --sign (fit-core.sh:231-238). Quindi niente doppia build.
	#
	# E' esattamente l'invocazione che make.sh fa dopo aver compilato
	# (build-trace.log:4056), e make.sh non esporta variabili: fit.sh e'
	# un processo autonomo, quindi chiamarlo da qui e' equivalente.
	#
	# --spl-new sostituisce lo SPL prebuilt di rkbin (rk3506_spl_v1.10.bin)
	# con spl/u-boot-spl.bin appena compilato da Buildroot.
	./scripts/fit.sh --spl-new \
		--ini-trust  "$RKBIN_DIR/RKTRUST/RK3506TOS.ini" \
		--ini-loader "$RKBIN_DIR/RKBOOT/RK3506MINIALL.ini" \
		--chip "$UBOOT_CHIP"
)

LOADER="$(ls "$UBOOT_DIR"/*_loader_*.bin 2>/dev/null | head -1)"
[ -n "$LOADER" ] || die "fit.sh non ha prodotto *_loader_*.bin in $UBOOT_DIR"
[ -f "$UBOOT_DIR/uboot.img" ] || die "fit.sh non ha prodotto uboot.img in $UBOOT_DIR"

install -m 0644 "$LOADER"             "$BINARIES_DIR/MiniLoaderAll.bin"
install -m 0644 "$UBOOT_DIR/uboot.img" "$BINARIES_DIR/uboot.img"
# trust.img non esiste in questa configurazione: OP-TEE e' dentro il FIT di
# uboot.img (firmware = "optee"), perche' CONFIG_ROCKCHIP_FIT_IMAGE_PACK=y.
[ ! -f "$UBOOT_DIR/trust.img" ] || install -m 0644 "$UBOOT_DIR/trust.img" "$BINARIES_DIR/trust.img"

# ---------------------------------------------------------------------------
# 2. resource.img  (build-trace.log:8938)
# ---------------------------------------------------------------------------
LINUX_DIR="$(find "$BUILD_DIR" -maxdepth 1 -type d -name 'linux-*' ! -name 'linux-headers*' | head -1)"
[ -n "$LINUX_DIR" ] || die "directory di build del kernel non trovata sotto $BUILD_DIR"

RESOURCE_TOOL="$LINUX_DIR/scripts/resource_tool"
[ -x "$RESOURCE_TOOL" ] || die "scripts/resource_tool non compilato in $LINUX_DIR
    (e' hostprogs-always-\$(CONFIG_ARCH_ROCKCHIP): il kernel non e' quello vendor?)"

DTB="$LINUX_DIR/arch/arm/boot/dts/${DTB_NAME}.dtb"
[ -f "$DTB" ] || die "DTB non trovato: $DTB"

WORK="$BUILD_DIR/lyra-plus-image"
rm -rf "$WORK"; mkdir -p "$WORK"

msg "resource.img (dtb: ${DTB_NAME}.dtb)"
(
	cd "$WORK"
	# resource_tool scrive resource.img nella cwd. I logo sono opzionali:
	# scripts/mkimg li aggiunge solo se presenti nel sorgente del kernel.
	LOGOS=()
	for l in logo.bmp logo_kernel.bmp; do
		[ -f "$LINUX_DIR/$l" ] && { cp -f "$LINUX_DIR/$l" .; LOGOS+=("$l"); }
	done
	"$RESOURCE_TOOL" "$DTB" "${LOGOS[@]+"${LOGOS[@]}"}" >/dev/null
)
[ -f "$WORK/resource.img" ] || die "resource_tool non ha prodotto resource.img"

# ---------------------------------------------------------------------------
# 3. boot.img — FIT  (build-trace.log:8980-8985)
# ---------------------------------------------------------------------------
# Stessa logica di device/rockchip/common/scripts/mk-fitimage.sh: sostituisce
# i placeholder @KERNEL_*@ nell'.its e chiama il mkimage di rkbin.
# -E: dati esterni al FDT. -p 0x800: offset di partenza dei dati.
msg "boot.img (FIT: zImage + fdt + resource)"
ITS="$WORK/boot.its"
sed -e "s~@KERNEL_DTB@~$(readlink -f "$DTB")~" \
    -e "s~@KERNEL_IMG@~$(readlink -f "$LINUX_DIR/arch/arm/boot/zImage")~" \
    -e "s~@RAMDISK_IMG@~~" \
    -e "s~@RESOURCE_IMG@~$(readlink -f "$WORK/resource.img")~" \
    "$BOARD_DIR/boot.its" > "$ITS"

"$RKBIN_DIR/tools/mkimage" -f "$ITS" -E -p 0x800 "$BINARIES_DIR/boot.img" >/dev/null
[ -f "$BINARIES_DIR/boot.img" ] || die "mkimage non ha prodotto boot.img"

# ---------------------------------------------------------------------------
# 4. rootfs.img e parameter.txt
# ---------------------------------------------------------------------------
INITRAMFS=0
grep -q '^BR2_TARGET_ROOTFS_INITRAMFS=y' "$BR2_CONFIG" && INITRAMFS=1

install -m 0644 "$BOARD_DIR/parameter.txt" "$BINARIES_DIR/parameter.txt"

if [ "$INITRAMFS" = 1 ]; then
	# Il rootfs e' dentro zImage, quindi dentro boot.img: nessuna
	# partizione rootfs da scrivere.
	msg "variante initramfs: nessun rootfs.img (il rootfs e' incorporato in boot.img)"
	rm -f "$BINARIES_DIR/rootfs.img"
else
	[ -f "$BINARIES_DIR/rootfs.ubi" ] || die "rootfs.ubi non prodotto da Buildroot"
	# Rockchip si aspetta rootfs.img; Buildroot produce rootfs.ubi.
	cp -f "$BINARIES_DIR/rootfs.ubi" "$BINARIES_DIR/rootfs.img"
fi

# Controllo che l'SDK fa in mk-firmware.sh:52-64: ogni immagine deve entrare
# nella partizione dichiarata in parameter.txt.
msg "verifica dimensioni contro parameter.txt"
python3 - "$BINARIES_DIR/parameter.txt" "$BINARIES_DIR" <<'PYEOF'
import re, sys, os
param, bindir = sys.argv[1], sys.argv[2]
line = next(l for l in open(param) if l.startswith('CMDLINE'))
parts = line.split('mtdparts=', 1)[1].split(':', 1)[1].strip()
total = None
rc = 0
for ent in parts.split(','):
    m = re.match(r'(-|0x[0-9a-fA-F]+)@(0x[0-9a-fA-F]+)\(([^):]+)', ent)
    if not m:
        continue
    size, off, name = m.group(1), int(m.group(2), 16), m.group(3)
    img = os.path.join(bindir, name + '.img')
    if not os.path.exists(img):
        print(f"    {name:8} (nessuna {name}.img, salto)")
        continue
    fsz = os.path.getsize(img)
    if size == '-':
        print(f"    {name:8} {fsz/2**20:8.2f} MiB  -> partizione 'grow', nessun limite fisso")
        continue
    lim = int(size, 16) * 512
    ok = 'OK' if fsz <= lim else 'TROPPO GRANDE'
    print(f"    {name:8} {fsz/2**20:8.2f} MiB / {lim/2**20:8.2f} MiB  {ok}")
    if fsz > lim:
        rc = 1
sys.exit(rc)
PYEOF

# ---------------------------------------------------------------------------
# 5. update.img  (build-trace-pack.log:3109-3130)
# ---------------------------------------------------------------------------
AFPTOOL="$PACKTOOL_DIR/afptool"
RKIMAGEMAKER="$PACKTOOL_DIR/rkImageMaker"

if [ -n "$PACKTOOL_DIR" ] && [ -x "$AFPTOOL" ] && [ -x "$RKIMAGEMAKER" ]; then
	msg "update.img (afptool + rkImageMaker)"
	PACK="$WORK/update"
	rm -rf "$PACK"; mkdir -p "$PACK"

	# package-file, generato come gen_package_file() di mk-updateimg.sh.
	{
		printf '# NAME\tPATH\n'
		printf 'package-file\tpackage-file\n'
		printf 'parameter\tparameter.txt\n'
		printf 'bootloader\tMiniLoaderAll.bin\n'
	} > "$PACK/package-file"

	cp -f "$BINARIES_DIR/parameter.txt" "$BINARIES_DIR/MiniLoaderAll.bin" "$PACK/"
	for p in uboot boot rootfs; do
		if [ -f "$BINARIES_DIR/$p.img" ]; then
			cp -f "$BINARIES_DIR/$p.img" "$PACK/"
			printf '%s\t%s.img\n' "$p" "$p" >> "$PACK/package-file"
		fi
	done

	(
		cd "$PACK"
		# Il tag e' letto dal loader stesso: 4 byte a offset 21, invertiti.
		# Per RK3506 vale RK350F, come NAME= in RK3506MINIALL.ini.
		TAG="RK$(hexdump -s 21 -n 4 -e '4 "%c"' MiniLoaderAll.bin | rev)"
		"$AFPTOOL" -pack ./ update.raw.img
		"$RKIMAGEMAKER" "-$TAG" MiniLoaderAll.bin update.raw.img update.img \
			-os_type:androidos
	)
	install -m 0644 "$PACK/update.img" "$BINARIES_DIR/update.img"
else
	warn "update.img SALTATO: afptool/rkImageMaker non trovati in '$PACKTOOL_DIR'.
    Sono nel repository 'tools' dell'SDK Luckfox, non in rkbin:
      tools/linux/Linux_Pack_Firmware/rockdev/
    Imposta BR2_LYRA_PACKTOOL_DIR. Le immagini per partizione restano
    flashabili singolarmente con rkdeveloptool (vedi README)."
	rm -f "$BINARIES_DIR/update.img"
fi

# ---------------------------------------------------------------------------
# 6. flash.img — immagine raw full-chip (extra, non prodotta dall'SDK)
# ---------------------------------------------------------------------------
# Utile per un programmatore NAND esterno o per ispezionare il layout:
# mette ogni immagine all'offset esatto dichiarato in parameter.txt.
if [ "$INITRAMFS" = 0 ] && [ -x "$HOST_DIR/bin/genimage" ]; then
	msg "flash.img (genimage, layout da parameter.txt)"
	GENIMAGE_TMP="$BUILD_DIR/genimage.tmp"
	rm -rf "$GENIMAGE_TMP"
	mkdir -p "$WORK/empty-root"
	"$HOST_DIR/bin/genimage" \
		--rootpath "$WORK/empty-root" \
		--tmppath "$GENIMAGE_TMP" \
		--inputpath "$BINARIES_DIR" \
		--outputpath "$BINARIES_DIR" \
		--config "$BOARD_DIR/genimage.cfg"
fi

# ---------------------------------------------------------------------------
msg "artefatti in $BINARIES_DIR"
for f in MiniLoaderAll.bin uboot.img boot.img rootfs.img update.img flash.img; do
	[ -f "$BINARIES_DIR/$f" ] || continue
	printf '    %-20s %12d B  magic=%s\n' \
		"$f" "$(stat -c%s "$BINARIES_DIR/$f")" \
		"$(hexdump -n 4 -e '4/1 "%02x "' "$BINARIES_DIR/$f")"
done
echo
