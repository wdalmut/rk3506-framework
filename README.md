# rk3506-framework — Luckfox Lyra Plus su Buildroot upstream

Albero `BR2_EXTERNAL` per la **Luckfox Lyra Plus** (Rockchip **RK3506G2**,
triple Cortex-A7, ARMv7 32-bit, storage SPI NAND), costruito su **Buildroot
upstream** invece che sull'SDK Luckfox.

Kernel e U-Boot restano vendor — mainline non supporta ancora RK3506 — ma sono
agganciati con `_CUSTOM_GIT` a commit SHA fissi, e ogni modifica va come
`.patch` numerata, non come fork.

```bash
./setup.sh
make lyra_plus_defconfig
make
```

Gli artefatti finiscono in `output/images/`.

## Documentazione

Questo README copre **come costruire e usare** il repository. Il resto sta in
[`docs/`](docs/):

| Documento | Cosa contiene |
|-----------|---------------|
| [docs/BOARD-FACTS.md](docs/BOARD-FACTS.md) | Ricognizione dell'SDK: ogni valore con la fonte esatta da cui e' stato ricavato, la catena di packaging Rockchip ricostruita comando per comando, e la tabella dei TODO aperti. **Il primo posto dove guardare se qualcosa non torna.** |
| [docs/SCELTE-DI-PROGETTO.md](docs/SCELTE-DI-PROGETTO.md) | Il *perche'* delle decisioni: glibc e non musl, `fit.sh` e non `make.sh`, nessuna patch a Buildroot, le quattro patch a U-Boot, AMP fuori scope. |
| [docs/check-artifacts.sh](docs/check-artifacts.sh) | Controlla gli invarianti degli artefatti (struttura dei FIT, geometria UBI, offset, contenuto di `update.img`). Da lanciare dopo aver alzato uno SHA o toccato `post-image.sh`. |
| [docs/RELEASE.md](docs/RELEASE.md) | Come pubblicare una release con le immagini gia' costruite, e cosa il testo deve dire. |
| [docs/mk-vendor-mirror.sh](docs/mk-vendor-mirror.sh) | Ricostruisce i mirror di kernel e U-Boot da un checkout SDK shallow. |

## Partire da questo template

Questo repository e' un **template GitHub** e vuole restare il **minimo
indispensabile**: una base che si costruisce, parte e da' una shell, su cui
provare una feature senza rifare ogni volta il porting.

Il modo d'uso previsto e': "Use this template" → repository **privato** → li'
dentro il lavoro vero. Quello che nasce nel progetto resta nel progetto; qui
torna solo cio' che e' utile a *qualunque* progetto su questa board.

```
template (pubblico, stabile)  ──▶  repo privato (display, audio, rete, ...)
        ▲                                    │
        └──── solo miglioramenti alla base ──┘
```

Cosa trovi gia' funzionante:

- build riproducibile in container, da `./setup.sh && make lyra_plus_defconfig && make`
- immagini flashabili: `update.img` e le singole partizioni
- console seriale su `ttyFIQ0`, shell di root
- accesso `adb` via USB
- `hello-lyra`, che al boot dice se la board e' quella giusta e cosa vede
- una variante `initramfs` per il bring-up senza dipendere dalla NAND

Cosa cambiare appena forkato:

1. **Titolo di questo README** e `BR2_TARGET_GENERIC_HOSTNAME` /
   `BR2_TARGET_GENERIC_ISSUE` nei defconfig.
2. **La tua applicazione**, accanto o al posto di `hello-lyra`: copia
   `external/package/hello-lyra/` come scheletro e aggiungi il tuo `source`
   in `external/Config.in`.

`BR2_TARGET_GENERIC_ROOT_PASSWD="lyra"` resta **volutamente banale**: qui serve
una shell in tre secondi. Mettere una password seria, o togliere il login da
seriale, e' compito del progetto che nasce dal fork, non di questa base.

### Cosa NON deve finire qui

Il template si logora se ci si accumulano cose di un progetto specifico.
Restano fuori: driver e device tree di una periferica particolare, package
applicativi, tuning per un caso d'uso, e le tracce di lavorazione di un
porting. Se una cosa serve a *un* progetto, vive nel repo privato di quel
progetto. Se serve a *tutti* i progetti su questa board, allora sale qui.

### Display e i 32 MiB di CMA

Vale la pena saperlo prima di guardare `MemTotal` e pensare che qualcosa non
va: **la board ha 32 MiB di CMA riservati, e restano riservati di proposito.**

Il DTS vendor fa `&cma { size = <0x2000000>; }` sotto il commento
`/**********display**********/`, mentre il default nel dtsi e' `0`. Quella
memoria serve al VOP per allocare i framebuffer. Questa base **non** applica il
fragment `rk3506-display.config` del kernel, quindi il driver non c'e' e quei
32 MiB oggi non li usa nessuno: `MemTotal` risulta 87,1 MiB e `CmaFree` zero.

Restano lo stesso, perche' il CMA e' la meta' che costa cambiare. Accendere un
pannello per un esperimento vuol dire aggiungere il fragment display al
proprio repo e basta; se invece il CMA fosse azzerato qui, bisognerebbe anche
scrivere un DTS di board solo per rimetterlo, e il sintomo di essersene
dimenticati e' un VOP che non alloca — oscuro da diagnosticare.

Il verso giusto e' l'opposto: **si tolgono in fase di target**, quando si sa
che quel prodotto il display non ce l'ha. Sono 32 MiB su 128, cioe' il 37% di
RAM utilizzabile in piu', e si recuperano con un DTS custom che azzera `&cma`
via `BR2_LINUX_KERNEL_CUSTOM_DTS_PATH` — lo stesso meccanismo gia' usato per
la variante initramfs.

Misure e conti in [docs/BOARD-FACTS.md](docs/BOARD-FACTS.md).

Se un giorno serve portare **un'altra board Rockchip** e non un altro progetto
su questa, il lavoro e' diverso: `post-image.sh` ha `RK3506MINIALL.ini`,
`RK3506TOS.ini` e `rk3506_ddr_750MHz_v1.04.bin` scritti dentro, e
`BOARD-FACTS.md` andrebbe rifatto da capo. Meglio un template dedicato.

### Controlli automatici

`.github/workflows/checks.yml` verifica a ogni push cio' che si rompe in
silenzio: che `savedefconfig` non generi diff, che la toolchain resti glibc e
non scivoli su uClibc, che gli script siano validi ed eseguibili, che
`hello-lyra` passi `gofmt`/`vet` e cross-compili ARMv7 statico, e che non ci
siano link morti fra i documenti.

**Non** c'e' una build completa, e non e' una dimenticanza: servirebbe `rkbin`,
che non e' pubblico. Per la stessa ragione `docs/check-artifacts.sh` non gira
in CI — senza build non ci sono artefatti — e resta un comando da lanciare a
mano dopo aver alzato uno SHA o toccato `post-image.sh`.

## Indice

- [Partire da questo template](#partire-da-questo-template)
- [Struttura](#struttura)
- [Prerequisiti](#prerequisiti)
- [Build](#build)
- [Immagini precompilate](#immagini-precompilate)
- [Flash](#flash)
- [Console seriale](#console-seriale)
- [Accesso via USB (adb)](#accesso-via-usb-adb)
- [Output atteso a boot riuscito](#output-atteso-a-boot-riuscito)
- [Licenza](#licenza)

---

## Struttura

```
.
├── README.md                     questo file: build e uso
├── LICENSE                       GPL-2.0
├── setup.sh                      prepara il clone (submodule, SDK, immagine docker)
├── Makefile                      wrapper: make shell / defconfig / build
├── docker/Dockerfile             Ubuntu 22.04, unico posto dove si compila
├── docs/                         riferimento di board, scelte, strumenti
├── buildroot/                    submodule upstream, tag 2026.02.3 (LTS)
├── vendor/                       submodule: binari Rockchip non ricompilabili
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
    │   └── rootfs_overlay/       /etc/init.d/{S45adb,S99hello}
    └── package/hello-lyra/       applicazione Go di verifica
```

Il file da guardare per primo, se una build non torna, e'
`external/board/lyra-plus/post-image.sh`: e' li' che si arenano i porting da
SDK Rockchip. `build.sh` non compila soltanto, dopo kernel e U-Boot invoca i
tool che producono le immagini flashabili (`boot_merger`, `mkimage`,
`resource_tool`, `afptool`, `rkImageMaker`). Buildroot non ne sa nulla, e
`post-image.sh` deve rifare quella sequenza.

---

---

## Prerequisiti

Sull'host servono due cose:

| Cosa | Perche' |
|------|---------|
| `git` | i submodule: Buildroot e i binari vendor |
| `docker` | tutta la compilazione avviene dentro il container |

Non serve installare toolchain, `python2`, `gcc` vecchi o altro: stanno nel
container. **E non serve l'SDK Luckfox.**

### I binari vendor stanno nel submodule `vendor`

Alcune cose non sono ricompilabili dai sorgenti e vanno prese cosi' come sono:

| File | A che serve |
|------|-------------|
| `vendor/rkbin/bin/rk35/rk3506_ddr_750MHz_v1.04.bin` | init DDR, eseguita dal BootROM |
| `vendor/rkbin/bin/rk35/rk3506_tee_v1.25.bin` | OP-TEE, finisce nel FIT di `uboot.img` |
| `vendor/rkbin/bin/rk35/rk3506_usbplug_v1.02.bin` | CODE472, modalita' MaskROM/USB |
| `vendor/rkbin/tools/{boot_merger,mkimage}` | assemblano loader e FIT |
| `vendor/rkbin/RKBOOT/RK3506MINIALL.ini`, `RKTRUST/RK3506TOS.ini` | dicono ai tool cosa mettere dove |
| `vendor/packtool/{afptool,rkImageMaker}` | producono `update.img` |

Vengono da [rk3506-vendor-kit](https://github.com/wdalmut/rk3506-vendor-kit),
estratti dall'SDK Luckfox e ridistribuiti secondo la licenza Rockchip, che
consente esplicitamente uso, copia e distribuzione.

Esiste come repository separato per un motivo pratico: l'SDK Luckfox completo
pesa **30 GB**, e questa roba ne e' lo **0,2%**. Senza, per costruire
un'immagine bisognerebbe prima fare un `repo sync` dell'intero SDK per usarne
62 MB.

I blob non sono usati alla cieca: `post-image.sh` ne verifica lo `sha256`
contro `external/board/lyra-plus/rkbin.sha256` e **si ferma** se non
corrispondono. Per puntare a un altro checkout `rkbin` bastano
`BR2_LYRA_RKBIN_DIR` e `BR2_LYRA_PACKTOOL_DIR` in `make menuconfig` →
*Luckfox Lyra Plus*: un percorso relativo si intende dalla radice del
repository, uno assoluto va dove vuoi.

### Quando serve comunque l'SDK

Per costruire, mai. Serve solo per due cose accessorie, ed entrambe sono
opzionali:

- rigenerare i mirror di kernel e U-Boot con
  [docs/mk-vendor-mirror.sh](docs/mk-vendor-mirror.sh), se esce un SDK nuovo;
- confrontare gli artefatti con quelli prodotti dall'SDK in
  [docs/check-artifacts.sh](docs/check-artifacts.sh).

Se `~/git/luckfox-lyra` esiste il `Makefile` lo monta read-only su `/sdk`; se
non c'e', non succede niente.

### Mirror di kernel e U-Boot

I due `_CUSTOM_GIT` puntano a:

| | URL | Commit |
|---|-----|--------|
| kernel 6.1.99 | `https://github.com/wdalmut/rk3506-kernel.git` | `73bca17b67938d649b072408780369f600555263` |
| U-Boot 2017.09 | `https://github.com/wdalmut/rk3506-uboot.git` | `1625f78b6dcf9fe401d447da79132b7bc6804538` |

Sono **mirror**: l'origine dell'SDK e' `ssh://git@192.168.10.75/...`, una LAN
privata Luckfox non raggiungibile da fuori. I commit non hanno parent e riusano
l'oggetto tree del commit vendor, quindi il contenuto e' identico bit per bit;
lo SHA differisce perche' differiscono i parent. Si rigenerano con
[docs/mk-vendor-mirror.sh](docs/mk-vendor-mirror.sh).

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
    -u "$(id -u):$(id -g)" \
    -w /work rk3506-framework:build bash
```

Un mount solo: i binari vendor sono nel submodule `vendor`, quindi gia' dentro
`/work`. Se `$SDK_DIR` esiste, il `Makefile` aggiunge `-v $SDK_DIR:/sdk:ro`,
ma serve solo ai confronti, non alla build.

### Variante initramfs (primo bring-up)

```bash
make lyra_plus_initramfs_defconfig
make
```

Rootfs incorporato in `zImage` e quindi in `boot.img`: non c'e' `rootfs.img` e
la NAND non viene toccata. Se la board arriva alla shell con questa immagine,
NAND, UBI e partizionamento sono fuori dall'equazione — e resta da guardare
solo il resto. E' l'immagine giusta con cui cominciare su hardware nuovo.

### Iterare su `hello-lyra`

**`make` da solo non ricostruisce `hello-lyra` quando ne cambi il sorgente.**
Non e' un bug: il package usa `SITE_METHOD = local`, che in Buildroot diventa
un `OVERRIDE_SRCDIR`. Per quei package il sorgente viene copiato nella build
dir una volta sola (`.stamp_rsynced`) e i `make` successivi saltano il package
interamente. Il risultato e' che compili, non vedi errori, e ottieni il binario
di prima.

Serve chiederlo esplicitamente:

```bash
make hello-lyra-rebuild     # ri-sincronizza il sorgente e ricompila
make                        # rigenera rootfs.img e le altre immagini
```

Per controllare di avere davvero il binario nuovo prima di flasharlo o
pusharlo:

```bash
strings output/target/usr/bin/hello-lyra | grep -c CmaTotal   # una stringa che sai di aver aggiunto
```

Con adb attivo si itera senza riflashare:

```bash
make hello-lyra-rebuild
adb push output/target/usr/bin/hello-lyra /usr/bin/
adb shell hello-lyra
```

Il rootfs e' montato in scrittura (`BR2_TARGET_GENERIC_REMOUNT_ROOTFS_RW=y`),
quindi il push funziona. Attenzione pero': quello che scrivi cosi' vive nella
UBI della board e sparisce al primo riflash del `rootfs.img`.


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

---

## Immagini precompilate

Se ti serve solo **verificare che una scheda parta**, non c'e' bisogno di
costruire niente: le [Releases](../../releases) contengono un `update.img` gia'
provato su hardware, con `MiniLoaderAll.bin`, `parameter.txt` e `SHA256SUMS`.

```bash
sha256sum -c SHA256SUMS
sudo rkdeveloptool db MiniLoaderAll.bin
sudo rkdeveloptool uf update.img
sudo rkdeveloptool rd
```

Poi console a 1500000 8N1: se `hello-lyra` stampa modello, memoria e partizioni
MTD, la scheda e' viva e il porting funziona su quell'esemplare.

Le release si pubblicano **a mano**, non dalla CI: servirebbe `rkbin`, che non
e' pubblico. Come farlo e' in [docs/RELEASE.md](docs/RELEASE.md).


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
accertato — vedi [docs/BOARD-FACTS.md](docs/BOARD-FACTS.md), sezione *Aperti*.

---

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

> Su quale pettine della Lyra Plus escano fisicamente quei pin non e'
> ricavabile dall'SDK: lo script `flash.sh` parla di "UART2", ma il DTS dice
> `serial-id = <0>`. Il baudrate e la periferica sono invece certi.

---

---

## Accesso via USB (adb)

Oltre alla seriale la board espone un **gadget USB ADB**, cosi' si puo'
iterare senza riflashare:

```bash
adb devices          # atteso: <seriale>  device
adb shell
adb push output/target/usr/bin/hello-lyra /usr/bin/    # ricompila e prova
```

Collegare la USB-C alla porta **OTG0** (quella che il DTS mette in
`dr_mode = "peripheral"`), non a OTG1 che e' host.

| | |
|---|---|
| VID:PID | `2207:0006` |
| Funzione | `ffs.adb` via configfs |
| Script | `/etc/init.d/S45adb` |
| Binario | `/usr/bin/adbd`, da `BR2_PACKAGE_ANDROID_TOOLS_ADBD` upstream |

`2207` e' Rockchip e `0006` e' la convenzione per il solo ADB (la stessa
tabella di `usb_pid()` in `rkscript/usbdevice`), quindi eventuali regole udev
gia' presenti sull'host continuano a funzionare. Se `adb devices` mostra
`no permissions`:

```bash
echo 'SUBSYSTEM=="usb", ATTR{idVendor}=="2207", MODE="0666", GROUP="plugdev"' \
    | sudo tee /etc/udev/rules.d/51-rockchip.rules
sudo udevadm control --reload-rules
```

Se il device non enumera, la diagnosi si fa dalla seriale:

```
/etc/init.d/S45adb restart      # rilancia e stampa l'errore
ls /sys/class/udc/              # atteso: ff740000.usb (OTG0, usb@ff740000 nel DTS)
ls /dev/usb-ffs/adb/            # dopo l'avvio devono esserci ep0 ep1 ep2
```

Se ci sono `ep1`/`ep2` ma il gadget non enumera, il problema e' a valle
(cavo, porta, host). Se c'e' solo `ep0`, adbd non ha scritto i descrittori e
`S45adb` non lega l'UDC apposta — vedi sotto.
adbd tira dentro openssl: il rootfs passa da 5,5 a 8,6 MiB. Per toglierlo,
via `BR2_PACKAGE_ANDROID_TOOLS_ADBD` dal defconfig e `S45adb` dall'overlay.
Il perche' di questo script invece di `usbdevice` dell'SDK e' in
[docs/SCELTE-DI-PROGETTO.md](docs/SCELTE-DI-PROGETTO.md#usb-perche-non-usiamo-usbdevice-dellsdk).

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
- **`MemTotal`** — la board monta 128 MiB di DDR; se la RAM e' molto meno del
  previsto, il blob DDR non ha fatto il suo lavoro. E' il primo posto dove guardare quando il boot e'
  instabile. Attenzione pero': **87,1 MiB e' il valore normale su questa
  base**, non un sintomo. Mancano i 32 MiB di CMA riservati al display, che
  sono tenuti apposta — vedi [Display e i 32 MiB di CMA](#display-e-i-32-mib-di-cma).
- **`mtd0/1/2`** — nomi e dimensioni devono combaciare con `parameter.txt`. Se
  non c'e' nessuna partizione, `mtdparts=` non e' arrivato al kernel: il DTB e'
  sbagliato o U-Boot ha sovrascritto il bootargs.

I valori numerici sopra (MemTotal, uptime, data) sono indicativi; quelli
misurati su questa board — 128 MiB di DDR, NAND da 256 MiB — stanno nella
tabella d'identita' di [BOARD-FACTS](docs/BOARD-FACTS.md).

Con la variante initramfs, `/proc/mtd` puo' essere vuoto o assente: e'
previsto, il rootfs non sta su NAND.

Prima di questo, `S45adb` stampa una riga sola:

```
S45adb: gadget ADB attivo su ff740000.usb (0x2207:0x0006)
```

Se invece dice `nessun UDC` o `adbd non ha scritto i descrittori`, la
board comunque completa il boot: il gadget e' una comodita', non una
dipendenza dell'avvio.

---

---

## Licenza

**GPL-2.0-or-later**, come Buildroot e U-Boot. Testo completo in
[LICENSE](LICENSE).

Ogni file dichiara la propria licenza con un header `SPDX-License-Identifier`,
quindi le eccezioni si leggono dal file stesso. Le due che conviene sapere a
memoria:

- `external/board/lyra-plus/boot.its` e' **GPL-2.0-only** (copiato verbatim
  dall'SDK, Copyright Rockchip): e' l'unico file "solo v2" dell'albero e
  **blocca un eventuale passaggio a GPLv3**.
- `external/package/hello-lyra/src/` e' **MIT**, coerentemente con
  `HELLO_LYRA_LICENSE` dichiarato nel `.mk` e quindi con `make legal-info`.

Le patch in `patches/uboot/` non le licenziamo noi: valgono le regole di
Buildroot, che le fa ricadere sotto la licenza del software a cui si applicano
(U-Boot, GPL-2.0+).
