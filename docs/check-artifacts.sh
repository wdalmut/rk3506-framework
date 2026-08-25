#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 Corley S.r.l.
#
# check-artifacts.sh — controlla che post-image.sh non abbia rotto la catena
# di packaging Rockchip.
#
# NON verifica che il sistema funzioni: quello lo dice il boot. Verifica gli
# invarianti di *forma* degli artefatti, cioe' le cose che si rompono in
# silenzio quando si alza lo SHA del kernel, si passa a un Buildroot nuovo, o
# si tocca post-image.sh, boot.its o parameter.txt. Il risultato e' un'immagine
# che si costruisce senza errori e non parte.
#
# post-image.sh controlla gia' due cose a ogni build: che ogni immagine entri
# nella sua partizione, e gli sha256 dei blob rkbin. Qui ci sono i controlli
# che non fa: struttura dei FIT, geometria UBI, offset in flash.img, contenuto
# di update.img.
#
# Uso:
#     docs/check-artifacts.sh [output/images]
#
# I pack tool servono al controllo 5 e vengono presi da vendor/packtool.
# Se in piu' e' disponibile un checkout dell'SDK Luckfox gia' costruito, viene
# fatto anche il confronto con i suoi artefatti:
#     SDK_DIR=~/git/luckfox-lyra docs/check-artifacts.sh
#
set -uo pipefail

IMG="${1:-output/images}"
SDK_DIR="${SDK_DIR:-}"

RC=0
pass() { printf '  \033[32mok\033[0m    %s\n' "$*"; }
fail() { printf '  \033[31mKO\033[0m    %s\n' "$*"; RC=1; }
skip() { printf '  \033[33m--\033[0m    %s\n' "$*"; }
head_() { printf '\n\033[1m%s\033[0m\n' "$*"; }

[ -d "$IMG" ] || { echo "directory immagini non trovata: $IMG" >&2; exit 2; }

need() { command -v "$1" >/dev/null 2>&1; }

magic() { hexdump -n 4 -e '4/1 "%02x "' "$1" 2>/dev/null | tr -d ' '; }

# ---------------------------------------------------------------------------
head_ "1. magic e dimensioni"
# ---------------------------------------------------------------------------
# uboot.img ha una dimensione FISSA e non negoziabile: e'
# CONFIG_SPL_FIT_IMAGE_MULTIPLE=2 copie del FIT paddate a
# CONFIG_SPL_FIT_IMAGE_KB=2048 => 4 MiB esatti, cioe' la partizione uboot.
# Se cambia, il FIT e' cresciuto oltre i 2 MiB e non ci sta piu'.
check_magic() {
    local f="$1" want="$2" desc="$3"
    [ -f "$IMG/$f" ] || { skip "$f assente"; return; }
    local got; got="$(magic "$IMG/$f")"
    if [ "$got" = "$want" ]; then
        pass "$(printf '%-18s %10d B  magic=%s (%s)' "$f" "$(stat -c%s "$IMG/$f")" "$got" "$desc")"
    else
        fail "$f: magic $got, atteso $want ($desc)"
    fi
}
check_magic MiniLoaderAll.bin 4c445220 "LDR , loader Rockchip"
check_magic uboot.img         d00dfeed "FIT"
check_magic boot.img          d00dfeed "FIT"
check_magic rootfs.img        55424923 "UBI#"
check_magic update.img        524b4657 "RKFW"

if [ -f "$IMG/uboot.img" ]; then
    SZ="$(stat -c%s "$IMG/uboot.img")"
    [ "$SZ" -eq 4194304 ] \
        && pass "uboot.img e' esattamente 4 MiB (2 x FIT paddati a 2048K)" \
        || fail "uboot.img e' $SZ B, atteso 4194304: il FIT ha superato i 2 MiB?"
fi

# ---------------------------------------------------------------------------
head_ "2. struttura interna dei FIT"
# ---------------------------------------------------------------------------
if ! need fdtget; then
    skip "fdtget assente (apt install device-tree-compiler), salto"
else
    fdt_has() {  # file, path, prop, atteso
        local got; got="$(fdtget "$1" "$2" "$3" 2>/dev/null)"
        [ "$got" = "$4" ] && pass "$(basename "$1") $2 $3 = $got" \
                          || fail "$(basename "$1") $2 $3 = '${got:-assente}', atteso '$4'"
    }
    if [ -f "$IMG/boot.img" ]; then
        # Deve rispecchiare board/lyra-plus/boot.its
        NODES="$(fdtget -l "$IMG/boot.img" /images 2>/dev/null | tr '\n' ' ' | xargs)"
        [ "$NODES" = "fdt kernel resource" ] \
            && pass "boot.img /images = $NODES" \
            || fail "boot.img /images = '$NODES', atteso 'fdt kernel resource'"
        fdt_has "$IMG/boot.img" /configurations/conf fdt    fdt
        fdt_has "$IMG/boot.img" /configurations/conf kernel kernel
        fdt_has "$IMG/boot.img" /configurations/conf multi  resource
        fdt_has "$IMG/boot.img" /images/kernel   compression none
        fdt_has "$IMG/boot.img" /images/kernel   arch        arm
        fdt_has "$IMG/boot.img" /images/resource type        multi
        # -p 0x800 passato a mkimage: i dati partono a 2048
        POS="$(fdtget -ti "$IMG/boot.img" /images/fdt data-position 2>/dev/null)"
        [ "$POS" = "2048" ] \
            && pass "boot.img primo data-position = 2048 (mkimage -p 0x800)" \
            || fail "boot.img data-position = '$POS', atteso 2048"
    else
        skip "boot.img assente"
    fi

    if [ -f "$IMG/uboot.img" ]; then
        # OP-TEE dentro il FIT come "firmware", U-Boot come "loadables":
        # e' questo che rende superfluo un trust.img separato.
        fdt_has "$IMG/uboot.img" /configurations/conf firmware  optee
        fdt_has "$IMG/uboot.img" /configurations/conf loadables uboot
        fdt_has "$IMG/uboot.img" /configurations/conf fdt       fdt
    else
        skip "uboot.img assente"
    fi
fi

# ---------------------------------------------------------------------------
head_ "3. geometria UBI"
# ---------------------------------------------------------------------------
# vid_hdr_offset=2048 e data_offset=4096 significano page 2048 B e PEB 128 KiB.
# Se cambiano, il rootfs non monta sulla NAND anche se l'immagine si costruisce.
if [ -f "$IMG/rootfs.img" ]; then
    python3 - "$IMG/rootfs.img" <<'PY'
import struct, sys
d = open(sys.argv[1], 'rb').read(32)
vid, data, seq = struct.unpack('>III', d[16:28])
ok = d[0:4] == b'UBI#' and vid == 2048 and data == 4096
print(("  \033[32mok\033[0m    " if ok else "  \033[31mKO\033[0m    ") +
      f"UBI vid_hdr_offset={vid} data_offset={data} "
      f"(attesi 2048/4096)  image_seq=0x{seq:08x}")
sys.exit(0 if ok else 1)
PY
    [ $? -eq 0 ] || RC=1
    # image_seq e' casuale a ogni ubinize: rootfs.img NON e' byte-riproducibile,
    # ed e' corretto cosi'. Mai confrontarlo per checksum.
else
    skip "rootfs.img assente"
fi

# ---------------------------------------------------------------------------
head_ "4. offset in flash.img"
# ---------------------------------------------------------------------------
if [ -f "$IMG/flash.img" ]; then
    python3 - "$IMG/flash.img" <<'PY'
import sys
f = open(sys.argv[1], 'rb')
rc = 0
for name, off, exp in (("uboot", 4<<20, b'\xd0\x0d\xfe\xed'),
                       ("boot",  8<<20, b'\xd0\x0d\xfe\xed'),
                       ("rootfs",32<<20, b'UBI#')):
    f.seek(off); got = f.read(4)
    good = got == exp
    rc |= 0 if good else 1
    print(("  \033[32mok\033[0m    " if good else "  \033[31mKO\033[0m    ") +
          f"{name:7} @ {off>>20:3d} MiB  magic={got.hex(' ')}")
sys.exit(rc)
PY
    [ $? -eq 0 ] || RC=1
else
    skip "flash.img assente"
fi

# ---------------------------------------------------------------------------
head_ "5. contenuto di update.img"
# ---------------------------------------------------------------------------
# I pack tool stanno in vendor/packtool (submodule) oppure, se si punta a un
# checkout dell'SDK, sotto tools/linux/Linux_Pack_Firmware/rockdev.
PACKDIR=""
for c in "$(dirname "$0")/../vendor/packtool" \
         ${SDK_DIR:+"$SDK_DIR/packtool"} \
         ${SDK_DIR:+"$SDK_DIR/tools/linux/Linux_Pack_Firmware/rockdev"}; do
    [ -x "$c/afptool" ] && { PACKDIR="$c"; break; }
done
if [ -n "$PACKDIR" ] && [ -x "$PACKDIR/afptool" ] && [ -x "$PACKDIR/rkImageMaker" ] \
   && [ -f "$IMG/update.img" ]; then
    TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
    # Servono DUE passi, come fa unpack.sh dell'SDK: update.img e' un RKFW,
    # cioe' il loader piu' l'immagine afptool incapsulata. afptool da solo non
    # sa leggere l'involucro RKFW.
    if "$PACKDIR/rkImageMaker" -unpack "$IMG/update.img" "$TMP" >/dev/null 2>&1 \
       && "$PACKDIR/afptool" -unpack "$TMP/firmware.img" "$TMP" >/dev/null 2>&1; then
        for p in parameter bootloader uboot boot rootfs; do
            grep -qw "$p" "$TMP/package-file" 2>/dev/null \
                && pass "update.img contiene '$p'" \
                || fail "update.img: '$p' assente dal package-file"
        done
    else
        fail "impossibile spacchettare update.img (rkImageMaker -unpack + afptool -unpack)"
    fi
else
    skip "afptool/rkImageMaker non disponibili (serve SDK_DIR=...), salto"
fi

# ---------------------------------------------------------------------------
if [ -n "$SDK_DIR" ] && [ -d "$SDK_DIR/output/firmware" ]; then
    head_ "6. confronto con gli artefatti dell'SDK"
    # Solo MiniLoaderAll.bin e uboot.img devono coincidere in dimensione:
    # boot.img e rootfs.img dipendono da cosa ci mettiamo dentro, e il nostro
    # e' volutamente piu' magro (niente fragment display, rootfs minimale).
    for f in MiniLoaderAll.bin uboot.img; do
        A="$(stat -c%s  "$IMG/$f" 2>/dev/null)"
        B="$(stat -Lc%s "$SDK_DIR/output/firmware/$f" 2>/dev/null)"
        [ -n "$A" ] && [ -n "$B" ] || { skip "$f non confrontabile"; continue; }
        [ "$A" = "$B" ] && pass "$f: $A B, identico all'SDK" \
                        || fail "$f: $A B, l'SDK ne fa $B"
    done
    skip "boot.img/rootfs.img/update.img: dimensioni diverse per costruzione"
fi

echo
[ $RC -eq 0 ] && printf '\033[32mTutti i controlli passati.\033[0m\n' \
              || printf '\033[31mAlcuni controlli sono falliti.\033[0m\n'
exit $RC
