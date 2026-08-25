# rk3506-framework — Luckfox Lyra Plus su Buildroot upstream

Albero `BR2_EXTERNAL` per la **Luckfox Lyra Plus** (Rockchip **RK3506G2**,
triple Cortex-A7, ARMv7 32-bit, storage SPI NAND), costruito su **Buildroot
upstream** invece che sull'SDK Luckfox.

L'SDK Luckfox e' un Buildroot 2024.02 con centinaia di package infilati
nell'albero e orchestrato da `build.sh`. Qui il rapporto e' rovesciato:
Buildroot e' un submodule intatto su un tag LTS, e tutto cio' che riguarda la
board vive in `external/`. Kernel e U-Boot restano vendor — mainline non
supporta ancora RK3506 — ma sono agganciati con `_CUSTOM_GIT` a **commit SHA
fissi**, e ogni modifica va come `.patch` numerata, non come fork.

La verifica che il giro funzioni e' `hello-lyra`, una applicazione Go che
all'avvio stampa cosa il sistema vede davvero.

---

## Indice

- [Com'e' fatto](#come-fatto)
- [Prerequisiti](#prerequisiti)
- [Build](#build)
- [Flash](#flash)
- [Console seriale](#console-seriale)
- [Output atteso a boot riuscito](#output-atteso-a-boot-riuscito)
- [Verificare che post-image.sh produca gli stessi artefatti dell'SDK](#verificare-che-post-imagesh-produca-gli-stessi-artefatti-dellsdk)
- [Scelte di progetto](#scelte-di-progetto)
- [Licenza](#licenza)
- [Cosa manca ancora](#cosa-manca-ancora)

---

## Com'e' fatto

```
.
├── README.md
├── setup.sh                      prepara il clone (submodule, SDK, immagine docker)
├── Makefile                      wrapper: make shell / defconfig / build
├── docker/Dockerfile             Ubuntu 22.04, unico posto dove si compila
├── docs/BOARD-FACTS.md           ricognizione dell'SDK, ogni valore con la sua fonte
├── buildroot/                    submodule upstream, tag 2026.02.3 (LTS)
└── external/
    ├── Config.in                 opzioni della board (path rkbin, tool di packaging)
    ├── external.mk
    ├── external.desc             name: LYRA_PLUS
    ├── patches/                  BR2_GLOBAL_PATCH_DIR (package Buildroot) — vuota
    ├── configs/
    │   ├── lyra_plus_defconfig            SPI NAND + UBIFS (produzione)
    │   └── lyra_plus_initramfs_defconfig  rootfs in RAM (bring-up)
    ├── board/lyra-plus/
    │   ├── linux.config          fragment kernel (non un defconfig completo)
    │   ├── uboot.config          fragment U-Boot
    │   ├── boot.its              sorgente FIT di boot.img
    │   ├── parameter.txt         tabella partizioni MTD (baseline vendor)
    │   ├── rkbin.sha256          hash attesi dei blob vendor
    │   ├── dts/                  DTS custom (variante initramfs)
    │   ├── patches/{linux,uboot}/  patch numerate a kernel e U-Boot
    │   ├── genimage.cfg          flash.img, immagine raw full-chip
    │   ├── post-build.sh         ritocchi al rootfs
    │   ├── post-image.sh         **la catena di packaging Rockchip**
    │   └── rootfs_overlay/       /etc/init.d/S99hello
    └── package/hello-lyra/       applicazione Go di verifica
```

Il file da leggere per primo, se qualcosa non torna, e' `docs/BOARD-FACTS.md`:
contiene la ricognizione dell'SDK con **la fonte esatta di ogni valore**, e la
ricostruzione della catena di packaging riga per riga dal trace di `build.sh`.

Il file da leggere per secondo e' `external/board/lyra-plus/post-image.sh`. E'
li' che si arenano i porting da SDK Rockchip: `build.sh` non compila soltanto,
dopo kernel e U-Boot invoca i tool che producono le immagini flashabili
(`boot_merger`, `mkimage`, `resource_tool`, `afptool`, `rkImageMaker`).
Buildroot non ne sa nulla, e `post-image.sh` deve rifare quella sequenza.

---

## Prerequisiti

Sull'host servono solo tre cose:

| Cosa | Perche' |
|------|---------|
| `git` | submodule Buildroot |
| `docker` | tutta la compilazione avviene dentro il container |
| Checkout dell'**SDK Luckfox** | blob DDR e tool di packaging vendor, non ricompilabili |

Non serve installare toolchain, `python2`, `gcc` vecchi o altro: stanno nel
container.

### L'SDK serve, ma non come build system

`build.sh` non viene **mai** lanciato. L'SDK e' montato **read-only** e da li'
si prendono solo i binari vendor che non si possono ricostruire dai sorgenti:

| Da | Cosa | A che serve |
|----|------|-------------|
| `rkbin/bin/rk35/rk3506_ddr_750MHz_v1.04.bin` | blob | init DDR eseguita dal BootROM |
| `rkbin/bin/rk35/rk3506_tee_v1.25.bin` | blob | OP-TEE, incluso nel FIT di `uboot.img` |
| `rkbin/bin/rk35/rk3506_usbplug_v1.02.bin` | blob | CODE472 (modalita' MaskROM/USB) |
| `rkbin/tools/{boot_merger,mkimage}` | tool | assemblano loader e FIT |
| `rkbin/RKBOOT/RK3506MINIALL.ini`, `rkbin/RKTRUST/RK3506TOS.ini` | descrittori | dicono ai tool cosa mettere dove |
| `tools/linux/Linux_Pack_Firmware/rockdev/{afptool,rkImageMaker}` | tool | producono `update.img` |

Il percorso e' **configurabile**, non cablato: `BR2_LYRA_RKBIN_DIR` e
`BR2_LYRA_PACKTOOL_DIR` in `make menuconfig` → *Luckfox Lyra Plus*. Il default
e' `/sdk/...`, cioe' il mount del container.

I blob non vengono copiati alla cieca: `post-image.sh` ne verifica lo `sha256`
contro `external/board/lyra-plus/rkbin.sha256` e **si ferma** se non
corrispondono. Revisione attesa di `rkbin`: tag `linux-6.1-stan-rkr4.2`, commit
`32ccaf811ae70ce050aa810869c63c2b34324d59`. Se l'aggiornamento e' voluto, si
rigenera `rkbin.sha256`; per forzare una volta sola,
`LYRA_ALLOW_RKBIN_MISMATCH=1`.

### Mirror di kernel e U-Boot

I due `_CUSTOM_GIT` puntano a:

| | URL | Commit |
|---|-----|--------|
| kernel 6.1.99 | `https://github.com/wdalmut/rk3506-kernel.git` | `696a8549d1a582337c8032c02a2aea35790047a4` |
| U-Boot 2017.09 | `https://github.com/wdalmut/rk3506-uboot.git` | `4d88b0a83c87488f343fb4cc4f56ffc598b2e0a3` |

Sono **mirror**: l'origine dell'SDK e' `ssh://git@192.168.10.75/...`, una LAN
privata Luckfox non raggiungibile da fuori (vedi `docs/BOARD-FACTS.md` §1a).

> **I due repository vanno pubblicati prima della prima build.** Finche' non
> esistono, `make` si ferma allo scaricamento del kernel. I checkout dentro
> l'SDK sono `clone-depth=1`, quindi il push va fatto da un clone completo
> oppure pubblicando quell'unico commit su un branch. Assicurarsi che il
> commit sia **raggiungibile da un ref** (branch o tag): un fetch di SHA nudo
> funziona solo se il server ha `uploadpack.allowReachableSHA1InWant`.

---

## Build

```bash
git clone <questo-repo> rk3506-framework
cd rk3506-framework

./setup.sh                        # submodule + controlli SDK + immagine docker
make lyra_plus_defconfig
make
```

Se l'SDK non e' in `~/git/luckfox-lyra`:

```bash
SDK_DIR=/percorso/al/sdk ./setup.sh
make SDK_DIR=/percorso/al/sdk lyra_plus_defconfig
make SDK_DIR=/percorso/al/sdk
```

`make` da solo lancia il container e ci esegue Buildroot: non serve entrare a
mano. Ogni target non riconosciuto viene inoltrato a Buildroot, quindi
funzionano `make menuconfig`, `make linux-menuconfig`, `make uboot-rebuild`,
`make hello-lyra-rebuild`, `make savedefconfig`.

Per lavorare dentro:

```bash
make shell
```

che equivale a

```bash
docker run --rm -it \
    -v "$PWD":/work \
    -v "$HOME/git/luckfox-lyra":/sdk:ro \
    -u "$(id -u):$(id -g)" \
    -w /work rk3506-framework:build bash
```

I due mount sono entrambi necessari: `/work` e' il repo, `/sdk` e' l'SDK
read-only da cui arrivano i blob.

### Variante initramfs (primo bring-up)

```bash
make lyra_plus_initramfs_defconfig
make
```

Rootfs incorporato in `zImage` e quindi in `boot.img`: non c'e' `rootfs.img` e
la NAND non viene toccata. Se la board arriva alla shell con questa immagine,
NAND, UBI e partizionamento sono fuori dall'equazione — e resta da guardare
solo il resto. E' l'immagine giusta con cui cominciare su hardware nuovo.

### Artefatti

In `output/images/`:

| File | Cos'e' |
|------|--------|
| `MiniLoaderAll.bin` | loader per la MaskROM (DDR init + SPL) |
| `uboot.img` | FIT: U-Boot + OP-TEE, 2 copie paddate a 2 MiB |
| `boot.img` | FIT: `zImage` + dtb + `resource.img` |
| `rootfs.img` (`rootfs.ubi`) | UBI con dentro UBIFS |
| `update.img` | immagine unica Rockchip per `rkdeveloptool uf` |
| `flash.img` | immagine raw dell'intero chip (extra, vedi sotto) |
| `parameter.txt` | tabella partizioni, usata dai tool di flash |

---

## Flash

### Modalita' MaskROM / loader

Alimentare la board tenendo premuto il tasto **BOOT** (oppure cortocircuitando
i pin di boot) e collegare il cavo USB-C. Controllo:

```bash
rkdeveloptool ld
# atteso: DevNo=1 Vid=0x2207,Pid=0x350f,LocationID=... Maskrom
```

`Vid=0x2207` `Pid=0x350f` sono quelli dichiarati dal defconfig U-Boot
(`CONFIG_USB_GADGET_VENDOR_NUM` / `PRODUCT_NUM`).

### Immagine unica (consigliato)

```bash
cd output/images
sudo rkdeveloptool db MiniLoaderAll.bin      # carica il loader in SRAM
sudo rkdeveloptool uf update.img             # scrive tutto
sudo rkdeveloptool rd                        # reset
```

### Per partizione

Utile quando si itera solo sul rootfs o solo sul kernel: gli offset sono in
settori da 512 B e vengono da `parameter.txt`.

```bash
cd output/images
sudo rkdeveloptool db MiniLoaderAll.bin
sudo rkdeveloptool gpt parameter.txt          # scrive la tabella
sudo rkdeveloptool wl 0x2000  uboot.img       # @ 4 MiB
sudo rkdeveloptool wl 0x4000  boot.img        # @ 8 MiB
sudo rkdeveloptool wl 0x10000 rootfs.img      # @ 32 MiB
sudo rkdeveloptool rd
```

### `flash.img`

Immagine raw dei 256 MiB, con ogni partizione al suo offset. Serve per un
programmatore NAND esterno o per ispezionare il layout senza board. **Non e'
avviabile cosi' com'e'**: i primi 4 MiB (area loader/IDB) sono vuoti, perche'
l'offset a cui il BootROM RK3506 cerca l'IDB su SPI NAND non e' ancora
accertato — vedi *Cosa manca ancora*, TODO-4.

---

## Console seriale

| | |
|---|---|
| Device sul target | `ttyFIQ0` |
| UART SoC | UART0, base `0xff0a0000` |
| **Baudrate** | **1500000** |
| Formato | 8N1, nessun controllo di flusso |

**Non e' 115200.** Il valore viene dal nodo `fiq_debugger` del DTS vendor
(`rk3506-luckfox-lyra.dtsi:72`), che ammette solo `115200` o `1500000` e su
questa board e' impostato al secondo. Un adattatore USB-seriale a 115200 non
mostra niente, e sembra un boot fallito.

```bash
picocom -b 1500000 /dev/ttyUSB0
# oppure
screen /dev/ttyUSB0 1500000
```

`ttyFIQ0` non e' una `ttyS*`: e' la tty esposta dal *FIQ debugger* Rockchip
(`CONFIG_FIQ_DEBUGGER_CONSOLE=y`), che prende in carico UART0
(`rockchip,serial-id = <0>`). Per questo il defconfig ha
`BR2_TARGET_GENERIC_GETTY_PORT="ttyFIQ0"` e lascia il baudrate a *keep*: la
velocita' la fissa il driver, getty non deve toccarla.

> Su quale pettine della Lyra Plus escano fisicamente quei pin resta da
> confermare (TODO-6): lo script `flash.sh` dell'SDK parla di "UART2", ma il
> DTS dice `serial-id = <0>`. Il baudrate e' invece certo.

---

## Output atteso a boot riuscito

Dopo il banner di U-Boot e i messaggi del kernel, `S99hello` esegue
`hello-lyra` e sulla seriale compare:

```
═══════════════════════════════════════════════════════
  hello-lyra 1.0.0 — Luckfox Lyra Plus (RK3506G2)
  Buildroot upstream + external tree · 2026-08-24 09:14:22
═══════════════════════════════════════════════════════

  Board
  ───────
    Modello:       Luckfox Lyra Plus
    Kernel:        6.1.99
    Uptime:        4s (4.31 s)

  Memoria
  ─────────
    MemTotal:      118.4 MiB (121256 kB)
    MemFree:       92.1 MiB (94312 kB)
    MemAvailable:  95.7 MiB (98016 kB)
    Buffers:       0.0 MiB (36 kB)
    Cached:        4.2 MiB (4304 kB)

  Partizioni MTD
  ────────────────
    dev      size         erasesize    name
    mtd0     4 MiB        128 KiB      uboot
    mtd1     12 MiB       128 KiB      boot
    mtd2     224 MiB      128 KiB      rootfs

Welcome to Luckfox Lyra Plus (RK3506G2)
lyra-plus login:
```

Le righe che valgono davvero come verifica sono tre:

- **`Modello: Luckfox Lyra Plus`** — arriva da `/proc/device-tree/model`, cioe'
  il DTB dentro `boot.img` e' quello giusto. Se qui compare un altro modello,
  `BR2_LINUX_KERNEL_INTREE_DTS_NAME` non e' quello che si crede.
- **`MemTotal`** — se la RAM e' molto meno del previsto, il blob DDR non ha
  fatto il suo lavoro. E' il primo posto dove guardare quando il boot e'
  instabile.
- **`mtd0/1/2`** — nomi e dimensioni devono combaciare con `parameter.txt`. Se
  non c'e' nessuna partizione, `mtdparts=` non e' arrivato al kernel: il DTB e'
  sbagliato o U-Boot ha sovrascritto il bootargs.

I valori numerici sopra (MemTotal, uptime, date) sono ovviamente indicativi;
**`MemTotal` non e' stato misurato su hardware** — vedi TODO-5 sulla dimensione
effettiva di RAM e NAND.

Con la variante initramfs, `/proc/mtd` puo' essere vuoto o assente: e'
previsto, il rootfs non sta su NAND.

---

## Verificare che `post-image.sh` produca gli stessi artefatti dell'SDK

Il criterio non e' "i file sono identici byte a byte": **non possono esserlo**.
`ubinize` scrive un `image_seq` casuale a ogni esecuzione (verificato:
`image_seq=0x4fad5d65` nella build di riferimento), e i FIT contengono un
timestamp. Il confronto giusto e' su **struttura, dimensioni e header**.

Con l'SDK gia' costruito in `~/git/luckfox-lyra/output/firmware/`:

### 1. Magic e dimensioni

```bash
for f in MiniLoaderAll.bin uboot.img boot.img rootfs.img update.img; do
    printf '%-20s %12s  %12s   %s\n' "$f" \
        "$(stat -c%s ~/git/luckfox-lyra/output/firmware/$f 2>/dev/null || echo -)" \
        "$(stat -c%s output/images/$f 2>/dev/null || echo -)" \
        "$(hexdump -n 4 -e '4/1 "%02x "' output/images/$f 2>/dev/null)"
done
```

Riferimento misurato sulla build SDK:

| File | Dimensione SDK | Magic | Formato |
|------|---------------:|-------|---------|
| `MiniLoaderAll.bin` | 268 736 | `4c 44 52 20` (`LDR `) | loader Rockchip |
| `uboot.img` | 4 194 304 | `d0 0d fe ed` | FIT |
| `boot.img` | 6 391 808 | `d0 0d fe ed` | FIT |
| `rootfs.img` | 124 518 400 | `55 42 49 23` (`UBI#`) | UBI |
| `update.img` | 135 649 866 | `52 4b 46 57` (`RKFW`) | firmware Rockchip |

`uboot.img` deve essere **esattamente 4 194 304 byte**: e' `CONFIG_SPL_FIT_IMAGE_MULTIPLE=2`
copie paddate a `CONFIG_SPL_FIT_IMAGE_KB=2048`. Un valore diverso significa che
il FIT e' cresciuto oltre i 2 MiB, e la partizione `uboot` non lo contiene piu'.
`boot.img` e `rootfs.img` variano con il contenuto: si controlla che rientrino
nella partizione, non che siano uguali.

### 2. Struttura interna dei FIT

```bash
# le immagini dentro boot.img e i loro offset
fdtget -l output/images/boot.img /images
for n in fdt kernel resource; do
    echo "$n: pos=$(fdtget -ti output/images/boot.img /images/$n data-position)" \
         "size=$(fdtget -ti output/images/boot.img /images/$n data-size)"
done
```

Attesi tre nodi — `fdt`, `kernel`, `resource` — con `data-position` allineato a
`0x800` (il `-p 0x800` passato a `mkimage`). Stessa cosa su `uboot.img`, dove
la configurazione deve avere `firmware = "optee"` e `loadables = "uboot"`:

```bash
fdtget -l output/images/uboot.img /images
fdtget    output/images/uboot.img /configurations/conf firmware loadables
```

### 3. Geometria UBI

```bash
python3 - <<'EOF'
import struct
d = open('output/images/rootfs.img','rb').read(32)
magic = d[0:4]
vid, data, seq = struct.unpack('>III', d[16:28])
print(f"magic={magic} vid_hdr_offset={vid} data_offset={data} image_seq=0x{seq:08x}")
EOF
```

Attesi `magic=b'UBI#'`, `vid_hdr_offset=2048`, `data_offset=4096` — cioe' page
2048 B e PEB 128 KiB. `image_seq` differisce a ogni build ed e' corretto cosi'.

### 4. Offset delle partizioni

`post-image.sh` fa gia' questo controllo a ogni build e lo stampa: per ogni
`*.img` confronta la dimensione con il limite dichiarato in `parameter.txt` e
fallisce se sfora, come `mk-firmware.sh:52-64` dell'SDK.

### 5. Contenuto di `update.img`

```bash
~/git/luckfox-lyra/tools/linux/Linux_Pack_Firmware/rockdev/afptool \
    -unpack output/images/update.img /tmp/unpacked
cat /tmp/unpacked/package-file
```

Deve elencare `parameter`, `bootloader`, `uboot`, `boot`, `rootfs` — lo stesso
insieme che `gen_package_file()` dell'SDK produce.

---

## Scelte di progetto

### Buildroot 2026.02.3, non 2026.05.x

Le LTS Buildroot sono le release `YYYY.02.x`. `setup.sh` avvisa se il
submodule finisce su un tag non-LTS.

### glibc, non musl — e una trappola da non reintrodurre

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

### Toolchain

`BR2_cortex_a7` seleziona da solo ARMv7-A, NEON e VFPv4; l'ABI hard-float e'
la conseguenza. Il defconfig fissa esplicitamente solo
`BR2_ARM_FPU_NEON_VFPV4`. GCC e' pinnato a **13.x**, la piu' vecchia
disponibile in 2026.02.3: U-Boot 2017.09 e' del 2017 e piu' il compilatore e'
recente piu' aumenta il rischio (vedi TODO-9).

### Nessuna patch a Buildroot

`external/patches/` e' vuota di proposito. La Fase 1 ha confrontato il
Buildroot dell'SDK con l'upstream `2024.02` da cui deriva: 452 file aggiunti,
242 modificati, ma tutto cio' che tocca il percorso di questa board (`fs/ubi`,
`fs/ubifs`, `linux/linux.mk`, `arch/Config.in.arm`) e' **comodita', non
funzionalita' mancante**. Esempio: il vendor aggiunge
`BR2_TARGET_ROOTFS_UBIFS_MAX_SIZE` in MB che calcola `MAXLEBCNT`; noi
impostiamo `MAXLEBCNT=8456` a mano e otteniamo lo stesso `mkfs.ubifs -c 8456`.
Dettaglio voce per voce in `docs/BOARD-FACTS.md` §1a.

### U-Boot: perche' `post-image.sh` richiama `scripts/fit.sh`

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
(`build-trace.log:4056`), e `make.sh` non esporta variabili d'ambiente: `fit.sh`
e' un processo autonomo, quindi chiamarlo direttamente e' equivalente.

Un dettaglio che fa fallire questo passo se non lo si conosce: la catena
pretende `rkbin` come **directory fratello** — `prepare()` controlla
`-d ../rkbin` e aborta con `ERROR: No ../rkbin repository` (`make.sh:105`).
`post-image.sh` crea un symlink in `$(BUILD_DIR)/rkbin`, senza toccare il
checkout puntato da `BR2_LYRA_RKBIN_DIR`, che resta read-only.

### Perche' `linux.config` non include `rk3506-display.config`

Il defconfig di board dell'SDK aggiunge quel fragment (DRM/VOP/DSI, ~23 KB di
simboli). Qui no: questa e' una immagine da console seriale. Conseguenza
attesa: `console=tty1` nel bootargs del DTS non trova un framebuffer e viene
ignorato, `/dev/console` resta su `ttyFIQ0`. Per riabilitarlo, copiare il
fragment accanto a `linux.config` e aggiungerlo a
`BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES`.

### Il Dockerfile e' piu' magro di quello dell'SDK

`file` su ogni tool di `rkbin/tools/` e di `Linux_Pack_Firmware/rockdev/`: sono
tutti x86-64. L'unico binario i386 e' `firmwareMerger`, che **non e' nella
catena** (`update.img` usa `afptool` + `rkImageMaker`). Quindi via
`gcc-multilib` e `g++-multilib`, e non serve neanche `libc6:i386`.

`python2` invece **resta**: e' un gate incondizionato per U-Boot 2017.09, e
sull'host senza python2 la build si ferma esattamente li' (verificato).

### AMP fuori scope

Il checkout SDK di riferimento aveva modifiche locali che accendono l'AMP
(RT-Thread sul terzo core A7, partizioni `config` e `amp`, `amp_miranda.its`).
Questo albero parte dal **baseline vendor**: solo Linux, partizioni
`uboot`/`boot`/`rootfs`. Vedi TODO-8.

---

## Licenza

**GPL-2.0-or-later**, come Buildroot e U-Boot — i due progetti a cui questo
repository fa da collante. Non GPL-2.0-*only* come Linux: `or-later` lascia
aperta la strada a GPLv3 per il codice nostro, e si allinea a cio' che
costruiamo. Testo completo in [LICENSE](LICENSE).

Ogni file che abbiamo scritto porta l'header SPDX. **Le eccezioni sono
tracciate per file**, non nascoste sotto una licenza unica:

| File | Licenza | Perche' |
|------|---------|---------|
| `external/board/lyra-plus/boot.its` | **GPL-2.0-only** | copiato verbatim dall'SDK (`device/rockchip/rk3506/zboot.its`), Copyright Rockchip. E' l'unico file "solo v2" dell'albero: si combina con GPL-2.0+, ma **blocca un eventuale passaggio a GPLv3**. |
| `external/board/lyra-plus/dts/*.dts` | GPL-2.0+ **OR MIT** | derivato dal DTS vendor, che e' dual-licensed. Header SPDX conservato. |
| `external/board/lyra-plus/patches/uboot/*.patch` | GPL-2.0+ | **non le licenziamo noi.** Il `COPYING` di Buildroot: *"Buildroot also bundles patch files... Those patches are not covered by the license of Buildroot. Instead, they are covered by the license of the software to which the patches are applied."* I file U-Boot toccati sono tutti `SPDX: GPL-2.0+`. |
| `external/package/hello-lyra/src/*` | **MIT** | codice nostro, indipendente. Resta MIT perche' `hello-lyra.mk` dichiara `HELLO_LYRA_LICENSE = MIT` e quel metadato finisce in `make legal-info`: relicenziare il sorgente senza aggiornare il `.mk` produrrebbe un report legale falso. MIT e' comunque compatibile GPL. |
| `external/board/lyra-plus/parameter.txt` | dato Rockchip | tabella delle partizioni copiata dall'SDK, senza intestazione di licenza propria. |
| `build-trace*.log` | output di esecuzione | trace di `build.sh` dell'SDK, conservati come prova; contengono comandi e messaggi degli script Rockchip. |

I `configs/*_defconfig` **non** hanno header SPDX di proposito: `make
savedefconfig` rigenera quei file e ne rimuoverebbe i commenti, rompendo il
criterio di accettazione 2.

> Questa e' igiene di licensing, non consulenza legale. Prima di pubblicare il
> repository vale la pena farla confermare.


## Cosa manca ancora

Estratto dalla tabella completa in `docs/BOARD-FACTS.md`, aggiornato con le
decisioni prese.

| # | Criticita' | Cosa manca |
|---|-----------|------------|
| ~~1~~ | ✅ | Mirror pubblicati e funzionanti: Buildroot li clona e costruisce. |
| ~~2~~ | ✅ | Gli SHA pinnati sono la tip del branch, quindi raggiungibili da un ref. Consigliato pushare anche i tag `vendor-*`: se il branch si sposta, il pin sopravvive solo grazie a quelli. |
| ~~3~~ | ✅ | Blob DDR: path configurabile + verifica sha256, provata in entrambi i versi. |
| ~~9~~ | ✅ | U-Boot 2017.09 con GCC 13: risolto con quattro patch numerate (sotto). |
| **4** | 🟠 | Offset a cui il BootROM RK3506 cerca l'IDB su **SPI NAND**. Accertato solo che i primi 4 MiB sono riservati, e che su SD/eMMC e' il settore 64. Blocca solo `flash.img` come immagine avviabile, non il flash via `update.img`. |
| **5** | 🟡 | Conferma che la NAND sia da 256 MiB con page 2048 B e blocco 128 KiB. Te lo dice `hello-lyra` stesso al primo boot, leggendo `/proc/mtd`. Finche' non e' confermato, `flash.img` non viene paddata alla dimensione del chip. |
| **6** | 🟡 | Quale pettine fisico porta UART0. Il DTS e' inequivoco (`serial-id = <0>`), la serigrafia forse no. |
| **7** | 🟢 | Divergenza in numero di commit del Buildroot SDK vs `2024.02`. Solo documentale. |
| **8** | 🟢 | Se e quando replicare l'AMP. |

#### Le quattro patch a U-Boot

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

### Stato di verifica di questo repository

**La build completa gira e produce le immagini.** `make lyra_plus_defconfig && make`
termina con exit 0 senza interventi manuali (criterio 1).

Confronto degli artefatti con quelli dell'SDK (criterio 4):

| File | Questo repo | SDK | Magic | |
|------|------------:|----:|-------|---|
| `MiniLoaderAll.bin` | 268 736 | 268 736 | `4c 44 52 20` | **stessa dimensione** |
| `uboot.img` | 4 194 304 | 4 194 304 | `d0 0d fe ed` | **stessa dimensione** (2 x FIT paddati a 2 MiB) |
| `boot.img` | 5 745 664 | 6 391 808 | `d0 0d fe ed` | piu' piccolo: niente fragment display, niente moduli |
| `rootfs.img` | 5 767 168 | 124 518 400 | `55 42 49 23` | piu' piccolo: rootfs BusyBox minimale |
| `update.img` | 16 253 514 | 135 649 866 | `52 4b 46 57` | segue rootfs e boot |

Struttura interna, che e' il confronto che conta davvero:

- `boot.img` — nodi `fdt`, `kernel`, `resource`; `/configurations/conf` con
  `fdt=fdt`, `kernel=kernel`, `multi=resource`; kernel `compression=none`,
  `arch=arm`; `resource` di tipo `multi`; primo `data-position` a `2048`
  (= `-p 0x800`). **Identica a quella del `boot.img` dell'SDK**, verificata
  con `fdtget` su entrambi.
- `uboot.img` — nodi `uboot`, `optee`, `fdt`; `/configurations/conf` con
  `firmware=optee`, `loadables=uboot`, `description=rk3506-luckfox`.
  L'hash dell'immagine `optee` nel FIT e' `690eb8a1…`, cioe' esattamente lo
  sha256 di `rk3506_tee_v1.25.bin` registrato in `rkbin.sha256`.
- `rootfs.img` — `magic=UBI#`, `vid_hdr_offset=2048`, `data_offset=4096`:
  page 2048 B e PEB 128 KiB, gli stessi dell'SDK.
- `flash.img` — `uboot.img` a 4 MiB, `boot.img` a 8 MiB, `rootfs.img` a
  32 MiB, magic corretti a ciascun offset.

`MiniLoaderAll.bin` ha la stessa dimensione ma **non** lo stesso contenuto
(differisce dal byte 19): lo SPL e' ricompilato qui con GCC 13 invece del
GCC 10.3 dei prebuilt dell'SDK, e l'header del loader contiene un timestamp.
La dimensione identica e' il segnale che conta: il `boot_merger` ha assemblato
lo stesso layout con gli stessi blob.

Altro verificato:

- ✅ `make savedefconfig` non genera diff su entrambi i defconfig (criterio 2)
- ✅ nessun file di Buildroot upstream modificato: submodule pulito su
  `2026.02.3`, zero righe di `git status` (criterio 3)
- ✅ la libc e' **glibc** (`arm-buildroot-linux-gnueabihf`), non uClibc
- ✅ `hello-lyra` nel rootfs e' un ELF ARM 32-bit **statically linked**,
  `S99hello` e' `0755`, `/etc/lyra-release` riporta i commit giusti
- ⏳ boot reale su hardware: non ancora provato

Non verificato da un clone davvero pulito: `./setup.sh` e' stato eseguito su
questo albero, non su un checkout appena clonato.
