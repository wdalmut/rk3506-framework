Prima immagine verificata su hardware per **Luckfox Lyra Plus** (RK3506G2, SPI NAND),
costruita con Buildroot upstream e questo external tree.

Serve a una cosa sola: **flashare una scheda e vedere se parte**, senza dover
prima mettere in piedi l'ambiente di build. Non e' un'immagine di prodotto.

## Cosa flashare

Scheda in MaskROM (tasto BOOT premuto all'alimentazione), poi:

```bash
sha256sum -c SHA256SUMS
sudo rkdeveloptool db MiniLoaderAll.bin
sudo rkdeveloptool uf update.img
sudo rkdeveloptool rd
```

`update.img` contiene loader, U-Boot, kernel e rootfs: `MiniLoaderAll.bin` serve
solo al passo `db`, che carica il loader in SRAM prima di poter scrivere.
`parameter.txt` e' incluso per chi preferisce flashare per partizione.

## Cosa aspettarsi

Console seriale su **`ttyFIQ0`, 1500000 8N1** — non 115200. Il baudrate viene
dal nodo `fiq_debugger` del DTS vendor, che ammette solo 115200 o 1500000. Con
un adattatore a 115200 non si vede niente e sembra un boot fallito.

```
picocom -b 1500000 /dev/ttyUSB0
```

Dopo i messaggi del kernel parte `hello-lyra`, che legge dal sistema le quattro
cose che dicono se la scheda e' viva:

```
  Board
    Modello:       Luckfox Lyra Plus
    Kernel:        6.1.99

  Memoria
    MemTotal:      87.1 MiB (89216 kB)
    CmaTotal:      32.0 MiB (32768 kB)

  Partizioni MTD
    dev      size           raw        erasesize  name
    mtd0     4.000 MiB      0x00400000 128 KiB    uboot
    mtd1     12.000 MiB     0x00c00000 128 KiB    boot
    mtd2     223.375 MiB    0x0df60000 128 KiB    rootfs
```

Se `Modello` non dice `Luckfox Lyra Plus`, il DTB caricato non e' quello giusto.
Se non compare nessuna partizione MTD, `mtdparts=` non e' arrivato al kernel.

Login: **`root` / `lyra`**. E' volutamente banale: questa e' un'immagine di
verifica, e mettere una password seria e' compito del progetto che parte da qui.

C'e' anche un gadget USB **ADB** (`2207:0006`) sulla porta OTG0, quindi
`adb shell` funziona senza seriale.

## Cosa c'e' dentro

| | |
|---|---|
| Kernel | vendor 6.1.99 — [`73bca17b`](https://github.com/wdalmut/rk3506-kernel/commit/73bca17b67938d649b072408780369f600555263) |
| U-Boot | vendor 2017.09 — [`1625f78b`](https://github.com/wdalmut/rk3506-uboot/commit/1625f78b6dcf9fe401d447da79132b7bc6804538) |
| Buildroot | upstream, tag LTS 2026.02.3 |
| Toolchain | GCC 13, glibc, ARMv7-A hard-float NEON |
| rootfs | BusyBox init, UBIFS su UBI |

## Sorgenti e licenze

Il kernel e U-Boot sono GPL-2.0: i sorgenti corrispondenti a **questi** binari
sono ai due commit linkati qui sopra, e le modifiche applicate sono le quattro
patch numerate in `external/board/lyra-plus/patches/uboot/` di questo
repository, insieme alla configurazione Buildroot in `external/configs/`.

Le immagini incorporano blob proprietari Rockchip presi da `rkbin` (init DDR
`rk3506_ddr_750MHz_v1.04.bin` dentro `MiniLoaderAll.bin`, OP-TEE
`rk3506_tee_v1.25.bin` dentro `uboot.img`), ridistribuiti secondo la licenza
Rockchip, che concede esplicitamente uso, copia e distribuzione. I blob sono
inclusi intatti, con le loro note di copyright.

## Nota sulla riproducibilita'

Ricostruire da questo commit **non** dara' file identici byte a byte: `ubinize`
scrive un `image_seq` casuale a ogni esecuzione, e i FIT contengono un
timestamp. Gli sha256 sopra valgono per questi file. Cio' che e' invece stabile
sono struttura e geometria, verificabili con `docs/check-artifacts.sh`.
