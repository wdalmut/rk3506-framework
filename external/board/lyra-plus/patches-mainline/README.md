<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
<!-- Copyright (C) 2026 Corley S.r.l. -->

# Patch solo per il percorso mainline

Directory aggiunta a `BR2_GLOBAL_PATCH_DIR` **solo** da
`lyra_plus_mainline_initramfs_defconfig`. I due defconfig vendor non la
vedono.

Serve perche' `board/lyra-plus/patches/` e' condivisa fra i tre defconfig e
Buildroot applica al package `linux` tutte le patch che trova in
`<dir>/linux/`, senza sapere quale kernel sia. Una patch al DTS mainline
(`arch/arm/boot/dts/rockchip/rk3506g-luckfox-lyra-plus.dts`) non applica sul
kernel vendor 6.1, dove quel file non esiste a quel percorso: metterla nella
directory condivisa romperebbe le due build vendor.

## `linux/0001-dts-keep-linux-out-of-the-op-tee-region.patch`

Aggiunge `linux,usable-memory-range` al nodo `/chosen` del DTS di board.

Senza, la board **non parte e non stampa niente**: con `AUTO_ZRELADDR` il
decompressore mette la propria page directory a `0x4000` e il kernel a
`0x8000`, dentro la regione di OP-TEE (`trust@0`, `0x0-0x62000`) che il
firewall del SoC rende inaccessibile dal normal world. Il perche' in dettaglio,
con i riferimenti al sorgente e la prova raccolta sulla board, sta
nell'intestazione della patch stessa.

**Questa patch e' un rimedio temporaneo nel posto sbagliato.** Il DTS vive in
`rk3506-kernel-upstream`, e la correzione va la': quando ci sara', questa
patch va rimossa e lo SHA nel defconfig alzato.
