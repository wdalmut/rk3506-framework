# Scelte di progetto

Il *perche'* delle decisioni prese in questo albero. Per costruire e usare il
repository basta il [README](../README.md); questo documento serve quando ci si
chiede "perche' e' fatto cosi'" prima di cambiare qualcosa.

I fatti su cui queste scelte si appoggiano — con la fonte esatta di ogni
valore — stanno in [BOARD-FACTS.md](BOARD-FACTS.md).

---



## Buildroot 2026.02.3, non 2026.05.x

Le LTS Buildroot sono le release `YYYY.02.x`. `setup.sh` avvisa se il
submodule finisce su un tag non-LTS.

## glibc, non musl — e una trappola da non reintrodurre

Non e' una preferenza estetica, e' un vincolo binario. Nell'SDK ci sono **417
shared object ARM precompilati** (`external/`, `prebuilts/`) e, campionandoli
con `readelf -d`, dichiarano tutti `libc.so.6` e `ld-linux-armhf.so.3`: sono
glibc. Alcuni tirano anche `libstdc++.so.6`. Il path stesso lo dice:
`external/common_algorithm/misc/lib/arm-rockchip830-linux-gnueabi**hf**/`.
Con musl non caricano.

Per `hello-lyra` la libc sarebbe indifferente — Go con `CGO_ENABLED=0` produce
un binario statico — ma la scelta e' fatta pensando al giorno in cui servira'
un blob vendor (RGA, rockit, wifibt). Il vendor stesso usa glibc
(`BR2_TOOLCHAIN_BUILDROOT_GLIBC=y` in `configs/rockchip/base/common.config`).

> ⚠️ **`BR2_PACKAGE_HOST_LINUX_HEADERS_CUSTOM_6_1=y` non e' decorativo: e' cio'
> che rende glibc selezionabile.** Senza quella riga il porting finisce su
> uClibc **in silenzio**, ed e' successo davvero durante lo sviluppo di questo
> albero.
>
> Il meccanismo: il default e' `BR2_KERNEL_HEADERS_AS_KERNEL`, cioe' "gli header
> sono quelli del kernel che costruisco". Ma il kernel arriva da `_CUSTOM_GIT`,
> quindi Buildroot non ne conosce la versione e nessun
> `BR2_TOOLCHAIN_HEADERS_AT_LEAST_*` viene selezionato
> (`linux/Config.in:31-65`: solo le versioni note lo fanno). Di conseguenza
> `BR2_PACKAGE_GLIBC_SUPPORTS` — che `depends on BR2_TOOLCHAIN_HEADERS_AT_LEAST_3_2`
> (`package/glibc/Config.in:38`) — resta a `n`, glibc **sparisce dalla choice**,
> e Kconfig ripiega sulla prima voce disponibile: uClibc. Nessun errore, nessun
> avviso.
>
> Dichiarare la serie 6.1 riaccende `BR2_TOOLCHAIN_HEADERS_AT_LEAST_6_1` e
> quindi glibc. E' la stessa riga che ha nel suo defconfig anche l'SDK Luckfox.
>
> Secondo effetto, controintuitivo: una volta che glibc torna disponibile
> ridiventa **il default della choice**, quindi `make savedefconfig` **cancella**
> `BR2_TOOLCHAIN_BUILDROOT_GLIBC=y` dal defconfig. E' corretto e va lasciato
> cosi'; per verificare che la libc sia quella giusta si guarda il `.config`:
>
> ```bash
> grep BR2_TOOLCHAIN_BUILDROOT_LIBC output/.config
> # atteso: BR2_TOOLCHAIN_BUILDROOT_LIBC="glibc"
> ```

## Toolchain

`BR2_cortex_a7` seleziona da solo ARMv7-A, NEON e VFPv4; l'ABI hard-float e'
la conseguenza. Il defconfig fissa esplicitamente solo
`BR2_ARM_FPU_NEON_VFPV4`. GCC e' pinnato a **13.x**, la piu' vecchia
disponibile in 2026.02.3: U-Boot 2017.09 e' del 2017 e piu' il compilatore e'
recente piu' aumenta il rischio.

## Nessuna patch a Buildroot

`external/patches/` e' vuota di proposito. La Fase 1 ha confrontato il
Buildroot dell'SDK con l'upstream `2024.02` da cui deriva: 452 file aggiunti,
242 modificati, ma tutto cio' che tocca il percorso di questa board (`fs/ubi`,
`fs/ubifs`, `linux/linux.mk`, `arch/Config.in.arm`) e' **comodita', non
funzionalita' mancante**. Esempio: il vendor aggiunge
`BR2_TARGET_ROOTFS_UBIFS_MAX_SIZE` in MB che calcola `MAXLEBCNT`; noi
impostiamo `MAXLEBCNT=8456` a mano e otteniamo lo stesso `mkfs.ubifs -c 8456`.
Dettaglio voce per voce in `docs/BOARD-FACTS.md` §1a.

## U-Boot: perche' `post-image.sh` richiama `scripts/fit.sh`

Buildroot possiede U-Boot (download, patch, config, build): e' cosi' che
`_CUSTOM_GIT` e le patch numerate funzionano. Ma la produzione di `uboot.img`
non e' un `objcopy`: e' un FIT con OP-TEE come `firmware` e U-Boot come
`loadables`, il cui `.its` viene **generato** da `scripts/fit-core.sh` (~600
righe). Riscriverlo sarebbe un fork mascherato.

`post-image.sh` chiama quindi il codice vendor — ma **`scripts/fit.sh`, non
`make.sh`**. La differenza conta:

- `./make.sh <board>` rifa' `make <board>_defconfig`, che sovrascrive il
  `.config` prodotto da Buildroot e butta via il merge di `uboot.config`.
  Fallirebbe in silenzio, dando un U-Boot configurato diversamente da quello
  che il defconfig dichiara.
- `scripts/fit.sh` non ricompila: `fit_raw_compile()` ricostruisce solo con
  `--sign` (`fit-core.sh:231-238`). Niente doppia build.

E' comunque la stessa invocazione che `make.sh` fa subito dopo aver compilato
(`trace di `build.sh``), e `make.sh` non esporta variabili d'ambiente: `fit.sh`
e' un processo autonomo, quindi chiamarlo direttamente e' equivalente.

Un dettaglio che fa fallire questo passo se non lo si conosce: la catena
pretende `rkbin` come **directory fratello** — `prepare()` controlla
`-d ../rkbin` e aborta con `ERROR: No ../rkbin repository` (`make.sh:105`).
`post-image.sh` crea un symlink in `$(BUILD_DIR)/rkbin`, senza toccare il
checkout puntato da `BR2_LYRA_RKBIN_DIR`, che resta read-only.

## Perche' `linux.config` non include `rk3506-display.config`

Il defconfig di board dell'SDK aggiunge quel fragment (DRM/VOP/DSI, ~23 KB di
simboli). Qui no: questa e' una immagine da console seriale. Conseguenza
attesa: `console=tty1` nel bootargs del DTS non trova un framebuffer e viene
ignorato, `/dev/console` resta su `ttyFIQ0`. Per riabilitarlo, copiare il
fragment accanto a `linux.config` e aggiungerlo a
`BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES`.

## Il Dockerfile e' piu' magro di quello dell'SDK

`file` su ogni tool di `rkbin/tools/` e di `Linux_Pack_Firmware/rockdev/`: sono
tutti x86-64. L'unico binario i386 e' `firmwareMerger`, che **non e' nella
catena** (`update.img` usa `afptool` + `rkImageMaker`). Quindi via
`gcc-multilib` e `g++-multilib`, e non serve neanche `libc6:i386`.

`python2` invece **resta**: e' un gate incondizionato per U-Boot 2017.09, e
sull'host senza python2 la build si ferma esattamente li' (verificato).

## AMP fuori scope

Il checkout SDK di riferimento aveva modifiche locali che accendono l'AMP
(RT-Thread sul terzo core A7, partizioni `config` e `amp`, `amp_miranda.its`).
Questo albero parte dal **baseline vendor**: solo Linux, partizioni
`uboot`/`boot`/`rootfs`.

---

---

## Le quattro patch a U-Boot


GCC 13 e' molto piu' severo di quello del 2017 usato dal BSP, e il BSP compila
con `-Werror`. La coda si e' rivelata corta: enumerandola in una sola passata
con `KCFLAGS=-Wno-error` sono emerse **tre sole classi** di warning, tutte
risolte con patch minime invece che disattivando `-Werror` (che avrebbe
nascosto anche i warning veri).

| Patch | Cosa | Falso positivo? |
|-------|------|-----------------|
| `0001` | `common/edid.c`: `hdmi_len` non inizializzata | Si': `hdmi` e `hdmi_len` sono assegnate insieme, GCC non correla le due variabili |
| `0002` | `pinctrl-rockchip{,-core}.c`: puntatore `data` in 4 punti | Si': se il contatore e' 0 il ciclo non gira, ma la guardia successiva ritorna prima di dereferenziare |
| `0003` | `include/command.h`: `cmd_process()` dichiarata `int`, definita `enum command_ret_t` | **No**: divergenza reale fra dichiarazione e definizione, che GCC < 13 non segnalava |
| `0004` | `tools/rockchip/bmp2gray16.c`: `static const char version[4] = "1.00"` | **No**: bug vero, `printf("%s")` legge oltre l'array perche' il `[4]` scarta il NUL |
| ~~**9**~~ | ✅ | **Risolto.** U-Boot 2017.09 non compilava con GCC 13: quattro patch in `external/board/lyra-plus/patches/uboot/` (vedi sotto). |

---

## USB: perche' non usiamo `usbdevice` dell'SDK



`rkscript` installa `/usr/bin/usbdevice`, **725 righe** che gestiscono adb,
rndis, ums, mtp, ptp, uvc, ntb, hid e midi. Tirarlo dentro significherebbe
portare nell'external tree un package vendor intero per usarne un decimo.
`S45adb` fa la stessa cosa per il caso che ci serve in ~40 righe leggibili.

Un dettaglio che non e' opzionale, e che e' il motivo per cui lo script e'
piu' lungo di quanto sembrerebbe necessario: **con functionfs l'ordine
conta.** Il demone in user space deve scrivere i descrittori su `ep0` *prima*
che il gadget venga legato all'UDC. Scrivere su `UDC` troppo presto fa
fallire il bind, o fa enumerare un device senza endpoint. Quindi:

1. crea gadget e funzione `ffs.adb`
2. monta functionfs
3. avvia `adbd`, che apre `ep0` e scrive i descrittori
4. **aspetta** che compaiano `ep1`/`ep2`
5. collega la funzione alla config
6. solo ora `echo <udc> > UDC`

E' la stessa sequenza di `usbdevice` e di Android. Il passo 4 e' una
attesa esplicita con timeout: se scade, lo script **non** lega l'UDC e lo
dice, invece di lasciare un gadget mezzo configurato che enumera male.

### Costo

adbd tira dentro openssl: il rootfs passa da 5,5 a 8,6 MiB, quasi tutto
`libcrypto.so.3` (3,7 MB). Su una partizione rootfs da 224 MiB non e' un
problema; su un target piu' stretto si toglie togliendo
`BR2_PACKAGE_ANDROID_TOOLS_ADBD` dal defconfig e `S45adb` dall'overlay.
## Due trappole della catena vendor, trovate solo costruendo

Nessuna delle due è deducibile leggendo gli script: si manifestano al primo
`post-image.sh` reale.

### `make.sh` risolve la toolchain a ogni invocazione, anche nei sotto-comandi

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

### La catena scrive **dentro** rkbin, quindi read-only non basta

`spl.sh:54` fa `rm tmp -rf && mkdir tmp -p` nella **radice di rkbin**, dove poi
copia lo SPL e l'`.ini` modificato; `boot_merger` ci deposita il loader prodotto
prima che `make.sh` lo sposti via. Con l'SDK montato read-only:

```
mkdir: cannot create directory 'tmp': Read-only file system
```

Un symlink `$(BUILD_DIR)/rkbin -> vendor/rkbin` **non** risolve: si scrive
attraverso il link, quindi si sporca il submodule. Serve una copia di lavoro
vera. rkbin è 57 MB, quindi `post-image.sh` la rsyncia in
`$(BUILD_DIR)/rkbin` a ogni build. La sorgente puntata da
`BR2_LYRA_RKBIN_DIR` resta intatta, e può anche stare su un mount `:ro`.

> Sottigliezza: se una versione precedente aveva lasciato lì un symlink,
> `mkdir -p` lo attraversa e `rsync` scrive nella sorgente. `post-image.sh`
> rimuove esplicitamente un eventuale symlink prima di creare la directory.

---

## Il percorso mainline 6.19, accanto al vendor 6.1

`lyra_plus_mainline_initramfs_defconfig` costruisce la stessa board con un
kernel **mainline 6.19.0** invece del vendor 6.1.99. È un terzo percorso, non
una sostituzione: i due defconfig vendor restano come termine di paragone.
Quando il mainline non arriva al prompt, la domanda "è il kernel o è il
packaging?" si risponde flashando l'altro.

Cosa cambia, e perché:

| | vendor | mainline |
|---|---|---|
| kernel | `rk3506-kernel.git` 6.1.99 | `rk3506-kernel-upstream.git` 6.19.0 |
| defconfig kernel | `rk3506_luckfox` | `multi_v7` + fragment |
| fragment | `linux.config` | `linux-mainline.config` |
| DTB | in-tree o custom, senza sottodirectory | `rockchip/rk3506g-luckfox-lyra-plus` |
| console | `ttyFIQ0` (fiq-debugger) | `ttyS0` (8250-dw) |
| storage | SPI NAND / UBI, oppure initramfs | solo initramfs |
| `resource_tool` | dal kernel | host package `rk-resource-tool` |
| U-Boot | invariato: stesso repo, stesso SHA, stesso fragment | idem |

`ttyFIQ0` non esiste in mainline: è la tty del *FIQ debugger* Rockchip
(`CONFIG_FIQ_DEBUGGER`), che non è mai stato mandato upstream. La stessa UART0
`@0xff0a0000` viene quindi guidata dal driver 8250-dw standard e si chiama
`ttyS0`. Il baudrate resta **1500000**, non 115200.

### I bootargs arrivano dal kernel, non dal DTS

`linux-mainline.config` imposta `CONFIG_CMDLINE` + `CONFIG_CMDLINE_FORCE=y`.
Il DTS in-tree ha solo `stdout-path` (`rk3506g-luckfox-lyra-plus.dts:14-16`),
mentre il DTS custom vendor si portava dietro i bootargs in `/chosen`.
`CMDLINE_FORCE` fa una cosa sola ma utile: toglie U-Boot dall'equazione. Se la
board resta muta, la cmdline non è tra i sospetti. Ottenuto il prompt si può
rilassare.

### `resource.img`: perché è obbligatorio

Verrebbe voglia di togliere il nodo `resource` da `boot.its` e chiudere la
questione senza vendorizzare niente. **Non si può**, e la ragione è nel
sorgente di U-Boot.

Con `CONFIG_ROCKCHIP_RESOURCE_IMAGE=y` (attivo: si legge in
`output/build/uboot-*/.config`) il ramo che leggerebbe il DTB dal nodo `fdt`
del FIT è compilato via:

```c
/* arch/arm/mach-rockchip/boot_rkimg.c:516-519 */
} else if (where == LOCATE_FIT) {
#if defined(CONFIG_ROCKCHIP_FIT_IMAGE) && !defined(CONFIG_ROCKCHIP_RESOURCE_IMAGE)
        return fit_image_read_dtb(fdt);
#endif
```

L'unica via che resta è `LOCATE_RESOURCE` (`boot_rkimg.c:491-497`), cioè
`rockchip_read_resource_dtb()` → `resource_scan()` → `fit_image_init_resource()`
(`fit.c:439`), che cerca il nodo `multi` e senza quello ritorna `-EINVAL`
(`fit.c:453-455`). Il risultato a runtime è `Failed to load DTB, ret=-22`
seguito da `No valid DTB` (`boot_rkimg.c:499` e `:536`), e il boot si ferma
lì.

Detto in una riga: **U-Boot prende il DTB del kernel da `resource.img`, non dal
nodo `fdt` del FIT.** `resource.img` non è un accessorio per i logo di boot.

Togliere il nodo avrebbe quindi richiesto di spegnere
`CONFIG_ROCKCHIP_RESOURCE_IMAGE` in U-Boot, cioè cambiare il bootloader — e
il senso di questo defconfig è cambiare **solo** il kernel, per avere un
confronto pulito. Quindi: `resource_tool` vendorizzato.

### `resource_tool` come host package, non compilato al volo

Nel kernel vendor il tool si costruisce da sé, perché `scripts/Makefile:9` lo
dichiara `hostprogs-always-$(CONFIG_ARCH_ROCKCHIP)`. In mainline
`scripts/resource_tool.c` non esiste: non è mai stato mandato upstream.

Il sorgente è vendorizzato in `external/package/rk-resource-tool/src/`, con
provenienza, sha256 e licenza in
[../external/package/rk-resource-tool/README.md](../external/package/rk-resource-tool/README.md) —
la stessa disciplina che `board/lyra-plus/rkbin.sha256` applica ai blob.

È un **host package Buildroot** e non un `cc` dentro `post-image.sh`, per
quattro motivi concreti:

1. `post-image.sh` gira una volta per build, alla fine. Un `cc` lì dentro
   ricompila ogni volta e, se fallisce, fallisce *dopo* trenta minuti di
   toolchain e kernel.
2. Il compilatore host e i suoi flag li decide Buildroot (`$(HOSTCC)`,
   `$(HOST_CFLAGS)`), non lo script. Nel container o fuori, sono gli stessi.
3. La dipendenza diventa **dichiarata**: `BR2_PACKAGE_HOST_RK_RESOURCE_TOOL=y`
   sta nel defconfig, si vede in `make menuconfig`, e `make legal-info` vede
   la licenza GPL-2.0+ di Rockchip invece di ignorarla.
4. `post-image.sh` resta uno script di packaging e non diventa anche un build
   system.

`post-image.sh` preferisce comunque sempre `$LINUX_DIR/scripts/resource_tool`
se c'è: il percorso vendor non cambia di una riga, e non c'è modo che i due
defconfig vendor comincino a usare il binario dell'host package senza che
nessuno l'abbia chiesto.

### `multi_v7_defconfig` non entra nella partizione `boot`

Il fragment `linux-mainline.config` spegne 72 famiglie di SoC ARM e una
quindicina di sottosistemi. Non e' zelo: senza, la build **non passa**.

`multi_v7_defconfig` e' un defconfig multi-piattaforma, accende 76 famiglie di
SoC ARMv7 e RK3506 e' una di quelle. Il risultato:

```
>>> lyra-plus: verifica dimensioni contro parameter.txt
    uboot        4.00 MiB /     4.00 MiB  OK
    boot        15.09 MiB /    12.00 MiB  TROPPO GRANDE
```

Non e' un problema di rootfs. L'initramfs e' gia' compresso *dentro* il kernel
(`CONFIG_INITRAMFS_COMPRESSION_GZIP=y`) e `arch/arm/boot/Image` non compresso
e' **34.90 MiB**: il solo kernel compresso e' circa 13 MiB, quindi non
entrerebbe nei 12 MiB nemmeno con un rootfs vuoto.

Misurato su questo albero, con la toolchain di Buildroot:

| configurazione | `zImage` | `boot.img` | entra in 12 MiB? |
|---|---|---|---|
| `multi_v7` + fragment minimale | 15.07 MiB | 15.09 MiB | no |
| + 72 piattaforme estranee spente | 12.11 MiB | ~12.13 MiB | no, per 0.13 MiB |
| + sottosistemi fuori scope spenti | 6.30 MiB | 6.32 MiB | si |
| + i 41 `SOC_*` (chiude il buco OMAP) | **6.16 MiB** | **6.18 MiB** | si, 5.8 MiB di margine |

L'ultima riga e' la configurazione attuale del fragment.

Il confronto giusto e' con l'altro defconfig **initramfs**, non con quello su
NAND: e' l'unico che mette il rootfs dentro `boot.img` come fa questo.

| defconfig | `zImage` | `rootfs.cpio` | `boot.img` |
|---|---|---|---|
| `lyra_plus_initramfs_defconfig` (vendor 6.1) | 8.83 MiB | 10.48 MiB | **10.32 MiB** |
| `lyra_plus_mainline_initramfs_defconfig` | 6.16 MiB | 4.67 MiB | **6.18 MiB** |

L'immagine mainline sfoltita e' quindi **piu' piccola** di quella vendor, non
piu' grande: il kernel e' di poco superiore (circa 4 MiB contro 4.19 MiB senza
initramfs), ma il rootfs e' meno di meta' perche' non porta ne' i tool MTD ne'
android-tools/adbd, che in questo bring-up non servono.

Tutte le misure di `zImage` sono **con l'initramfs incorporato**, perche' e'
quello che finisce in `boot.img`: Buildroot ricompila il kernel dopo aver
generato `rootfs.cpio` (`>>>   Rebuilding kernel with initramfs`). Il solo
kernel, senza initramfs, e' circa 4 MiB — la taglia del vendor. Non
e' mainline a essere grosso: e' `multi_v7_defconfig` non sfoltito.

Notare la riga di mezzo: il pruning delle sole piattaforme **non basta**,
manca per 0.13 MiB. E' il motivo per cui il fragment spegne anche
`CONFIG_NET`, `CONFIG_FTRACE`, `CONFIG_PCI` e compagnia, e non si e' fermato
alle piattaforme. Quel 12.11 viene da un esperimento incrementale (`sed` sul
`.config` gia' risolto piu' `olddefconfig`) e non da un merge pulito, quindi
va letto come ordine di grandezza; il punto che conta e' che non bastava.

### Tre simboli che il fragment non riesce a spegnere

La verifica va fatta sul `.config` **finale**, non sul fragment: `olddefconfig`
riaccende per `select` quello che qualcuno tira dentro. Su questo albero sono
tre, tutti spiegati:

| simbolo | chi lo riaccende | si puo' togliere? |
|---|---|---|
| `REGULATOR=y` | `arch/arm/mach-rockchip/Kconfig:16` — `ARCH_ROCKCHIP` fa `select REGULATOR` | **no**, e' la piattaforma che vogliamo |
| `INPUT=y` | `drivers/tty/Kconfig:14-15` — `config VT` fa `select INPUT` | si, spegnendo `CONFIG_VT`; non fatto, costa poco |
| `ARCH_OMAP=y` | `SOC_AM33XX`/`SOC_AM43XX`/`SOC_DRA7XX`/`SOC_OMAP5` fanno `select ARCH_OMAP2PLUS` (`arch/arm/mach-omap2/Kconfig`) | **si, ed e' stato fatto** |

L'ultimo era un buco vero nella lista: la prima versione intersecava solo i
simboli `ARCH_*`, e OMAP rientrava dai `SOC_*`, restando compilato dentro
nonostante `# CONFIG_ARCH_OMAP is not set`. Per questo la ricetta di
rigenerazione nel fragment copre `(ARCH|SOC)_` e non solo `ARCH_`.

#### Perche' non allargare la partizione, invece

Si poteva: fra la fine di `boot` (20 MiB) e l'inizio di `rootfs` (32 MiB) ci
sono 12 MiB non allocati, quindi `boot` potrebbe passare da `0x6000` a
`0xC000` settori senza spostare `rootfs`. Scartata perche' `parameter.txt` e'
**condiviso** dai tre defconfig ed e' la tabella partizioni che si flasha:
cambiarlo per far entrare il kernel mainline avrebbe cambiato il layout anche
delle due immagini vendor, che oggi funzionano. Un percorso nuovo non deve
ritoccare la baseline del percorso che serve da termine di paragone.

E nel merito: un kernel da 15 MiB per arrivare a stampare su una UART e'
sproporzionato, e ogni driver in piu' e' un probe in piu' che puo' fallire
prima che la console sia viva — che e' esattamente cio' che
`rk3506_minimal.config` dice di voler evitare. Il vincolo di dimensione ha
solo reso obbligatorio un criterio che era gia' dichiarato.

#### Il prezzo: niente rete

`CONFIG_NET is not set` significa nessuna rete in questa immagine. E' una
scelta, non un effetto collaterale: l'immagine si usa dalla seriale. Per
coerenza il defconfig toglie anche `BR2_PACKAGE_IFUPDOWN_SCRIPTS`, che
altrimenti installerebbe un `S40network` destinato a fallire a ogni boot
(`/etc/network/interfaces` ha solo `lo`, e senza `CONFIG_NET` nemmeno `lo`
esiste) sporcando l'unico strumento diagnostico che c'e'.

Per riabilitarla: togliere la riga dal fragment e rimettere il package nel
defconfig. C'e' margine — 6.18 contro 12.00 MiB — ma la verifica dimensioni di
`post-image.sh` resta il guardrail, e fallisce la build invece di produrre
un'immagine non flashabile.

#### La lista delle piattaforme non e' scritta a mano

Viene dai Kconfig del kernel, intersecando i simboli di piattaforma
(`arch/arm/Kconfig.platforms` e `arch/arm/mach-*/Kconfig`) con quelli che
`multi_v7_defconfig` accende, meno Rockchip e meno l'infrastruttura
multi-piattaforma. Il comando per rigenerarla e' nel commento del fragment.

Limite noto: se mainline aggiunge una piattaforma nuova, quella non e' nella
lista e rientra, facendo ricrescere lo `zImage`. Non c'e' un modo dichiarativo
di dire "solo Rockchip" partendo da `multi_v7_defconfig`; il controllo che se
ne accorge e' la verifica dimensioni, che fa fallire la build.

### Cosa ha rivelato il primo boot

Due cose che nessuna analisi statica avrebbe trovato, e che si vedono solo con
la board che parla. Stanno nella sezione `(5/5)` di `linux-mainline.config`,
con le righe di `dmesg` da cui vengono.

**64 MiB su 128 riservati a niente.** `multi_v7_defconfig:1305` imposta
`CONFIG_CMA_SIZE_MBYTES=64`:

```
cma: Reserved 64 MiB at 0x04000000
Memory: 48024K/129024K available (... 65536K cma-reserved ...)
```

48 MB utilizzabili su 128. CMA lo vogliono DRM, V4L2 e MMC, che sono tutti
spenti: e' RAM riservata per nessun utente. Spento.

**Nove driver ancora vivi dopo il pruning delle piattaforme**, perche' non
sono gated su un simbolo `ARCH_*` e restano da `multi_v7_defconfig`: PL011,
ST ASC, SCSI, libata, squashfs, brd, loop, SCMI, EDAC. Nessuno ha un nodo nel
DT che lo reclami, e ognuno e' un probe in piu'. E' la dimostrazione che
spegnere le piattaforme non basta ad avere un kernel minimale: il pruning per
sottosistema della sezione `(3/5)` serve, e non e' completo per costruzione —
si allunga a ogni boot che rivela qualcosa.

### Il container non ha credenziali, e GitHub ha smesso di servire i fetch anonimi

Il `Makefile` monta nel container solo `/work`, con `HOME=/tmp`. Niente
`~/.ssh`, niente `~/.gitconfig`, niente credential helper, verificato:

```
HOME=/tmp
~/.ssh:            assente
~/.gitconfig:      assente
~/.netrc:          assente
credential.helper: nessuno
```

E' voluto, ed e' la ragione per cui i due `_CUSTOM_GIT` usano `https` e non
`ssh`. Quella scelta contiene pero' un presupposto che non era scritto da
nessuna parte: **che l'accesso git anonimo funzioni.** Il 26 agosto
funzionava; il 2 settembre no.

#### La diagnosi, perche' il messaggio d'errore mente

```
fatal: could not read Username for 'https://github.com': No such device or address
fatal: the remote end hung up unexpectedly
Detected a corrupted git cache.
```

Sembrano tre cose: un repository privato, una chiave mancante, una cache
rotta. Non e' nessuna delle tre. Con `GIT_CURL_VERBOSE=1`:

```
GET  /<repo>.git/info/refs?service=git-upload-pack   HTTP/2 200
POST /<repo>.git/git-upload-pack                     HTTP/2 401
```

L'annuncio dei ref passa anonimo, la negoziazione no. Git riporta il 401 come
richiesta di credenziali, e la "cache corrotta" e' solo Buildroot che ritenta
due volte e si arrende.

Tre test per inchiodarla, perche' le prime due ipotesi erano sbagliate:

| test | esito | cosa esclude |
|---|---|---|
| `buildroot/buildroot.git` dal container | **401 uguale** | non e' il nostro repository, ne' la sua visibilita' |
| nostro repo, `protocol.version=0` | `ls-remote` **passa**, il fetch **no** | non e' il protocollo v2: il POST c'e' in entrambe le versioni |
| stesso comando dall'host | **funziona** | e' l'accesso anonimo |

L'host ce la fa perche' ha un helper *scoped per URL* in `~/.gitconfig`:

```
credential.https://github.com.helper = !/usr/bin/gh auth git-credential
```

che un `git config --get credential.helper` non mostra — dettaglio che ha
allungato la diagnosi.

Attenzione all'effetto ottico: una build che trova i tarball gia' in `dl/`
non se ne accorge. Il guasto si manifesta **solo alzando uno SHA**, ed e'
esattamente cosi' che l'abbiamo trovato.

#### Perche' `MIRROR=` e non un URL nel defconfig

Un mirror che serve file su HTTPS evita del tutto il protocollo git, quindi
risolve. Ma l'URL **non** sta in questo albero, per due motivi indipendenti:

- un mirror e' infrastruttura di chi la paga, e questo repository e'
  pubblico: un URL cablato significa che il traffico di sconosciuti finisce
  sulla bolletta di qualcun altro;
- un valore site-specific per variante e' il problema che i defconfig
  dovrebbero evitare. `BR2_PRIMARY_SITE` e' una stringa sola.

Quindi: `MIRROR=` da riga di comando, oppure in `local.mk` che e' in
`.gitignore`. Default vuoto, comportamento invariato.

Due dettagli implementativi non ovvi, entrambi a commento nel `Makefile`:

`MIRROR` va passato sulla **riga di comando** di make, non nell'ambiente. Il
`.config` di Buildroot assegna `BR2_PRIMARY_SITE` come variabile del makefile,
e l'ambiente non sovrascrive un'assegnazione del makefile — la riga di comando
si'. Con `-e` non avrebbe funzionato.

E `-include local.mk` da solo non basta: make prova a *ricostruire* un file
incluso che manca, la regola catch-all `%:` intercetta il nome e lo inoltra a
Buildroot, che risponde `No rule to make target`. Serve la regola vuota
`$(LOCAL_MK): ;`, lo stesso idioma che il `Makefile` usava gia' per se stesso.

#### Il limite che questa scelta accetta

| senza `MIRROR` | |
|---|---|
| ~80 package di terzi | scaricano da upstream, funzionano |
| kernel e U-Boot | **falliscono** |

Un clone fresco, per chi non ha un mirror ne' credenziali git, non completa
la build. E' un limite noto e accettato: l'alternativa era pubblicare un
mirror a spese di qualcuno, o rimettere segreti nel container. Il rimedio
documentato e' scaricare i due tarball dall'host, che serve una volta per
SHA.

`BR2_PRIMARY_SITE_ONLY` resta la strada per build ermetiche — niente
dipendenza da GitHub, kernel.org, gnu.org, che cadono tutti prima o poi. Con
gli SHA pinnati come li abbiamo e' cio' che rende una release ricostruibile
fra due anni.

Ma non e' un interruttore da lasciare acceso, ed e' il motivo per cui non e'
attivo. Con `ONLY` un tarball mancante e' errore secco, senza fallback — e
un tarball manca **ogni volta che si alza qualcosa**: un nuovo SHA del
kernel, una release di Buildroot che sposta le versioni dei package. Il
flusso diventerebbe: scarica normalmente, sincronizza sul mirror, poi
ricostruisci con `ONLY`. Tre passi dove oggi ce n'e' uno.

Ha senso quindi come **modalita' per riprodurre una release**, non come
impostazione di tutti i giorni: si accende su uno snapshot congelato e
completo, per dimostrare che quella release si ricostruisce da sola. Lo
sviluppo quotidiano resta con il fallback, che e' proprio la rete di
sicurezza che `ONLY` toglie.

Nota sulle dimensioni, utile per decidere: l'insieme completo dei tarball di
questo build e' **42 file per ~1.1 GB**, di cui 720 MB sono i tre tarball del
kernel. Non e' un mirror grande.

### Quanto divergiamo da mainline, e cosa costa il salto a 7.0

Il senso del percorso mainline e' capire quanto di questa board si regge su
codice upstream, e potersi spostare dalla 6.19 alla 7.0 toccando poco. Questo
richiede una regola su *dove* possono stare le modifiche, non solo quante
sono.

**La regola: zero patch al codice del kernel.** Oggi e' rispettata.

| cosa | e' divergenza? | stato |
|---|---|---|
| patch al **codice** del kernel (`.c`, `.S`, Kconfig) | si, la peggiore | **nessuna** |
| patch portate dal framework a un sorgente di terzi | si | **nessuna** |
| proprieta' nel DTS **della nostra board** | **no** | due, nel repo kernel |
| fragment di config (`linux-mainline.config`) | no | uno |

La distinzione che conta e' la terza. `rk3506g-luckfox-lyra-plus.dts` **non e'
ancora in mainline**: e' il nostro contributo in corso, nel branch
`rk3506-lyra-plus`. Aggiungerci una proprieta' corretta non e' forkare Linux,
e' scrivere il supporto della board. Quando la board andra' upstream, la
proprieta' va con lei e la divergenza e' zero per costruzione.

Il che vale solo se la proprieta' e' *giusta*, non un aggiramento. Per
`linux,usable-memory-range` il precedente in-tree c'e', su una board ARMv7 e
per lo stesso identico motivo — `arch/arm/boot/dts/airoha/en7523-evb.dts:19-21`:

```dts
/* Bootloader installs ATF here */
/memreserve/ 0x80000000 0x200000;
...
	chosen {
		linux,usable-memory-range = <0x80200000 0x1fe00000>;
	};
```

Firmware sicuro in fondo alla RAM, `/memory` che descrive tutto, e la
proprieta' che sposta Linux 2 MiB piu' in su. Stesso offset. Un secondo
precedente, con il motivo scritto nel commento, e'
`arch/arm/boot/dts/samsung/exynos4212-tab3.dtsi:53`.

#### Il costo ricorrente non e' nel kernel, e' nel fragment

Le tre cose che si romperanno alzando la versione del kernel, in ordine di
probabilita':

1. **La lista delle piattaforme da spegnere.** 72 simboli `ARCH_*` e 41
   `SOC_*`. Se mainline aggiunge una famiglia di SoC, quella non e' nella
   lista, rientra, e lo `zImage` ricresce. Non e' silenzioso: la verifica
   dimensioni di `post-image.sh` fa **fallire la build** invece di produrre
   un'immagine che non entra in partizione. Il comando per rigenerare le due
   liste dai Kconfig del kernel e' nel commento del fragment.
2. **I nomi dei simboli di config.** Upstream li rinomina e li rimuove senza
   preavviso. `merge_config` avvisa su un simbolo ridefinito, ma **non** su un
   simbolo che non esiste piu': quello sparisce in silenzio. Il controllo che
   se ne accorge e' rileggere il `.config` finale, non il fragment — che e' la
   ragione per cui la verifica del Passo 5 guarda il `.config` prodotto.
3. **`rk3506_minimal.config` in-tree**, di cui il fragment e' una copia
   dichiarata. Se cambia nel repo kernel, va riallineata a mano; il comando di
   diff e' nel commento.

#### Cosa NON e' stato fatto, e perche'

**`rockchip,rk3506` non e' in `rockchip_board_dt_compat[]`**
(`arch/arm/mach-rockchip/rockchip.c:54-63`), quindi la board ripiega su
`GENERIC_DT` invece di usare il machine descriptor Rockchip. Non e' fatale —
lo dimostra il fatto che boota, e che il kernel vendor fa lo stesso — ma
significa che `rockchip_dt_init()` non gira e quindi nemmeno
`rockchip_suspend_init()`. Aggiungerlo sarebbe una riga, ed e' una patch al
**codice**, non al DTS: prima di scriverla va capito cosa
`rockchip_suspend_init()` faccia su un SoC che non conosce. Fuori scope per un
bring-up da console, ma e' il primo candidato quando servira' il suspend.

### Il kernel non puo' stare a 0x8000: la' c'e' OP-TEE

Questo e' costato l'intero bring-up, e vale la pena scriverlo per esteso
perche' il sintomo non somiglia alla causa.

Il boot si fermava dopo `Starting kernel ...` **senza stampare un solo
carattere**: non con `earlycon`, non con `CONFIG_DEBUG_LL`, niente.

#### Perche' il silenzio non diceva nulla

La finestra in cui il boot ARM puo' morire muto e' prima che esista una
console:

| | |
|---|---|
| `setup.c:1106` | `mdesc = setup_machine_fdt(atags_vaddr);` |
| `setup.c:1138` | `parse_early_param();` — earlycon nasce qui |

e in quella finestra `early_print()` raggiunge una UART **solo** con
`CONFIG_DEBUG_LL` (`setup.c:368-370`); altrimenti e' un `printk` in un ring
buffer senza console, e `dump_machine_table()` finisce in `while (true);`
(`setup.c:756-757`). Il silenzio era percio' la firma *attesa* di qualunque
errore in quella finestra: non discriminava fra le cause.

#### Due ipotesi sbagliate, per non rifarle

**`rockchip,rk3506` non e' in `rockchip_board_dt_compat[]`.** Vero, e sembra
decisivo. Non lo e': `devtree.c:196-201` definisce un `GENERIC_DT` di
fallback e `fdt.c:763` fa `best_data = default_match`, quindi un compatible
non riconosciuto ripiega su "Generic DT based system" invece di morire. Il
kernel **vendor** non elenca `rk3506` e boota: ripiegano entrambi.

**Il DTB viene sovrascritto dal kernel decompresso.** Plausibile — il
bootloader lo mette a `0x63000`, appena 372 KiB sopra `0x8000` — e il
decompressore protegge solo se stesso (`head.S:449-465`), mai il DTB passato
in `r2`. Smentita sulla board: spostandolo con `setenv fdt_addr_r 0x02000000`
il silenzio e' rimasto identico.

#### La causa vera

Non il kernel, non il DTB: l'indirizzo a cui lavora il **decompressore**.

`AUTO_ZRELADDR` (obbligatorio su `ARCH_MULTIPLATFORM`) ricava l'inizio della
RAM mascherando il PC:

```
head.S:279-280   mov r0, pc; and r0, r0, #0xf8000000   ->  0x00000000
head.S:312       add r4, r0, #TEXT_OFFSET              ->  0x00008000
```

e `fdt_check_mem_start()` non lo corregge, perche' `memory@0` dichiara la RAM
da 0 e quindi 0 e' un indirizzo valido (`fdt_check_mem_start.c:146-148`,
*"Calculated address is valid, use it"*). Da li':

```
head.S:793   __setup_mmu: sub r3, r4, #16384    ->  page directory a 0x00004000
```

16 KiB di scritture da `0x4000` a `0x8000`. Quell'intervallo e' dentro
`trust@0` (`0x0-0x62000`), la regione di **OP-TEE**, che il firewall del SoC
rende inaccessibile dal normal world. La prova, dal prompt U-Boot — che gira
anch'esso in normal world:

```
=> md 0x4000 4
00004000:data abort
pc : 00254086  lr : 00254029
### ERROR ### Please RESET the board ###
```

Non passa nemmeno una **lettura**. Il decompressore aborta quindi alla prima
scrittura della page directory, dentro `cache_on`, **prima** di
`decompress_kernel()`: il suo primo `putstr()` non viene mai raggiunto, ed e'
per questo che accendere `DEBUG_LL` non cambiava niente.

Che il kernel decompresso vada *sopra* la regione riservata era scritto nella
mappa del bootloader, `u-boot/include/configs/rk3506_common.h:58-70`:

```
 *     fdt:  396K - 524K
 *   Image:  1M+32k - 16M
 *  zImage:  16M - 24M
```

`kernel_addr_r=0x00108000`. Il vincolo c'era; il kernel non lo sapeva.

#### La correzione

`linux,usable-memory-range = <0x00200000 0x07e00000>` nel nodo `/chosen`, nel
**repo del kernel** (`rk3506-kernel-upstream`, commit `c6c820d6`): il DTS e' di
questa board, e la correzione va dove vive il DTS. Il framework non porta
nessuna patch al kernel. Fa due cose:

- `fdt_check_mem_start()` ritorna `round_up(base, SZ_2M)` invece del PC
  mascherato → page directory a `0x00204000`, kernel a `0x00208000`, liberi
  da OP-TEE (`0x62000`), DTB (`0x63000`) e ramoops (`0x83000`);
- `early_init_dt_check_for_usable_mem_range()` (`of/fdt.c:884-916`, senza
  guardia di config) taglia `memblock`, cosi' la regione firewallata esce
  dalla vista del kernel e nessun accesso dalla linear map puo' abortire —
  che chiude anche il `TODO(verify)` su `trust@0`, privo di `no-map`.

Risultato:

```
# uname -a
Linux lyra-plus 6.19.0 #2 SMP armv7l GNU/Linux
```

`SMP` non e' un dettaglio: PSCI ha `method = "smc"`, servito da OP-TEE. Se il
kernel avesse comunque scritto su quella regione, il secondo core non
partirebbe. E' la conferma che ora la lascia in pace.

**Non costa niente.** Avevo previsto la perdita di `pstore`, assumendo che
`memblock_cap_memory_range()` impedisse la riserva di `ramoops@83000`, che sta
sotto il floor dei 2 MiB. Sbagliato: il cap toglie la RAM all'**allocatore**,
non a `reserved-memory`. Il `dmesg` del primo boot riuscito lo mostra senza
ambiguita':

```
OF: fdt: Ignoring memory range 0x0 - 0x200000
OF: reserved mem: 0x00083000..0x000affff (180 KiB) map non-reusable ramoops@83000
pstore: Registered ramoops as persistent store backend
ramoops: using 0x2d000@0x83000, ecc: 0
```

**Scartata:** spedire `Image` invece di `zImage`. U-Boot carica un kernel non
compresso direttamente a `kernel_addr_r = 0x00108000`, sopra OP-TEE, senza
decompressore e quindi senza page directory a `0x4000`: avrebbe risolto da
se'. Ma `Image` e' 16.61 MiB e la partizione `boot` e' 12 MiB.

**Resta aperto:** perche' il kernel vendor 6.1 bootasse. Ha
`CONFIG_AUTO_ZRELADDR=y`, il suo decompressore e' identico (stesso
`sub r3, r4, #16384`) e la sua catena DTS non ha ne' `/memory` ne'
`linux,usable-memory-range` — quindi dovrebbe finire nello stesso abort. Il
log di boot vendor lo chiarirebbe; fino ad allora la domanda e' aperta, e
vale la pena chiedersi se l'immagine vendor di questo albero sia mai stata
avviata o se il "funziona" venisse dalle immagini dell'SDK.

### I DTB dei due kernel non sono interscambiabili

Questa è la trappola grossa, e non dà nessun messaggio di errore.

Gli ID dei clock nei dt-bindings sono stati **rinumerati** fra il 6.1 vendor e
mainline. Stesso file, stesse righe, valori diversi:

| simbolo | vendor `rockchip,rk3506-cru.h` | mainline `rockchip,rk3506-cru.h` |
|---|---|---|
| `PCLK_UART0` (`:112`) | 113 | 99 |
| `SCLK_UART0` (`:117`) | 118 | 104 |

Un DTB vendor su kernel mainline (o viceversa) **compila, boota e programma i
clock sbagliati**: gli ID sono numeri, il kernel non ha modo di accorgersi che
vengono da un'altra numerazione. Nessun errore, solo una board che non parla —
o che parla a un baudrate che non è quello che ci si aspetta.

Conseguenza operativa: **i `boot.img` dei due percorsi non vanno mai mescolati
sulla stessa board.** Contromisure, tutte a costo zero:

- `post-image.sh` scrive `output/images/lyra-manifest.txt`: kernel, commit,
  DTB, console, provenienza di `resource_tool`.
- accanto a `boot.img` compare un **hard link** con il nome della release del
  kernel — `boot-6.1.99.img` oppure `boot-6.19.0.img`. Zero byte in più, e
  sulla scrivania i due file non si somigliano. Il nome viene da
  `include/config/kernel.release`, scritto dal kernel stesso.
- `/etc/issue` sul target lo dice prima del prompt di login
  (`BR2_TARGET_GENERIC_ISSUE`), e `/etc/lyra-release` riporta il commit.
