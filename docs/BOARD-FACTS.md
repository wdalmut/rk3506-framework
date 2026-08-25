# BOARD-FACTS — Luckfox Lyra Plus (RK3506G2)

Ricognizione dell'SDK Luckfox, **Fase 1**. Ogni valore cita il file da cui è
stato ricavato. Dove il dato non è stato trovato c'è un `TODO(verify):` con la
domanda precisa: **nessun valore è inventato**.

Convenzioni di percorso in questo documento:

| Simbolo | Host                      | Container |
|---------|---------------------------|-----------|
| `$SDK`  | `~/git/luckfox-lyra`      | `/sdk`    |
| `$WORK` | `~/git/rk3506-framework`  | `/work`   |

Trace di riferimento prodotti da questa ricognizione (in `$WORK`):

* `build-trace.log` — `env SHELLOPTS=xtrace bash ./build.sh` (target default `all`)
* `build-trace-pack.log` — `env SHELLOPTS=xtrace bash ./build.sh firmware updateimg`

> `SHELLOPTS=xtrace` va iniettato con `env`: in bash `SHELLOPTS` è **readonly**,
> quindi `SHELLOPTS=xtrace bash -x ./build.sh` fallisce. Serve iniettarlo
> nell'ambiente perché `build.sh` invoca gli hook come processi bash separati,
> che altrimenti non erediterebbero `-x`.

---

## 0. Stato del checkout SDK esaminato

L'SDK montato **non è vergine**: contiene modifiche locali. Vanno separate dal
baseline vendor, perché il porting deve partire dal secondo.

Fonte: `git -C $SDK/<repo> status --short`

| Repo             | File modificato/aggiunto                                     | Stato    |
|------------------|--------------------------------------------------------------|----------|
| `device/rockchip`| `.chips/rk3506/luckfox_lyra_plus_buildroot_spinand_defconfig` | `M`      |
| `device/rockchip`| `.chips/rk3506/luckfox_lyra_buildroot_sdmmc_defconfig`        | `M`      |
| `device/rockchip`| `.chips/rk3506/parameter-lyra-spinand.txt`                    | `M`      |
| `device/rockchip`| `common/scripts/build.sh`                                     | `M`      |
| `device/rockchip`| `.chips/rk3506/amp_miranda.its`                               | `??`     |
| `kernel-6.1`     | `arch/arm/boot/dts/rk3506-luckfox-lyra.dtsi`                  | `M`      |
| `kernel-6.1`     | `arch/arm/boot/dts/rk3506g-corley-lyra-plus.dts`              | `??`     |
| `kernel-6.1`     | `arch/arm/configs/miranda_amp.config`                         | `??`     |
| `buildroot`      | `configs/rockchip/base/common.config`                         | `M`      |
| `buildroot`      | `configs/rockchip_rk3506_luckfox_defconfig`                   | `M`      |
| `u-boot`         | —                                                             | pulito   |

Le modifiche locali introducono una configurazione **AMP** (Linux su due core
A7 + RT-Thread sul terzo, `RK_AMP=y`, `RK_AMP_MCU_HAL_TARGET="miranda-rt"`) e un
DTS custom `rk3506g-corley-lyra-plus`. **Il porting di Fase 2 prende come
riferimento il baseline vendor**, che non ha AMP; la variante locale è
documentata sotto per confronto.

---

## 1a. Provenienza dei sorgenti

### Manifest

* `$SDK/.gitmodules` — **non esiste**. L'SDK non usa submodule, usa `repo`.
* `$SDK/.repo/manifest.xml` → symlink a
  `manifests/rk3506_linux6.1_release.xml` → symlink a
  `release/luckfox_linux6.1_rk3506_release_v1.4_20250620.xml`
* Commento nel manifest: `<!-- Based file name: RK3506_LINUX6.1_SDK_Release_V1.1.0_20241128 -->`
* Remote del manifest, da `$SDK/.repo/manifests/.git/config`:

```
url = ssh://git@192.168.10.75/RK3506_Linux610_mirror_241206/manifests_luckfox.git
branch default -> refs/heads/luckfox-release
```

* Storia del manifest (`git -C $SDK/.repo/manifests log --oneline`):
  `d4e9bb0 luckfox release v1.4` / `71b4831 v1.2` / `7943442 v1.0`

> ⚠️ **Il remote è un mirror di LAN privata (192.168.10.75), non raggiungibile
> da fuori.** Nel manifest tutti i progetti usano `remote="rk" fetch="."`,
> cioè path relativi a quello stesso host. Vedi TODO-1 in fondo: è il
> blocco più serio per il requisito `_CUSTOM_GIT`.

### Revisioni pinnate

Il manifest pinna **branch/tag, non SHA**. Gli SHA sotto sono quelli
effettivamente in checkout (`git -C $SDK/<path> rev-parse HEAD`).

| Progetto  | Path SDK          | `revision` nel manifest        | SHA in checkout                            | Data commit  |
|-----------|-------------------|--------------------------------|--------------------------------------------|--------------|
| kernel    | `kernel-6.1`      | `luckfox-linux-6.1-rk3506`     | `696a8549d1a582337c8032c02a2aea35790047a4` | 2025-08-14   |
| U-Boot    | `u-boot`          | `luckfox-linux-6.1-rk3506`     | `4d88b0a83c87488f343fb4cc4f56ffc598b2e0a3` | 2025-06-23   |
| buildroot | `buildroot`       | `luckfox-linux-6.1-rk3506`     | `e6abe17d737f2829b53f187e434e45d110306d8f` | 2025-08-14   |
| rkbin     | `rkbin`           | `refs/tags/linux-6.1-stan-rkr4.2` | `32ccaf811ae70ce050aa810869c63c2b34324d59` | 2024-11-26   |
| device/rockchip | `device/rockchip` | `luckfox-linux-6.1-rk3506` | `3aaca70ee151696f2ff4806cc4a8406552b521f9` | 2025-08-14   |

Versioni upstream:

* Kernel `6.1.99` — `$SDK/kernel-6.1/Makefile` (`VERSION=6 PATCHLEVEL=1 SUBLEVEL=99`)
* U-Boot `2017.09` — `$SDK/u-boot/Makefile` (`VERSION=2017 PATCHLEVEL=09`)

> ⚠️ **Tutti i progetti sono clonati con `clone-depth="1"`** (attributo su ogni
> `<project>` del manifest; `git rev-list --count HEAD` su `buildroot` restituisce
> `1`). Conseguenze pratiche per `_CUSTOM_GIT`:
> 1. non è possibile calcolare localmente la divergenza in numero di commit;
> 2. un fetch di uno SHA nudo richiede che il server abbia
>    `uploadpack.allowReachableSHA1InWant`, oppure che lo SHA sia la tip di un ref.

### Base upstream del Buildroot dell'SDK

* **`2024.02`** — `$SDK/buildroot/Makefile`: `export BR2_VERSION := 2024.02`,
  confermato da `$SDK/buildroot/CHANGES` (prima voce: *"2024.02, released March 5th, 2024"*).
* `2024.02` **è una release LTS** upstream.

**Commit di divergenza: `TODO(verify)`** — non calcolabile: il clone è
`depth=1` (un solo commit). Vedi TODO-2.

Ho invece calcolato la divergenza **a livello di albero**, che è ciò che serve
davvero per decidere cosa riportare. Metodo:

```bash
git -C $WORK/buildroot worktree add --detach /tmp/br-2024.02 2024.02
diff -rq -x .git -x output -x dl -x archives /tmp/br-2024.02 $SDK/buildroot
```

Risultato: **452 file/dir aggiunti, 242 modificati, 22 rimossi.**

#### Package aggiunti in `package/` (nuove directory di primo livello)

```
alsa-ucm-conf  aml  android-adb  android-adbd  chromium-wayland  fatresize
flutter-embedded-linux  flutter-packages  frecon  gl4es  ifuse  iniparser
intel-wds  jwm  labwc  libarm-memhook  libdrm-cursor  libimobiledevice
libimobiledevice-glue  librws  libsrt  libtsm  libusbmuxd  libusrsctp  lvgl
mupen64plus  mynt-eye-d-sdk  neatvnc  nginx-http-flv-live  nginx-rtmp  noto
oem  pcl  pcsx  play  pm-utils  python-casttube  python-llvmlite
python-mkchromecast  python-numba  python-pychromecast  retroarch  rockchip
source-han-sans  stressapptest  tcp-wrappers  unixbench  usbmuxd  uvc-gadget
vkmark  xcursor-themes  xcursor-transparent-theme
```

Più decine di `.patch` aggiunte a package upstream esistenti (alsa-lib,
busybox, bash, gstreamer1/*, freerdp, gdb, gcc, dhcpcd, …).

**Rilevanza per questo porting: quasi nulla.** Sono stack multimediali /
grafici / Rockchip-BSP. Per un rootfs BusyBox + una app hello world non ne
serve nessuno. `rockchip` (il meta-package BSP) e `pm-utils` sono gli unici
citati dalla config di board, e nessuno dei due è necessario al boot.

#### Modifiche all'infrastruttura Buildroot (non-package)

```
arch/Config.in.arm            fs/common.mk              linux/Config.in
Config.in                     fs/Config.in              linux/linux.mk
Config.in.legacy              fs/ext2/Config.in         Makefile
DEVELOPERS                    fs/ext2/ext2.mk           support/download/bzr
support/download/check-hash   fs/ubi/Config.in          support/misc/toolchainfile.cmake.in
support/scripts/apply-patches.sh  fs/ubi/ubi.mk         support/scripts/check-bin-arch
system/Config.in              fs/ubi/ubinize.cfg        system/skeleton/etc/profile
toolchain/Config.in           fs/ubifs/Config.in        toolchain/toolchain-wrapper.c
utils/brmake                  fs/ubifs/ubifs.mk
```

Ho ispezionato le modifiche che toccano il nostro percorso (rootfs UBI, kernel,
patch, arch ARM). **Sono tutte comodità, non funzionalità mancanti in upstream:**

| File | Cosa cambia il vendor | Serve riportarla? |
|------|----------------------|-------------------|
| `fs/ubifs/Config.in` + `ubifs.mk` | Aggiunge `BR2_TARGET_ROOTFS_UBIFS_MAX_SIZE` (in MB) che *calcola* `MAXLEBCNT` | **No** — si imposta `BR2_TARGET_ROOTFS_UBIFS_MAXLEBCNT` direttamente (valore reale: `8456`, vedi §1c) |
| `fs/ubi/Config.in` + `ubi.mk` + `ubinize.cfg` | Aggiunge `BR2_TARGET_ROOTFS_UBI_MINIOSIZE` e l'opzione squashfs-dentro-UBI | **No** — upstream usa `BR2_TARGET_ROOTFS_UBIFS_MINIOSIZE` per `-m`, che vale comunque `0x800`; noi usiamo ubifs, non squashfs |
| `linux/linux.mk` | Aggiunge `BR2_LINUX_KERNEL_CUSTOM_LOCAL` (site method `local`) | **No** — noi usiamo `BR2_LINUX_KERNEL_CUSTOM_GIT`, già upstream |
| `arch/Config.in.arm` | cortex-a55/a75 in aarch32; default FPU `NEON_VFPV4` automatico | **No** — `BR2_cortex_a7` è upstream e seleziona già `ARMV7A`+`NEON`+`VFPV4`; l'FPU la fissiamo esplicitamente |
| `support/scripts/apply-patches.sh` | `BR2_GEN_GIT`: crea un repo git nella build dir per generare patch | **No** — comodità di sviluppo |
| `Makefile` | Supporto `#include` nei defconfig | **No** — scriviamo un defconfig piatto |

> **Conclusione 1a: nessuna patch a Buildroot upstream è necessaria.**
> `external/patches/` (`BR2_GLOBAL_PATCH_DIR`) resterà predisposta ma vuota.

---

## 1b. Configurazione di board

### Il defconfig di Lyra Plus (SPI NAND)

File: `$SDK/device/rockchip/rk3506/luckfox_lyra_plus_buildroot_spinand_defconfig`

**Baseline vendor** (`git show HEAD:.chips/rk3506/luckfox_lyra_plus_buildroot_spinand_defconfig`):

```
RK_BUILDROOT_BASE_CFG="rk3506_luckfox"
# RK_YOCTO is not set
RK_ROOTFS_UBI=y
RK_ROOTFS_HOSTNAME_CUSTOM=y
RK_ROOTFS_HOSTNAME="luckfox"
RK_ROOTFS_INSTALL_MODULES=y
# RK_WIFIBT is not set
# RK_ROOTFS_LOG_GUARDIAN is not set
RK_EXTRA_FONTS_ENABLED_EN=y
RK_UBOOT_CFG="rk3506_luckfox"
RK_UBOOT_SPL=y
RK_KERNEL_CFG="rk3506_luckfox_defconfig"
RK_KERNEL_CFG_FRAGMENTS="rk3506-display.config"
RK_KERNEL_DTS_NAME="rk3506g-luckfox-lyra-plus"
RK_BOOT_COMPRESSED=y
# RK_RECOVERY is not set
RK_EXTRA_PARTITION_NUM=0
RK_PARAMETER="parameter-lyra-spinand.txt"
RK_USE_FIT_IMG=y
```

Sintesi:

| Voce | Valore | Fonte |
|------|--------|-------|
| DTS | `rk3506g-luckfox-lyra-plus` | `RK_KERNEL_DTS_NAME` |
| Kernel defconfig | `arch/arm/configs/rk3506_luckfox_defconfig` | `RK_KERNEL_CFG` |
| Kernel fragment | `arch/arm/configs/rk3506-display.config` | `RK_KERNEL_CFG_FRAGMENTS` |
| U-Boot defconfig | `configs/rk3506_luckfox_defconfig` | `RK_UBOOT_CFG` |
| U-Boot SPL | sì, ricompilato (`--spl-new`) | `RK_UBOOT_SPL=y` |
| Buildroot base cfg | `configs/rockchip_rk3506_luckfox_defconfig` | `RK_BUILDROOT_BASE_CFG` |
| Rootfs | UBI/UBIFS | `RK_ROOTFS_UBI=y` |
| boot.img | FIT compresso → `zboot.img` | `RK_BOOT_COMPRESSED=y`, `RK_USE_FIT_IMG=y` |
| Partizioni | `parameter-lyra-spinand.txt` | `RK_PARAMETER` |

Derivate, da `$SDK/device/rockchip/common/configs/Config.in.boot`:

* `RK_BOOT_IMG` → `"zboot.img"` (default *if* `RK_BOOT_COMPRESSED`) — riga 9-11
* `RK_BOOT_FIT_ITS_NAME` → `"zboot.its"` — riga 25-29
* `RK_BOOT_FIT_ITS` → `"$RK_CHIP_DIR/$RK_BOOT_FIT_ITS_NAME"` = `device/rockchip/rk3506/zboot.its` — riga 32-34

**Delta locale (non vendor):** DTS `rk3506g-corley-lyra-plus`, fragment
aggiuntivi `rockchip_amp.config miranda_amp.config`, `RK_AMP=y`,
`RK_AMP_FIT_ITS="amp_miranda.its"`, `RK_AMP_MCU_HAL_TARGET="miranda-rt"`,
`RK_ROOTFS=y`, `# RK_NETWORK_CHECK is not set`, `RK_UBOOT_CFG_FRAGMENTS="rk-amp"`.

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

\* assumendo 256 MiB totali — vedi TODO-5.

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
> del connettore, non all'indice SoC. Vedi TODO-6.

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

Geometria usata dalla toolchain immagini (page 2048 B, blocco 128 KiB): vedi §1c.

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
* **SPI NAND: `TODO(verify)`** — vedi TODO-4. Fatto accertato: in
  `parameter-lyra-spinand.txt` i primi **4 MiB** (`0x0`–`0x2000` settori) non
  sono assegnati ad alcuna partizione, cioè sono l'area riservata a
  loader/IDB. Il posizionamento effettivo dentro quell'area lo decide
  `upgrade_tool`/`rkdeveloptool` a partire da `update.img`, non uno script
  dell'SDK.

---

## 1c. Catena di packaging — ricostruita dal trace

Metodo (come da specifica, con la correzione su `SHELLOPTS`):

```bash
cd /sdk && env SHELLOPTS=xtrace bash ./build.sh > /work/build-trace.log 2>&1
cd /sdk && env SHELLOPTS=xtrace bash ./build.sh firmware updateimg \
                                     > /work/build-trace-pack.log 2>&1
```

> Il primo run è arrivato fino a `boot.img` incluso e poi si è fermato allo
> stage buildroot per un motivo **ambientale**, non di catena: il `.config`
> Buildroot in `$SDK/buildroot/output/rockchip_rk3506_luckfox/.config` contiene
> `BR2_EXTERNAL_MIRANDA_PATH="/home/walter/git/test-lyra/br2-external"`,
> path residuo di un esperimento precedente e assente nel container →
> `Makefile:222: *** '…/br2-external': no such file or directory`.
> Il secondo run copre gli stage `firmware` e `updateimg`. Lo stage rootfs è
> comunque interamente ricostruito dal log Buildroot della build precedente
> (`$SDK/output/sessions/2026-08-23_20-07-02/br-rootfs.log`), che riporta i
> comandi reali.

### Sequenza completa, in ordine, con argomenti reali

#### ① Loader / U-Boot — `mk-loader.sh` → `u-boot/make.sh`

```
# build-trace.log:2322
./make.sh CROSS_COMPILE=/sdk/prebuilts/gcc/linux-x86/arm/\
gcc-arm-10.3-2021.07-x86_64-arm-none-linux-gnueabihf/bin/arm-none-linux-gnueabihf- \
    rk3506_luckfox rk-amp --spl-new
```

(`rk-amp` è il fragment introdotto dalla config **locale**; il baseline vendor
non lo passa.)

```
# build-trace.log:4056
/sdk/u-boot/scripts/fit.sh --spl-new \
    --ini-trust  /sdk/rkbin/RKTRUST/RK3506TOS.ini \
    --ini-loader /sdk/rkbin/RKBOOT/RK3506MINIALL.ini \
    --chip RK3506

# build-trace.log:4121  (genera u-boot.its; OP-TEE come "firmware", U-Boot come "loadables")
./make.sh itb /sdk/rkbin/RKTRUST/RK3506TOS.ini

# build-trace.log:4750
./tools/mkimage -f u-boot.its -E u-boot.itb

# build-trace.log:5257   <- OFFS_DATA = 0x1200
./tools/mkimage -f u-boot.its -E -p 0x1200 fit/uboot.itb -v 0

# build-trace.log:5616-5621   -> uboot.img = 2 copie della stessa .itb, ognuna
#                                paddata a 2048K  (CONFIG_SPL_FIT_IMAGE_MULTIPLE=2,
#                                CONFIG_SPL_FIT_IMAGE_KB=2048)  => 4 MiB esatti
cat fit/uboot.itb >> uboot.img ; truncate -s %2048K uboot.img   # x2

# build-trace.log:5298 / 5547
./make.sh --spl /sdk/rkbin/RKBOOT/RK3506MINIALL.ini
/sdk/u-boot/scripts/spl.sh --ini /sdk/rkbin/RKBOOT/RK3506MINIALL.ini \
                           --spl /sdk/u-boot/spl/u-boot-spl.bin
```

`spl.sh` copia l'`.ini` in `tmp/MINIALL.ini`, sostituisce
`FlashBoot=` con lo SPL appena compilato e lancia:

```
# build-trace.log:5577
./tools/boot_merger tmp/MINIALL.ini          # cwd = /sdk/rkbin
    ********boot_merger ver 1.35********
    Info:Pack loader ok.
    creating new idblock from loader...
    idblock binary saving at rk3506_idblock_v1.04.110.img
```

Esiti (`mk-loader.sh` li linka in `output/firmware/`):
`rk3506_spl_loader_v1.04.110.bin` → `MiniLoaderAll.bin`, e `uboot.img`.
**Nessun `trust.img`**: OP-TEE è dentro il FIT di `uboot.img`
(`firmware = "optee"` nelle `configurations`), coerentemente con
`CONFIG_ROCKCHIP_FIT_IMAGE_PACK=y`.

`trust_merger` / `loaderimage` **non vengono invocati** in questa
configurazione (sono i percorsi non-FIT / ARM64-ATF di `make.sh`).

#### ② Kernel e boot.img — `mk-kernel.sh` → `kernel/scripts/mkimg`

`mk-kernel.sh:79` esegue `$KMAKE "$RK_KERNEL_DTS_NAME.img"`. La regola sta in
`kernel-6.1/arch/arm/Makefile:343-348`:

```make
%.img:
	$(Q)$(MAKE) $*.dtb zImage Image.gz modules
	$(Q)$(srctree)/scripts/mkimg --dtb $*.dtb
```

`scripts/mkimg` produce prima `resource.img`, poi (ramo `mkbootimg`, perché
`BOOT_IMG`/`BOOT_ITS` non sono esportati a `make`) due immagini Android boot:

```
# build-trace.log:8938
scripts/resource_tool ./arch/arm/boot/dts/rk3506g-corley-lyra-plus.dtb logo.bmp logo_kernel.bmp
# build-trace.log:8947
./scripts/mkbootimg --kernel ./arch/arm/boot/Image  --second resource.img -o boot.img
# build-trace.log:8950
./scripts/mkbootimg --kernel ./arch/arm/boot/zImage --second resource.img -o zboot.img
```

`resource_tool` è **compilato dai sorgenti del kernel** (`kernel-6.1/scripts/resource_tool`,
ELF x86-64) — non viene da `rkbin`. `mkkrnlimg` **non è invocato** in questo flusso.

Poi `mk-kernel.sh:84` **sovrascrive** `zboot.img` con il vero FIT:

```
# build-trace.log:8969
/sdk/device/rockchip/common/scripts/mk-fitimage.sh \
    kernel/zboot.img \
    /sdk/device/rockchip/.chip/zboot.its \
    kernel/arch/arm/boot/zImage \
    kernel/arch/arm/boot/dts/rk3506g-corley-lyra-plus.dtb \
    kernel/resource.img
```

`mk-fitimage.sh` copia l'`.its` in un temp e sostituisce i placeholder:

```
# build-trace.log:8980
sed -i -e s~@KERNEL_DTB@~/sdk/kernel-6.1/arch/arm/boot/dts/<dts>.dtb~ \
       -e s~@KERNEL_IMG@~/sdk/kernel-6.1/arch/arm/boot/zImage~ \
       -e s~@RAMDISK_IMG@~~ \
       -e s~@RESOURCE_IMG@~/sdk/kernel-6.1/resource.img~  /tmp/tmp.XXXX
# build-trace.log:8985
/sdk/rkbin/tools/mkimage -f /tmp/tmp.XXXX -E -p 0x800 kernel/zboot.img
```

L'`.its` usato è `device/rockchip/rk3506/zboot.its` (via il symlink `.chip`):
tre `images` — `fdt` (`flat_dt`, `load = <0xffffff00>`), `kernel`
(`type="kernel"`, `arch="arm"`, `compression="none"`, `entry/load = <0xffffff01>`),
`resource` (`type="multi"`); ognuna con `hash { algo = "sha256"; }`. La
`configurations/conf` dichiara `rollback-index = <0>` e un blocco `signature`
(`sha256,rsa2048`, padding `pss`, `key-name-hint = "dev"`) che **non viene
applicato** perché `RK_SECURITY` è vuoto.

Infine `mk-kernel.sh:99`: `ln -rsf kernel/zboot.img output/firmware/boot.img`.

#### ③ Rootfs UBI — Buildroot nativo (`fs/ubi` + `fs/ubifs`)

Non c'è uno script Rockchip nel percorso buildroot: `output/firmware/rootfs.img`
è un symlink a `buildroot/output/rockchip_rk3506_luckfox/images/rootfs.ubi`.
Comandi reali (da `$SDK/output/sessions/2026-08-23_20-07-02/br-rootfs.log`):

```
mkfs.ubifs -d <target> -e 0x1f000 -c 8456 -m 0x800 -x lzo -F -v \
           -o images/rootfs.ubifs

ubinize -o images/rootfs.ubi -m 0x800 -p 0x20000 -s 2048 -v build/ubinize.cfg
```

`ubinize.cfg` generato:

```ini
[ubifs]
mode=ubi
vol_id=0
vol_type=dynamic
vol_name=rootfs
vol_alignment=1
vol_flags=autoresize
image=<…>/rootfs.ubifs
```

Geometria confermata dall'output di `ubinize` nello stesso log:

```
LEB size: 126976   PEB size: 131072   min. I/O size: 2048
sub-page size: 2048   VID offset: 2048   data offset: 4096
```

…e rileggendo l'header EC del `rootfs.ubi` prodotto:
`magic=UBI# version=1 vid_hdr_offset=2048 data_offset=4096 image_seq=0x4fad5d65`.

Mapping sui simboli Buildroot (tutti presenti **in upstream**):

| Simbolo | Valore | Nota |
|---------|--------|------|
| `BR2_TARGET_ROOTFS_UBIFS_LEBSIZE` | `0x1f000` | = `0x20000 − 2×2048` |
| `BR2_TARGET_ROOTFS_UBIFS_MINIOSIZE` | `0x800` | page 2048 B |
| `BR2_TARGET_ROOTFS_UBIFS_MAXLEBCNT` | `8456` | il vendor lo derivava da `MAX_SIZE=1024` MB; da fissare a mano |
| `BR2_TARGET_ROOTFS_UBIFS_RT_LZO` | `y` | → `-x lzo` |
| `BR2_TARGET_ROOTFS_UBIFS_OPTS` | `"-F -v"` | |
| `BR2_TARGET_ROOTFS_UBI_PEBSIZE` | `0x20000` | |
| `BR2_TARGET_ROOTFS_UBI_SUBSIZE` | `2048` | → `-s 2048` |
| `BR2_TARGET_ROOTFS_UBI_OPTS` | `"-v"` | |

> `image_seq` è **casuale a ogni build** → `rootfs.ubi` (e quindi `update.img`)
> **non è byte-riproducibile**. La verifica del criterio 4 va fatta su
> dimensioni / offset / magic, non su checksum.

#### ④ Firmware dir — `mk-firmware.sh`

Nessun tool esterno: crea `output/firmware/`, ricrea il symlink legacy
`rockdev/`, linka `parameter.txt` dal chip dir, e per ogni `*.img` verifica che
la dimensione entri nella partizione dichiarata in `parameter.txt`
(`mk-firmware.sh:52-64`). Contenuto reale osservato:

```
MiniLoaderAll.bin -> u-boot/rk3506_spl_loader_v1.04.110.bin      263K
uboot.img         -> u-boot/uboot.img                            4.0M
boot.img          -> kernel-6.1/zboot.img                        6.1M
parameter.txt     -> device/rockchip/.chips/rk3506/parameter-lyra-spinand.txt   390
rootfs.img        -> buildroot/output/rockchip_rk3506_luckfox/images/rootfs.ubi 119M
```

#### ⑤ update.img — `mk-updateimg.sh`

`package-file` generato al volo da `gen_package_file()` (nessun file `.ini`
statico: `RK_PACKAGE_FILE` è vuoto):

```
# NAME	PATH
package-file	package-file
parameter	parameter.txt
bootloader	MiniLoaderAll.bin
uboot	uboot.img
boot	boot.img
rootfs	rootfs.img
```

Comandi reali:

```
# build-trace-pack.log:3109-3111
TAG=RK$(hexdump -s 21 -n 4 -e '4 "%c"' MiniLoaderAll.bin | rev)     # -> RK350F

# build-trace-pack.log:3112
/sdk/tools/linux/Linux_Pack_Firmware/rockdev/afptool -pack ./ update.raw.img

# build-trace-pack.log:3130
/sdk/tools/linux/Linux_Pack_Firmware/rockdev/rkImageMaker \
    -RK350F MiniLoaderAll.bin update.raw.img update.img -os_type:androidos
```

`firmwareMerger` **non è usato** in questo flusso.

### Artefatti finali — dimensioni e magic (riferimento per il criterio 4)

| File | Dimensione | Primi byte | Formato |
|------|-----------:|------------|---------|
| `MiniLoaderAll.bin` | 268 736 | `4c 44 52 20` `LDR ` | Rockchip loader |
| `uboot.img` | 4 194 304 | `d0 0d fe ed` | FIT (2×itb, pad 2048K) |
| `boot.img` | 6 391 808 | `d0 0d fe ed` | FIT (zImage+fdt+resource) |
| `rootfs.img` | 124 518 400 | `55 42 49 23` `UBI#` | UBI |
| `update.img` | 135 649 866 | `52 4b 46 57` `RKFW` | Rockchip firmware |

### Python: `python2` o `python3`?

**Entrambi, ma per stage diversi.** Fonti:

| Chi | Cosa richiede | File |
|-----|---------------|------|
| **U-Boot** | **`python2`** | `common/scripts/check-loader.sh:5` → `if ! which python2 …; then … exit 1` |
| Kernel | `python3` (+ `python-is-python3`) | `common/scripts/check-kernel.sh:84,102` |
| SDK / repo | `python3` | `common/scripts/check-sdk.sh:38`, `mk-all.sh:79`, `post-info.sh:18` |
| Yocto | `python3` | `common/scripts/check-yocto.sh:12-17` |

**Verificato empiricamente**: eseguendo `build.sh` su un host senza `python2`,
la build si ferma esattamente lì (`build-trace.log`, primo run):

```
+ /sdk/device/rockchip/common/scripts/check-loader.sh
+ which python2
Your python2 is missing for U-Boot
ERROR: Running …/mk-loader.sh - build_uboot failed!
```

Gli script che usano davvero python2 sono in U-Boot 2017.09:
`arch/arm/mach-rockchip/make_fit_atf.py`, `decode_bl31.py`,
`scripts/dtc/pylibfdt/setup.py`, `tools/{binman,dtoc,patman,buildman}`.

> Nel percorso RK3506 (ARM 32-bit, OP-TEE, `tos.sh` e non `atf.sh`)
> `make_fit_atf.py` **non** viene eseguito, ma `check-loader.sh` è un gate
> incondizionato: senza `python2` la build non parte. Va tenuto nel Dockerfile.

### `rkbin/tools`: x86-64 o i386?

`file` su ciascun eseguibile di `$SDK/rkbin/tools/`:

| Tool | Arch |
|------|------|
| `boot_merger` | x86-64 (static) |
| `mkimage` | x86-64 (PIE, dyn) |
| `resource_tool` | x86-64 (dyn) |
| `mkkrnlimg` | x86-64 (dyn) |
| `trust_merger` | x86-64 (PIE, dyn) |
| `loaderimage` | x86-64 (PIE, dyn) |
| `kernelimage` | x86-64 (PIE, dyn) |
| `ddrbin_tool` | x86-64 (dyn) |
| `bmp2gray16` | x86-64 (dyn) |
| `rkdeveloptool` | x86-64 (dyn) |
| `upgrade_tool` | x86-64 (static) |
| `rk_sign_tool` | x86-64 (static) |
| `gpt2env` | x86-64 (static) |
| `programmer_image_tool` | x86-64 (static) |
| **`firmwareMerger`** | **ELF 32-bit i386** |

E in `$SDK/tools/linux/Linux_Pack_Firmware/rockdev/`:
`afptool` = x86-64 static, `rkImageMaker` = x86-64 static.

**Conclusione:** l'unico binario i386 è `firmwareMerger`, che **non è nella
catena di packaging** (update.img usa `afptool` + `rkImageMaker`). Quindi:

* `gcc-multilib` / `g++-multilib` nel Dockerfile sono **superflui** — non si
  compila nulla a 32 bit, si eseguirebbero solo binari già compilati;
* `libc6:i386` serve **solo** se si vuole poter eseguire `firmwareMerger`.
  Per questo porting non serve neanche quello.

---

## 2. Scelta libc: glibc, non musl

**Verdetto: glibc.** Non è una preferenza, è un vincolo binario.

Evidenza raccolta sull'SDK:

1. Il vendor usa glibc: `$SDK/buildroot/configs/rockchip/base/common.config` →
   `BR2_TOOLCHAIN_BUILDROOT_GLIBC=y`. Confermato nel `.config` generato:
   `BR2_TOOLCHAIN_USES_GLIBC=y`, `BR2_PACKAGE_GLIBC=y`.
2. **417 shared object ARM precompilati** in `$SDK/external` e `$SDK/prebuilts`
   (`find … -name '*.so*' | wc -l`). Campionandoli con `readelf -d`, **tutti**
   dichiarano `libc.so.6` e `ld-linux-armhf.so.3` — cioè glibc:
   `librkwifibt.so`, `librkdemuxer.so`, `libgraphic_lsf.so`, `librk_gdc_core.so`,
   `libturbojpeg.so`, `libod_share.so`, `libmd_share.so`, … Diversi tirano
   anche `libstdc++.so.6`.
   Il path stesso lo dichiara: `external/common_algorithm/misc/lib/**arm-rockchip830-linux-gnueabihf**/`.
3. La toolchain vendor per kernel/U-Boot è
   `prebuilts/gcc/linux-x86/arm/gcc-arm-10.3-2021.07-x86_64-arm-none-linux-**gnueabihf**`.

Con musl quei `.so` **non caricano**: manca `ld-linux-armhf.so.3` e i simboli
glibc-only. Esistono shim, ma introducono un rischio sproporzionato rispetto al
guadagno (qualche MB di rootfs) su una NAND da 256 MiB con 224 MiB di rootfs.

Per l'hello world in Go con `CGO_ENABLED=0` la libc sarebbe **indifferente** (il
binario è statico); la scelta è dettata dal voler restare compatibili con i blob
vendor il giorno in cui servissero.

Toolchain risultante da replicare (valori reali dal `.config` generato dell'SDK,
`$SDK/buildroot/output/rockchip_rk3506_luckfox/.config`):

```
BR2_arm=y                       BR2_cortex_a7=y
BR2_ARM_CPU_ARMV7A=y            BR2_ARM_EABIHF=y
BR2_ARM_FPU_NEON_VFPV4=y        BR2_ARM_INSTRUCTIONS_ARM=y
BR2_ARM_CPU_HAS_NEON=y          BR2_ARM_CPU_HAS_VFPV4=y
BR2_TOOLCHAIN_BUILDROOT_GLIBC=y BR2_TOOLCHAIN_BUILDROOT_CXX=y
BR2_GCC_VERSION="12.4.0"        BR2_BINUTILS_VERSION="2.40"
BR2_INIT_BUSYBOX=y              BR2_ROOTFS_MERGED_USR=y
```

(Con Buildroot upstream recente gcc/binutils saranno più nuovi; il target
ARMv7-A / hard-float / NEON resta identico.)

---

## 3. Buildroot upstream: quale tag

Lo stato attuale del submodule `$WORK/buildroot` è **`2026.05.1`**, che **non è
LTS** (le LTS Buildroot sono le release `YYYY.02.x`).

Tag LTS disponibili nel clone, più recenti: `2026.02`, `2026.02.1`, `2026.02.2`,
**`2026.02.3`**.

**Raccomandazione: pinnare il submodule a `2026.02.3`.** Verificato che tutto
ciò che serve è presente in upstream a quel livello:

* `BR2_cortex_a7` → seleziona `ARM_CPU_ARMV7A` + `NEON` + `VFPV4`
  (`arch/Config.in.arm:190-196`)
* `package/pkg-golang.mk` (infrastruttura `golang-package`) presente
* `BR2_PACKAGE_HOST_GO_TARGET_ARCH_SUPPORTS` accetta `BR2_arm` purché
  `BR2_TOOLCHAIN_SUPPORTS_PIE` (`package/go/Config.in.host:8`) — soddisfatto da glibc/ARMv7
* `fs/ubi` + `fs/ubifs` con tutti i simboli della tabella in §1c③

---

## Tabella dei TODO, ordinati per criticità sul boot

| # | Criticità | TODO(verify) | Perché blocca | Come rispondere |
|---|-----------|--------------|---------------|-----------------|
| ~~**1**~~ | ✅ **Risolto** | Mirror pubblicati su `github.com/wdalmut/rk3506-kernel` e `…/rk3506-uboot`, ricostruiti come commit senza parent che riusano l'oggetto tree vendor (contenuto identico bit per bit, SHA diverso perché cambiano i parent). Procedura in `docs/mk-vendor-mirror.sh`. | — | Verificato: `git ls-remote` risponde, e Buildroot clona e costruisce. |
| ~~**2**~~ | ✅ **Risolto** | Gli SHA pinnati sono la tip del branch `luckfox-linux-6.1-rk3506` su entrambi i mirror, quindi raggiungibili da un ref. | — | Resta consigliato pushare anche i tag `vendor-*`: se un domani il branch si sposta, il pin sopravvive solo grazie al tag. |
| ~~**3**~~ | ✅ **Risolto** | Il blob DDR arriva da un path configurabile (`BR2_LYRA_RKBIN_DIR`), non è copiato nel repo, e `post-image.sh` ne verifica lo sha256 contro `board/lyra-plus/rkbin.sha256` fermandosi se non combacia. | — | Verificato in entrambi i versi: passa sul rkbin buono, fallisce su un hash alterato. |
| **4** | 🟠 Alta | `TODO(verify):` per **SPI NAND**, a quale offset il BootROM RK3506 si aspetta l'IDB/loader? Accertato solo che i primi 4 MiB sono riservati (nessuna partizione in `parameter.txt`) e che per SD/eMMC è il settore 64. | Serve per documentare il flash manuale e per validare che `post-image.sh` produca un layout scrivibile. | Leggere `docs/{cn,en}/Linux/ApplicationNote/Rockchip_Developer_Guide_Linux_Flash_Open_Source_Solution_*.pdf` (presenti in `$SDK/docs/`), o dumpare la NAND di una board già funzionante. |
| **5** | 🟡 Media | `TODO(verify):` la SPI NAND è davvero da **256 MiB**, con page 2048 B e blocco 128 KiB? | Determina la dimensione reale di `rootfs` (`-@…:grow`) e la validità di LEB/PEB/min-I/O usati da `mkfs.ubifs`/`ubinize`. Se sbagliati il rootfs non monta. | `cat /proc/mtd` e `dmesg | grep -i nand` su board funzionante. Indizio forte a favore di 256 MiB: il `parameter.txt` locale piazza `amp` a `0x7f300` (254.625 MiB). |
| **6** | 🟡 Media | `TODO(verify):` la console seriale è fisicamente su UART0 (SoC) o sul connettore serigrafato "UART2"? | Non blocca il boot ma se il cavo va sul pettine sbagliato non si vede nulla e sembra un boot fallito. | Il DTS è inequivoco (`rockchip,serial-id = <0>` → `0xff0a0000`); resta da mappare quale header della Lyra Plus porta quei pin. Verificare su schematico o provando a 1500000 8N1. |
| **7** | 🟢 Bassa | `TODO(verify):` quanti commit di divergenza ha il Buildroot dell'SDK rispetto a `2024.02`? | Solo documentale: la decisione (non riportare nulla) è già presa sulla base della diff ad albero. | Impossibile in locale (`depth=1`). Serve un clone completo dal remote di TODO-1. |
| **8** | 🟢 Bassa | ~~Replicare l'AMP locale?~~ **DECISO: no.** La Fase 2 usa il baseline vendor: solo Linux, partizioni `uboot`/`boot`/`rootfs`. | — | Se servirà, il delta è documentato in §0 e §1b di questo file. |
| ~~**9**~~ | ✅ **Risolto** | U-Boot 2017.09 non compilava con GCC 13. Enumerando la coda in una passata con `KCFLAGS=-Wno-error` sono emerse tre sole classi di warning. | — | Quattro patch numerate in `external/board/lyra-plus/patches/uboot/`: due falsi positivi `maybe-uninitialized`, una divergenza reale dichiarazione/definizione (`cmd_process`), un bug vero di lettura fuori array (`bmp2gray16`). |

---

## Nota di trasparenza sull'esecuzione

Il primo tentativo di trace è stato lanciato **sull'host** anziché nel
container. `build.sh` esegue `rm -f u-boot/*.bin u-boot/*.img` **prima** del
check `python2` (`mk-loader.sh:31-35`), e `mk-firmware.sh` fa
`rm -rf "$RK_FIRMWARE_DIR"`: entrambe le cose sono avvenute, poi la build si è
fermata sul check. Ho quindi rieseguito la build **nel container**
(`wdalmut/luckfox-lyra:latest`), che ha **rigenerato** `u-boot/*.bin`,
`u-boot/uboot.img`, `kernel-6.1/zboot.img` e `output/firmware/`. Verificato a
posteriori:

* `$SDK/u-boot/`: `rk3506_spl_loader_v1.04.110.bin`, `rk3506_idblock_v1.04.110.img`,
  `uboot.img`, `u-boot.bin`, `tee.bin` — tutti presenti
* `$SDK/output/firmware/`: `MiniLoaderAll.bin`, `uboot.img`, `boot.img`,
  `parameter.txt`, `rootfs.img`, `update.img` — tutti presenti
* `buildroot/output/rockchip_rk3506_luckfox/images/rootfs.ubi` (124 MB, del
  build precedente) **non è mai stato toccato**

Lo stage buildroot non è stato rieseguito: fallisce sul `BR2_EXTERNAL` residuo
`/home/walter/git/test-lyra/br2-external`, che **preesisteva** nel `.config` e
non è stato introdotto da questa ricognizione.

---

## Decisioni di Fase 2

Prese dopo la consegna della ricognizione, e già riflesse nei file
dell'external tree.

| Tema | Decisione | Dove vive |
|------|-----------|-----------|
| Mirror kernel/U-Boot | GitHub `wdalmut/rk3506-kernel` e `wdalmut/rk3506-uboot`, pubblici | `external/configs/*_defconfig` |
| Tag Buildroot | `2026.02.3` (LTS) invece di `2026.05.1` | submodule `buildroot/` |
| AMP | fuori scope: solo Linux, partizioni vendor | — |
| libc | glibc (417 `.so` vendor linkati a `libc.so.6`) | vedi nota qui sotto: serve `BR2_PACKAGE_HOST_LINUX_HEADERS_CUSTOM_6_1` |
| GCC | pinnato 13.x, la più vecchia in 2026.02.3 | `BR2_GCC_VERSION_13_X` |
| Patch a Buildroot | nessuna: le modifiche vendor rilevanti sono comodità | `external/patches/` vuota |
| Blob rkbin | path configurabile + verifica sha256, mai copia cieca | `BR2_LYRA_RKBIN_DIR`, `board/lyra-plus/rkbin.sha256` |
| `uboot.img` | prodotto da `u-boot/scripts/fit.sh`, non da `make.sh` | `board/lyra-plus/post-image.sh` |
| Fragment display | `rk3506-display.config` **non** applicato (immagine da seriale) | `board/lyra-plus/linux.config` |

### Perché `fit.sh` e non `make.sh`

Il trace mostra che l'SDK esegue `./make.sh <board> --spl-new`, che compila e
poi chiama `scripts/fit.sh` (build-trace.log:2322 → 4056). Riprodurre il primo
comando dentro `post-image.sh` avrebbe due difetti:

1. `make.sh <board>` rifà `make <board>_defconfig` (make.sh:252-254),
   sovrascrivendo il `.config` che Buildroot ha appena costruito **fondendoci
   `BR2_TARGET_UBOOT_CONFIG_FRAGMENT_FILES`**. Il fragment andrebbe perso in
   silenzio.
2. ricompilerebbe U-Boot una seconda volta.

`fit.sh` invece non ricompila (`fit_raw_compile()` ricostruisce solo con
`--sign`, fit-core.sh:231-238) e non tocca `.config`. E `make.sh` non ha
nessun `export`, quindi `fit.sh` — lanciato come processo separato — è
autonomo: chiamarlo direttamente da `post-image.sh` è equivalente.

Resta la dipendenza scoperta in ricognizione: la catena pretende `rkbin` come
directory **fratello** di U-Boot (`prepare()` controlla `-d ../rkbin`,
make.sh:105). `post-image.sh` la soddisfa con un symlink in
`$(BUILD_DIR)/rkbin`, senza toccare il checkout read-only.

### glibc si ottiene solo dichiarando la serie degli header

Scoperto costruendo: con il defconfig scritto "come da manuale", la toolchain
risultante era **uClibc**, non glibc — senza nessun errore.

Catena causale, verificata sui sorgenti di Buildroot 2026.02.3:

1. il default degli header e' `BR2_KERNEL_HEADERS_AS_KERNEL` ("gli stessi del
   kernel che costruisco");
2. il kernel arriva da `BR2_LINUX_KERNEL_CUSTOM_GIT`, quindi Buildroot non ne
   conosce la versione. In `linux/Config.in:31-65` solo le versioni *note*
   fanno `select BR2_TOOLCHAIN_HEADERS_AT_LEAST_* if BR2_KERNEL_HEADERS_AS_KERNEL`;
   per un repo custom nessuno lo fa;
3. `BR2_PACKAGE_GLIBC_SUPPORTS` ha `depends on BR2_TOOLCHAIN_HEADERS_AT_LEAST_3_2`
   (`package/glibc/Config.in:38`), quindi resta `n`;
4. `BR2_TOOLCHAIN_BUILDROOT_GLIBC` ha `depends on BR2_PACKAGE_GLIBC_SUPPORTS`
   (`toolchain/toolchain-buildroot/Config.in:39`) e **sparisce dalla choice**,
   nonostante ne sia il `default`;
5. Kconfig sceglie la prima voce disponibile: uClibc-ng.

Rimedio: dichiarare esplicitamente la serie degli header con
`BR2_PACKAGE_HOST_LINUX_HEADERS_CUSTOM_6_1=y`
(`package/linux-headers/Config.in.host:208-210`, fa
`select BR2_TOOLCHAIN_HEADERS_AT_LEAST_6_1`). E' la stessa riga che l'SDK
Luckfox ha nel suo `configs/rockchip_rk3506_luckfox_defconfig` — dove pero'
sembra solo una delle tante, e non e' spiegata.

Effetto collaterale da conoscere: una volta che glibc torna disponibile
ridiventa il default della choice, quindi `make savedefconfig` **rimuove**
`BR2_TOOLCHAIN_BUILDROOT_GLIBC=y` dal defconfig. E' corretto. La verifica si fa
sul `.config` generato:

```bash
grep BR2_TOOLCHAIN_BUILDROOT_LIBC output/.config   # -> "glibc"
```

### Stato di verifica

Verificato eseguendolo:

- `make lyra_plus_defconfig` e `make lyra_plus_initramfs_defconfig` accettati,
  `.config` coerente (ARMv7-A / NEON-VFPv4 / **glibc**, UBI `0x1f000`/`0x800`/`8456`,
  `_CUSTOM_GIT` con gli SHA giusti)
- `make savedefconfig` idempotente su entrambi i defconfig
- `hello-lyra` compila e cross-compila ARMv7 statico (`CGO_ENABLED=0`), e gira
- tutti gli script passano `bash -n`
- il container ha tutti i tool che `post-image.sh` invoca; il calcolo del tag
  del loader (`hexdump -s 21 -n 4 | rev`) restituisce `RK350F`, identico all'SDK
- `sha256sum -c board/lyra-plus/rkbin.sha256` passa sul rkbin dell'SDK e
  fallisce su un hash alterato
- il controllo dimensioni-contro-`parameter.txt` di `post-image.sh`, eseguito
  sulle immagini reali dell'SDK, riporta `uboot 4.00/4.00 MiB OK`,
  `boot 6.10/12.00 MiB OK`, `rootfs 118.75 MiB (grow)`
- **build reale, fin dove e' possibile**: `make hello-lyra` costruisce
  `host-go-bin 1.26.3`, `host-binutils 2.44` e **`host-gcc-initial 13.4.0`**
  per il triplet **`arm-buildroot-linux-gnueabihf`** — cioe' GCC 13 regge la
  toolchain ARMv7 hard-float/glibc. Poi si ferma su
  `linux-headers-696a8549…/.stamp_downloaded`: con `BR2_KERNEL_HEADERS_AS_KERNEL`
  anche gli header vengono dal mirror del kernel, che non esiste ancora
  (TODO-1), e il fallback su `sources.buildroot.net` da 404.

Verificato dopo la pubblicazione dei mirror:

- **la build completa termina con exit 0** e produce tutti gli artefatti
- `MiniLoaderAll.bin` (268 736 B) e `uboot.img` (4 194 304 B) hanno la
  **stessa dimensione esatta** degli omologhi dell'SDK
- `boot.img` ha la stessa struttura FIT del `boot.img` dell'SDK, verificata
  con `fdtget` su entrambi
- `rootfs.img` ha la stessa geometria UBI (`vid_hdr_offset=2048`, `data_offset=4096`)
- `hello-lyra` nel rootfs è un ELF ARM 32-bit statically linked

**Non** ancora verificato:

- il boot reale su hardware
- `./setup.sh` da un clone davvero pulito (è stato eseguito su questo albero)

---

## Due trappole della catena vendor, emerse solo costruendo

Nessuna delle due è deducibile leggendo gli script: si manifestano al primo
`post-image.sh` reale.

### 1. `make.sh` risolve la toolchain a ogni invocazione, anche nei sotto-comandi

`select_toolchain()` gira incondizionatamente (make.sh:797), quindi anche per
`./make.sh itb` e `./make.sh --spl`, che `fit.sh` richiama al suo interno. Se
`CROSS_COMPILE=` non è sulla riga di comando, ripiega sui prebuilt hardcoded
dell'SDK (make.sh:15):

```
CROSS_COMPILE_ARM32=../prebuilts/gcc/linux-x86/arm/gcc-linaro-6.3.1-.../arm-linux-gnueabihf-
```

Quella directory non esiste nella build dir di Buildroot, il `cd` fallisce, e
si ottiene:

```
ERROR: No find /work/output/build/uboot-<sha>/arm-linux-gnueabihf-gcc
```

Il meccanismo previsto per questo caso è il file cache `.cc` (make.sh:274-276):
se esiste nella radice di U-Boot, `select_toolchain()` legge da lì il prefisso
invece di indovinarlo. `post-image.sh` ce lo scrive con la toolchain di
Buildroot, prima di chiamare `fit.sh`.

### 2. La catena scrive **dentro** rkbin, quindi read-only non basta

`spl.sh:54` fa `rm tmp -rf && mkdir tmp -p` nella **radice di rkbin**, dove poi
copia lo SPL e l'`.ini` modificato; `boot_merger` ci deposita il loader prodotto
prima che `make.sh` lo sposti via. Con l'SDK montato read-only:

```
mkdir: cannot create directory 'tmp': Read-only file system
```

Un symlink `$(BUILD_DIR)/rkbin -> /sdk/rkbin` **non** risolve: si scrive
attraverso il link. Serve una copia di lavoro vera. rkbin è 57 MB, quindi
`post-image.sh` la rsyncia in `$(BUILD_DIR)/rkbin` a ogni build. Il checkout
puntato da `BR2_LYRA_RKBIN_DIR` resta intatto e può stare su un mount `:ro`.

> Sottigliezza: se una versione precedente aveva lasciato lì un symlink,
> `mkdir -p` lo attraversa e `rsync` scrive nell'SDK. `post-image.sh` rimuove
> esplicitamente un eventuale symlink prima di creare la directory.

### Esito

Con queste due correzioni la build arriva in fondo:

```
BUILD EXIT=0
    MiniLoaderAll.bin          268736 B  magic=4c 44 52 20
    uboot.img                 4194304 B  magic=d0 0d fe ed
    boot.img                  5745664 B  magic=d0 0d fe ed
    rootfs.img                5767168 B  magic=55 42 49 23
    update.img               16253514 B  magic=52 4b 46 57
    flash.img                39321600 B  magic=00 00 00 00
```

`MiniLoaderAll.bin` e `uboot.img` hanno **la stessa dimensione esatta** degli
omologhi prodotti dall'SDK; `boot.img` ha la stessa struttura FIT
(`fdt`/`kernel`/`resource`, `multi=resource`) e `rootfs.img` la stessa
geometria UBI (`vid_hdr_offset=2048`, `data_offset=4096`).
