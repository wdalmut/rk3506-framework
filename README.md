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
| [docs/mk-vendor-mirror.sh](docs/mk-vendor-mirror.sh) | Ricostruisce i mirror di kernel e U-Boot da un checkout SDK shallow. |
| [docs/traces/](docs/traces/) | I trace di `build.sh` dell'SDK da cui e' stata ricostruita la catena di packaging. BOARD-FACTS li cita per numero di riga. |

## Partire da questo template

Questo repository e' un **template GitHub**: "Use this template" crea un nuovo
progetto con tutti i file e una storia nuova. E' pensato per far partire un
altro progetto **sulla stessa Luckfox Lyra Plus**, quindi tutto cio' che
riguarda la board — `parameter.txt`, `boot.its`, il DTS, gli SHA di kernel e
U-Boot, `docs/BOARD-FACTS.md`, i trace — va **tenuto**: e' gia' verificato su
hardware e non va rifatto.

Cosa cambiare, in ordine di importanza:

1. **La password di root.** `BR2_TARGET_GENERIC_ROOT_PASSWD="lyra"` nei due
   defconfig. Va bene per il bring-up, **non** per qualcosa che esce
   dall'ufficio: ogni progetto creato da questo template nascerebbe con la
   stessa password nota. Cambiala subito, o metti
   `# BR2_TARGET_ENABLE_ROOT_LOGIN is not set` se il progetto non ha bisogno
   di login da seriale.
2. **Nome e identita' del progetto**: titolo di questo README,
   `BR2_TARGET_GENERIC_HOSTNAME` e `BR2_TARGET_GENERIC_ISSUE` nei defconfig.
3. **La tua applicazione**, accanto a `hello-lyra`: copia
   `external/package/hello-lyra/` come punto di partenza, e aggiungi il tuo
   `source` in `external/Config.in`.

Cosa **non** cambiare:

- **`hello-lyra` conviene tenerla.** Non e' un esempio da buttare: e' la
  diagnostica che ha chiuso due TODO aperti su questa board, leggendo modello,
  memoria, CMA e partizioni MTD. Su un progetto nuovo e' la prima cosa da
  lanciare quando qualcosa non parte, e costa 1,7 MB.
- `docs/BOARD-FACTS.md` e `docs/traces/`: sono i fatti misurati di questa
  board, con la fonte di ogni valore. Riscriverli da zero sarebbe rifare la
  ricognizione.

Se un giorno serve portare **un'altra board Rockchip** e non un altro progetto
sulla stessa, il lavoro e' diverso: `post-image.sh` ha `RK3506MINIALL.ini`,
`RK3506TOS.ini` e `rk3506_ddr_750MHz_v1.04.bin` scritti dentro, e
`BOARD-FACTS.md` andrebbe svuotato e rifatto. Conviene partire da un template
dedicato, non da qui.

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
├── docs/                         tutto il resto della documentazione
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
accertato — vedi [docs/BOARD-FACTS.md](docs/BOARD-FACTS.md), TODO-4.

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

> Su quale pettine della Lyra Plus escano fisicamente quei pin resta da
> confermare ([BOARD-FACTS](docs/BOARD-FACTS.md), TODO-6): lo script `flash.sh`
> dell'SDK parla di "UART2", ma il
> DTS dice `serial-id = <0>`. Il baudrate e' invece certo.

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
- **`MemTotal`** — se la RAM e' molto meno del previsto, il blob DDR non ha
  fatto il suo lavoro. E' il primo posto dove guardare quando il boot e'
  instabile.
- **`mtd0/1/2`** — nomi e dimensioni devono combaciare con `parameter.txt`. Se
  non c'e' nessuna partizione, `mtdparts=` non e' arrivato al kernel: il DTB e'
  sbagliato o U-Boot ha sovrascritto il bootargs.

I valori numerici sopra (MemTotal, uptime, date) sono ovviamente indicativi;
I valori numerici sopra sono indicativi; per quelli reali di questa board vedi
[BOARD-FACTS](docs/BOARD-FACTS.md), TODO-5, sulla dimensione
effettiva di RAM e NAND.

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
