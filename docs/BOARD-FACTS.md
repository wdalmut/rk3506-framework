# BOARD-FACTS — Luckfox Lyra Plus (RK3506G2)

I fatti di questa board che servono per lavorarci: partizioni, console, blob
vendor, geometria della flash, e i valori misurati sull'hardware.

Non e' il diario del porting. Qui ci sono i dati, con la fonte di ognuno; il
*perche'* delle scelte sta in [SCELTE-DI-PROGETTO.md](SCELTE-DI-PROGETTO.md).

Percorsi: `$SDK` e' il checkout dell'SDK Luckfox (`/sdk` nel container),
`$WORK` la radice di questo repository (`/work`).

## Identita'

| | |
|---|---|
| SoC | Rockchip **RK3506G2**, triple Cortex-A7, ARMv7-A 32-bit |
| Storage | SPI NAND **256 MiB**, page 2048 B, erase block 128 KiB |
| DDR | 128 MiB (da confermare, vedi *Aperti*) |
| Console | `ttyFIQ0` su UART0 `0xff0a0000`, **1500000** 8N1 |
| Kernel | vendor 6.1.99 — `github.com/wdalmut/rk3506-kernel` @ `73bca17b6793…` |
| U-Boot | vendor 2017.09 — `github.com/wdalmut/rk3506-uboot` @ `1625f78b6dcf…` |
| rkbin | tag `linux-6.1-stan-rkr4.2`, commit `32ccaf811ae70ce050aa810869c63c2b34324d59` |
| Buildroot | upstream, tag LTS **2026.02.3** |
| DTS | `rk3506g-luckfox-lyra-plus` (in-tree nel kernel vendor) |

I due mirror di kernel e U-Boot sono commit senza parent che riusano l'oggetto
tree del commit vendor: contenuto identico bit per bit, SHA diverso perche'
cambiano i parent. Si rigenerano con [mk-vendor-mirror.sh](mk-vendor-mirror.sh).

---

## Configurazione di board

### Partizionamento MTD

File: `$SDK/device/rockchip/rk3506/parameter-lyra-spinand.txt`

**Baseline vendor** (`git show HEAD:...`):

```
CMDLINE:mtdparts=:0x00002000@0x00002000(uboot),0x00006000@0x00004000(boot),-@0x00010000(rootfs:grow)
```

Le unità di `parameter.txt` Rockchip sono **settori da 512 B**.

| idx MTD | Nome     | Offset (sett.) | Offset  | Size (sett.) | Size      |
|---------|----------|----------------|---------|--------------|-----------|
| —       | *(loader/IDB, non dichiarata)* | `0x0`   | 0 MiB   | `0x2000`  | 4 MiB     |
| `mtd0`  | `uboot`  | `0x2000`       | 4 MiB   | `0x2000`     | 4 MiB     |
| `mtd1`  | `boot`   | `0x4000`       | 8 MiB   | `0x6000`     | 12 MiB    |
| `mtd2`  | `rootfs` | `0x10000`      | 32 MiB  | `-` (grow)   | 224 MiB\* |

\* 256 MiB totali, **confermato sull'hardware**: vedi *Misure dal primo boot*.

Gli indici MTD combaciano con `ubi.mtd=2` nel bootargs del DTS: il parser
cmdline crea **solo** le partizioni elencate, quindi `rootfs` è `mtd2`.
(Nota: tra 20 MiB, fine di `boot`, e 32 MiB, inizio di `rootfs`, resta un gap
di 12 MiB non allocato — è nel baseline vendor, non un errore di lettura.)

**Delta locale:** il `parameter.txt` in checkout aggiunge due partizioni:

```
CMDLINE:mtdparts=:0x00002000@0x00002000(uboot),0x00006000@0x00004000(boot),\
0x00067b00@0x00010000(rootfs),0x00007800@0x00077b00(config),-@0x0007f300(amp:grow)
```

→ `rootfs` diventa 207.375 MiB fisse, `config` 15 MiB @ 239.375 MiB,
`amp` il resto. L'offset finale `0x7f300` (254.625 MiB) è la prova più forte
che il chip è da **256 MiB**.

Anche la riga UUID è identica nelle due varianti:
`uuid:rootfs=614e0000-0000-4b53-8000-1d28000054a9`

### UART di debug

Fonte: `$SDK/kernel-6.1/arch/arm/boot/dts/rk3506g-luckfox-lyra-plus.dts` riga 15

```
bootargs = "earlycon=uart8250,mmio32,0xff0a0000 console=tty1 console=ttyFIQ0
            root=ubi0:rootfs ubi.mtd=2 rootfstype=ubifs rootwait
            snd_aloop.index=7 snd_aloop.use_raw_jiffies=1";
```

| Dato | Valore | Fonte |
|------|--------|-------|
| Base address | `0xff0a0000` | `earlycon=` sopra; `rk3502.dtsi:476-478` → `uart0: serial@ff0a0000 { reg = <0xff0a0000 0x100>; }` |
| Alias | `serial0 = &uart0` | `rk3502.dtsi:31` |
| Compatible | `"rockchip,rk3506-uart", "snps,dw-apb-uart"` | `rk3502.dtsi:477` |
| `reg-shift` / `reg-io-width` | `2` / `4` | `rk3502.dtsi` |
| Device in bootargs | **`ttyFIQ0`** (confermato, *non* `ttyS0`) | `console=ttyFIQ0` nel bootargs |
| Baudrate | **`1500000`** | `rk3506-luckfox-lyra.dtsi:72` → `rockchip,baudrate = <1500000>; /* Only 115200 and 1500000 */` |

`ttyFIQ0` esiste perché il nodo `fiq_debugger` prende in carico la UART:

```
fiq_debugger: fiq-debugger {                       # rk3506-luckfox-lyra.dtsi:67-74
        compatible = "rockchip,fiq-debugger";
        rockchip,serial-id = <0>;                  # -> uart0 -> 0xff0a0000
        rockchip,wake-irq = <0>;
        rockchip,irq-mode-enable = <1>;
        rockchip,baudrate = <1500000>;
        interrupts = <GIC_SPI 115 IRQ_TYPE_LEVEL_HIGH>;
};
```

Abilitato nel kernel da `rk3506_luckfox_defconfig`:
`CONFIG_FIQ_DEBUGGER=y`, `CONFIG_FIQ_DEBUGGER_CONSOLE=y`,
`CONFIG_FIQ_DEBUGGER_NO_SLEEP=y`.

Lato U-Boot, `configs/rk3506_luckfox_defconfig` conferma la stessa UART:
`CONFIG_DEBUG_UART_BASE=0xff0a0000`, `CONFIG_DEBUG_UART_CLOCK=24000000`,
`CONFIG_DEBUG_UART_SHIFT=2`.

> ⚠️ `$SDK/flash.sh` (script scritto in locale, **non** vendor) stampa a fine
> esecuzione `Console seriale: UART2, 1500000 baud`. Il baudrate combacia, la
> UART no: il DTS dice `serial-id = <0>`. Probabile riferimento alla serigrafia
> del connettore, non all'indice SoC. Il DTS ha ragione: la board risponde
> davvero su UART0.

### Storage — SPI NAND

Fonte: `$SDK/kernel-6.1/arch/arm/boot/dts/rk3506-luckfox-lyra.dtsi:1245-1255`

```
&fspi {
        status = "okay";
        flash@0 {
                compatible = "spi-nand";
                reg = <0>;
                spi-max-frequency = <80000000>;
                spi-rx-bus-width = <4>;
                spi-tx-bus-width = <1>;
        };
};
```

Alias: `spi2 = &fspi` (`rk3502.dtsi:39`).

Driver kernel abilitati (`rk3506_luckfox_defconfig`): `CONFIG_MTD_SPI_NAND=y`,
`CONFIG_SPI_ROCKCHIP_SFC=y`, `CONFIG_SPI_ROCKCHIP_FLEXBUS_FSPI=y`,
`CONFIG_MTD_CMDLINE_PARTS=y`, `CONFIG_MTD_UBI=y`, `CONFIG_MTD_UBI_BLOCK=y`.
Lato U-Boot: `CONFIG_MTD_SPI_NAND=y`, `CONFIG_ROCKCHIP_SFC=y`,
`CONFIG_SPI_FLASH_{GIGADEVICE,MACRONIX,WINBOND,XMC}=y`, `CONFIG_SF_DEFAULT_SPEED=50000000`.

Page 2048 B e blocco 128 KiB, **misurati** sull'hardware: vedi *Misure dal
primo boot*. Sono i valori che il defconfig usa per `mkfs.ubifs` e `ubinize`.

### rkbin — blob DDR

Fonte: `$SDK/rkbin/RKBOOT/RK3506MINIALL.ini`

```ini
[CHIP_NAME]
NAME=RK350F
[CODE471_OPTION]
NUM=1
Path1=bin/rk35/rk3506_ddr_750MHz_v1.04.bin
[CODE472_OPTION]
NUM=1
Path1=bin/rk35/rk3506_usbplug_v1.02.bin
[LOADER_OPTION]
NUM=2
LOADER1=FlashData
LOADER2=FlashBoot
FlashData=bin/rk35/rk3506_ddr_750MHz_v1.04.bin
FlashBoot=bin/rk35/rk3506_spl_v1.10.bin
[LOADER2_PARAM]
LOAD_ADDR=0x3f00000
FLAG=0x0
[OUTPUT]
PATH=rk3506_spl_loader_v1.04.110.bin
IDB_PATH=rk3506_idblock_v1.04.110.img
[SYSTEM]
NEWIDB=true
[FLAG]
471_RC4_OFF=true
RC4_OFF=true
CREATE_IDB=true
```

| Dato | Valore |
|------|--------|
| **Nome esatto del DDR bin** | **`bin/rk35/rk3506_ddr_750MHz_v1.04.bin`** |
| Ruoli | `CODE471_OPTION/Path1` **e** `LOADER_OPTION/FlashData` |
| Variante da NON usare | `bin/rk35/rk3506_ddr_750MHz_v1.04.bin` è per RK3506**G**; esiste anche `rk3506b_ddr_750MHz_v1.04.bin` per RK3506**B** |
| SPL prebuilt (sostituito) | `bin/rk35/rk3506_spl_v1.10.bin` → rimpiazzato a build time da `u-boot/spl/u-boot-spl.bin` |
| usbplug | `bin/rk35/rk3506_usbplug_v1.02.bin` |
| TEE | `bin/rk35/rk3506_tee_v1.25.bin` (da `RKTRUST/RK3506TOS.ini`: `TOSTA=…`, `ADDR=0x1000`) |
| Chip tag | `RK350F` — usato sia da `boot_merger` sia da `rkImageMaker -RK350F` |
| Output loader | `rk3506_spl_loader_v1.04.110.bin` (→ `MiniLoaderAll.bin`, 268736 B) |
| IDB | `rk3506_idblock_v1.04.110.img` (196608 B) |

**Offset di scrittura atteso dal BootROM:**

* **SD / eMMC: settore 64 (32 KiB).** Verificato in `$SDK/flash.sh`:
  `info "scrivo idbloader al settore 64"` / `dd if="$IDB" of="$DEV" seek=64`.
  (Script locale, ma coerente con la convenzione Rockchip.)
* **SPI NAND: ancora da accertare** (vedi *Aperti*, punto 2). Fatto certo: in
  `parameter-lyra-spinand.txt` i primi **4 MiB** (`0x0`–`0x2000` settori) non
  sono assegnati ad alcuna partizione, cioè sono l'area riservata a
  loader/IDB. Il posizionamento effettivo dentro quell'area lo decide
  `upgrade_tool`/`rkdeveloptool` a partire da `update.img`, non uno script
  dell'SDK.

---

---

## Artefatti prodotti


| File | Dimensione | Primi byte | Formato |
|------|-----------:|------------|---------|
| `MiniLoaderAll.bin` | 268 736 | `4c 44 52 20` `LDR ` | Rockchip loader |
| `uboot.img` | 4 194 304 | `d0 0d fe ed` | FIT (2×itb, pad 2048K) |
| `boot.img` | 6 391 808 | `d0 0d fe ed` | FIT (zImage+fdt+resource) |
| `rootfs.img` | 124 518 400 | `55 42 49 23` `UBI#` | UBI |
| `update.img` | 135 649 866 | `52 4b 46 57` `RKFW` | Rockchip firmware |

Gli invarianti di forma di questi file (struttura dei FIT, geometria UBI,
offset, contenuto di `update.img`) si controllano con
[check-artifacts.sh](check-artifacts.sh), da lanciare dopo aver alzato uno SHA
o toccato `post-image.sh`.

---

## Misure dal primo boot su hardware

Output di `hello-lyra` sulla seriale, board che parte da SPI NAND.

### Confermato

| Dato | Valore misurato | Cosa conferma |
|------|-----------------|---------------|
| `/proc/device-tree/model` | `Luckfox Lyra Plus` | il DTB dentro `boot.img` è quello giusto: `BR2_LINUX_KERNEL_INTREE_DTS_NAME` corretto |
| kernel | `6.1.99` | il mirror `rk3506-kernel` serve il commit atteso |
| `mtd0 uboot` | 4 MiB, erase 128 KiB | combacia con `parameter.txt` (`0x2000` settori) |
| `mtd1 boot` | 12 MiB, erase 128 KiB | combacia con `parameter.txt` (`0x6000` settori) |
| `mtd2 rootfs` | 223.375 MiB (`0x0df60000`), erase 128 KiB | monta e il sistema parte |
| `erasesize` | **128 KiB** ovunque | `BR2_TARGET_ROOTFS_UBI_PEBSIZE=0x20000` è giusto — era l'assunzione più rischiosa di tutto il porting |
| console | `ttyFIQ0`, 1500000 8N1 | il DTS aveva ragione, non la serigrafia "UART2" |

L'`erasesize` è il riscontro che conta di più: LEB, PEB e min-I/O erano stati
dedotti dai default di `mk-image.sh` dell'SDK, non misurati. Se il blocco
fosse stato da 256 KiB il rootfs non avrebbe montato.

### Due cose che non tornano

**1. ~~`rootfs` è 223 MiB, non 224.~~ Chiuso.** Con le cifre esatte il conto si
fa: `rootfs` è `0x0df60000` a offset 32 MiB, quindi finisce a 255.375 MiB su un
chip da 256 MiB. Restano **640 KiB, cioè 5 blocchi da 128 KiB**, non coperti da
`mtdparts`. Non è il vendor storage, che sta a offset 0 e occupa 64 KiB
(`vendor.c:42,47`). Il perché esatto resta ignoto, ma sono lo 0.25% del chip e
il rootfs funziona: curiosità, non problema. Vale la pena notare che
l'arrotondamento a `%.0f` di `hello-lyra` nascondeva proprio la cifra che
permetteva di chiudere la questione.

**2. `MemTotal` = 89 216 kB (87,1 MiB), che è poco.** Confermato e approfondito
nella sezione [32 MiB di RAM fermi in un CMA che non usiamo](#32-mib-di-ram-fermi-in-un-cma-che-non-usiamo).
Il DTS di board fa:

```
/**********display**********/
&cma {
        size = <0x2000000>;     /* 32 MiB */
};
```

mentre il default nel dtsi è `size = <0x0>`. Quindi il DTS vendor riserva
**32 MiB di CMA per il VOP** — e questo albero il display non lo costruisce
(`linux.config` non applica `rk3506-display.config`).

La misura successiva ha dato `CmaTotal = 32 MiB` e `CmaFree = 0`: il sospetto
regge. Dettaglio e conti nella sezione dedicata.

---

---

## 32 MiB di RAM fermi in un CMA che non usiamo

Misurato da `hello-lyra` sulla board:

```
MemTotal:      87.1 MiB (89216 kB)
CmaTotal:      32.0 MiB (32768 kB)
CmaFree:        0.0 MiB (0 kB)
```

`CmaTotal` è **esattamente** il valore che il DTS di board scrive:

```
/**********display**********/
&cma {
        size = <0x2000000>;     /* 32 MiB */
};
```

mentre il default nel dtsi è `size = <0x0>`. Quel CMA esiste per il VOP, e
questo albero il display non lo costruisce: `board/lyra-plus/linux.config` non
applica `rk3506-display.config`.

`CmaFree = 0` è la parte che conta. Se quei 32 MiB fossero regolarmente entrati
nel buddy allocator come `MIGRATE_CMA`, sarebbero quasi tutti liberi e
utilizzabili come memoria normale, e il CMA sarebbe innocuo. Con `CmaFree = 0`
non lo sono: nessuno li sta usando (non c'è display) ma non sono nemmeno
disponibili.

I conti tornano con l'ipotesi "riservati e mai restituiti al sistema": se la
board monta 128 MiB di DDR,

    128.000 MiB  DDR
   - 32.000 MiB  CMA
   -  ~8.9 MiB   kernel, page table, mem_map, trust@0, ramoops
   ------------
     87.1  MiB   = MemTotal misurato

`TODO(verify):` la DDR è davvero 128 MiB? Il dato definitivo è la riga che il
kernel stampa al boot, che dà totale e ripartizione in un colpo solo:

```
dmesg | grep -i '^\[.*\] Memory:'
# es. Memory: 89216K/131072K available (... reserved, 32768K cma-reserved)
```

Se confermato, azzerare `&cma` in un DTS di board nostro restituisce **32 MiB
su 128, cioè il 37% di RAM utilizzabile in più**. Il meccanismo esiste già:
`BR2_LINUX_KERNEL_CUSTOM_DTS_PATH`, usato per la variante initramfs.

Da non fare alla cieca: chi un domani accende il display si ritrova senza
memoria contigua e con un VOP che non alloca framebuffer. La scelta va legata
al fragment display, non presa una volta per tutte.

---

## Aperti

| # | Criticita' | Cosa manca |
|---|-----------|------------|
| 1 | 🟠 | Quanta DDR monta la board, e quanto se ne recupera azzerando il CMA che non usiamo. Una riga: `dmesg \| grep -i 'Memory:'`. Vedi la sezione sul CMA. |
| 2 | 🟡 | A quale offset il BootROM RK3506 cerca l'IDB su **SPI NAND**. Accertato solo che i primi 4 MiB sono riservati e che su SD/eMMC e' il settore 64. Blocca `flash.img` come immagine avviabile, non il flash via `update.img`. |
| 3 | 🟢 | I 640 KiB (5 blocchi) di coda non coperti da `mtdparts`. Non e' il vendor storage, che sta a offset 0 e occupa 64 KiB (`vendor.c:42,47`). Lo 0.25% del chip: curiosita'. |
