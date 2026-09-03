<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
<!-- Copyright (C) 2026 Corley S.r.l. -->

# rk-resource-tool — provenienza e licenza

`src/resource_tool.c` **non e' codice di questo progetto**. E' un file preso
dal kernel vendor Rockchip, vendorizzato qui perche' serve alla catena di
packaging anche quando il kernel che stiamo costruendo non e' quello vendor.

## Provenienza

| | |
|---|---|
| Origine | `https://github.com/wdalmut/rk3506-kernel.git` (mirror del BSP Luckfox, `linux-6.1-stan-rkr4.2`) |
| Commit | `73bca17b67938d649b072408780369f600555263` (2025-08-14) |
| Percorso nell'origine | `scripts/resource_tool.c` |
| Dimensione | 39690 B |
| sha256 | `d565a15c6c95871b762fc3599ef37bdbc4de63f6190f4f889b25ac335266b9e4` |

E' lo stesso commit a cui puntano `BR2_LINUX_KERNEL_CUSTOM_REPO_VERSION` nei
due defconfig vendor: il tool vendorizzato e quello compilato in-tree dal
percorso vendor sono quindi lo **stesso** sorgente.

`resource_tool.sha256` permette di verificarlo senza fidarsi:

```sh
cd external/package/rk-resource-tool && sha256sum -c resource_tool.sha256
```

## Licenza

`GPL-2.0+`, dichiarata dal file stesso:

```
// SPDX-License-Identifier: GPL-2.0+
/*
 * (C) Copyright 2008-2015 Fuzhou Rockchip Electronics Co., Ltd
 */
```

Compatibile con la licenza di questo repository (`GPL-2.0-or-later`). Il file
e' incluso **non modificato**: nessuna patch, nessun ritocco di stile. Se
serve cambiarlo, la patch va nel repository del kernel, non qui.

## Perche' non basta il kernel

Nel kernel vendor 6.1 il tool viene compilato da solo, perche'
`scripts/Makefile:9` lo dichiara

```make
hostprogs-always-$(CONFIG_ARCH_ROCKCHIP)		+= resource_tool
```

In **mainline** quella riga non esiste: `scripts/resource_tool.c` non e' mai
stato mandato upstream. Con il kernel mainline
(`lyra_plus_mainline_initramfs_defconfig`) il binario non c'e', e
`post-image.sh` si fermerebbe allo step 2 — `resource.img` — che pero' serve:
U-Boot legge il DTB del kernel **da la'**, non dal nodo `fdt` del FIT. Vedi
`docs/SCELTE-DI-PROGETTO.md`, "resource.img: perche' e' obbligatorio".

## Perche' compila standalone

Include solo header di libc (`errno.h`, `memory.h`, `stdint.h`, `stdio.h`,
`stdlib.h`, `stdbool.h`, `sys/stat.h`, `time.h`): niente `<linux/...>`,
niente `$(srctree)/include`. L'unico flag che il kernel gli aggiunge e'
`-Wno-declaration-after-statement` (`scripts/Makefile:18`), necessario perche'
il file dichiara variabili a meta' blocco e il kernel compila i suoi hostprogs
con quel warning attivo. Qui lo passiamo comunque, per non dipendere dai
default del compilatore host.
