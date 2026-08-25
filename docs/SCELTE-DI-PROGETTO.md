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
