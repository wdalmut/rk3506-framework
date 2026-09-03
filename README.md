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
- due varianti con **kernel mainline 6.19** (`ttyS0`), accanto alle due
  vendor 6.1 e non al loro posto — una initramfs e una con il rootfs su SPI
  NAND: vedi [Variante mainline 6.19](#variante-mainline-619-kernel-upstream)

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
    │   ├── lyra_plus_initramfs_defconfig  rootfs in RAM (bring-up)
    │   ├── lyra_plus_mainline_defconfig   SPI NAND + UBIFS, kernel MAINLINE 6.19
    │   └── lyra_plus_mainline_initramfs_defconfig
    │                                      rootfs in RAM, kernel MAINLINE 6.19
    ├── board/lyra-plus/
    │   ├── linux.config          fragment kernel vendor 6.1
    │   ├── linux-mainline.config fragment kernel mainline 6.19 (condiviso)
    │   ├── linux-mainline-flash.config
    │   │                         cmdline con root su UBIFS (solo mainline+flash)
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
    └── package/
        ├── hello-lyra/           applicazione Go di verifica
        └── rk-resource-tool/     resource_tool di Rockchip, host package
                                  (sorgente vendorizzato + provenienza)
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

Il percorso mainline usa un terzo repository, `rk3506-kernel-upstream.git`, con
il DTS di board e le sue correzioni; lo SHA e' nel defconfig.

### `MIRROR=` — quando GitHub non serve i fetch git anonimi

**Sintomo.** La build si ferma sul kernel o su U-Boot con un messaggio che
manda fuori strada:

```
>>> linux-headers <sha> Downloading
fatal: could not read Username for 'https://github.com': No such device or address
fatal: the remote end hung up unexpectedly
Detected a corrupted git cache.
```

Sembra un repository privato o una chiave SSH mancante. **Non lo e'.** GitHub
risponde `401` a `POST /git-upload-pack` quando il client non e' autenticato, e
git riporta quel 401 come una richiesta di credenziali. Il container non ne ha,
per scelta: monta solo `/work`, quindi niente `~/.ssh`, niente `~/.gitconfig`,
niente credential helper. Che l'host sia autenticato non conta — la build non
gira sull'host.

Riguarda **solo** kernel e U-Boot, che sono `BR2_*_CUSTOM_GIT`. Gli altri ~80
package scaricano tarball via HTTPS normale e funzionano.

**Rimedio: un mirror dei tarball.**

```sh
make MIRROR=https://<host>/dl lyra_plus_mainline_initramfs_defconfig
make MIRROR=https://<host>/dl
```

Diventa `BR2_PRIMARY_SITE`: provato **prima** del sito upstream di ogni
package, con fallback su quest'ultimo. Servendo file su HTTPS evita del tutto
il protocollo git. Il layout atteso e' quello di `dl/` di Buildroot:

```
https://<host>/dl/linux/linux-<sha>-git4.tar.gz
https://<host>/dl/uboot/uboot-<sha>-git4.tar.gz
```

Per non ripeterlo a ogni comando, l'URL puo' stare in `local.mk`, che e' in
`.gitignore`:

```sh
echo 'MIRROR = https://<host>/dl' > local.mk
```

**In questo albero non c'e' nessun URL di mirror**, e non e' una dimenticanza:
un mirror e' infrastruttura di chi lo paga, e questo repository e' pubblico.
Chi ne ha uno lo indica con `MIRROR=`; chi non ne ha non paga il traffico di
nessun altro.

**Pubblicare un mirror**, se ne volete uno: bastano `dl/` servita su HTTPS —
un bucket S3, un CloudFront, un nginx. Le cache di lavoro git **non** vanno
caricate (sono checkout, non tarball, e Buildroot le ricrea: 2.4 GB dei 3.5
totali):

```sh
cd buildroot/dl
aws s3 cp . s3://<bucket>/dl/ --recursive \
    --exclude "*/git/*" --exclude "*/git" \
    --exclude "*.lock" --exclude "*/git.readme" \
    --exclude "br-cargo-home/*"
```

Se il bucket e' public-read, l'URL e' un segreto solo per oscurita': chi lo
scopre scarica a spese vostre. Una condizione `aws:SourceIp` nella bucket
policy limita l'accesso alle vostre reti senza rimettere credenziali nel
container.

**Rimedio alternativo, senza mirror**: scaricare i due tarball **dall'host**,
dove git e' autenticato, nella cache condivisa. Serve una volta per SHA.

```sh
make -C buildroot O="$PWD/out-dl" BR2_EXTERNAL="$PWD/external" \
     lyra_plus_mainline_initramfs_defconfig
make -C buildroot O="$PWD/out-dl" BR2_EXTERNAL="$PWD/external" \
     linux-source uboot-source
rm -rf out-dl
```

Serve una output dir separata: la `.config` in `output/` contiene i path del
**container** (`/work/external/...`), e dall'host Buildroot si ferma con
*"BR2_GLOBAL_PATCH_DIR contains nonexistent directory"*.

**Verificare che un mirror funzioni davvero.** Non basta lanciare `make` con
`MIRROR=`: se i tarball sono gia' in `dl/` non viene scaricato niente e la
build passa senza toccare il mirror. Anche `make <pkg>-source` da solo non
basta, perche' Buildroot vede lo `.stamp_downloaded` e salta in silenzio.
Serve rimuovere lo stamp, e conviene farlo sul package piu' piccolo:

```sh
mv buildroot/dl/uboot/uboot-<sha>-git4.tar.gz /tmp/          # da parte, non cancellato
rm -f output/build/uboot-*/.stamp_downloaded
make MIRROR=https://<host>/dl uboot-source
make uboot-dirclean                                          # OBBLIGATORIO, vedi sotto
```

> **Il `uboot-dirclean` non e' opzionale.** Togliere lo `.stamp_downloaded`
> lascia la directory di build in uno stato incoerente: i sorgenti sono ancora
> quelli estratti e **gia' patchati** dal giro precedente, ma per Buildroot il
> download non e' mai avvenuto, quindi al `make` successivo ri-estrae e
> ri-applica le patch sopra un albero che le ha gia'. Il sintomo non e' un
> errore di patch, e' questo:
>
> ```
> Error: duplicate filename '0001-common-edid-initialize-hdmi_len-to-silence-gcc-13.patch'
> ```
>
> cioe' `apply-patches.sh` che trova due volte lo stesso nome nella lista.
> Sembra un problema delle patch e non lo e'. Il `-dirclean` riporta il
> package allo stato "da estrarre" e il giro dopo e' pulito.

Nel log deve comparire il `wget` sull'URL del mirror e nessun tentativo git:

```
>>> uboot <sha> Downloading
wget ... 'https://<host>/dl/uboot/uboot-<sha>-git4.tar.gz'
HTTP request sent, awaiting response... 200 OK
```

Poi confronta lo sha256 con la copia messa da parte: i `-git4.tar.gz` sono
generati da Buildroot con un `tar` riproducibile, quindi devono essere
identici byte per byte. Se differiscono, il mirror serve una variante e i
checksum non torneranno.

> **Limite noto.** Senza mirror e senza uno dei due rimedi, un clone fresco
> **non** completa la build: i package di terzi scaricano, kernel e U-Boot no.
> Il perche' della diagnosi, con i test che la inchiodano, e' in
> [docs/SCELTE-DI-PROGETTO.md](docs/SCELTE-DI-PROGETTO.md).

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

### Variante mainline 6.19 (kernel upstream)

```bash
make lyra_plus_mainline_initramfs_defconfig
make
```

Stessa board, stesso U-Boot, stessa catena di packaging, ma kernel **mainline
6.19.0** invece del vendor 6.1.99. Esiste per rispondere a una domanda sola:
quanto di questa board si regge su codice upstream? Non sostituisce i due
defconfig vendor, che restano intatti come termine di paragone.

Cosa cambia rispetto a `lyra_plus_initramfs_defconfig`:

| | vendor | mainline |
|---|---|---|
| kernel | 6.1.99, `rk3506-kernel.git` | 6.19.0, `rk3506-kernel-upstream.git` |
| defconfig kernel | `rk3506_luckfox` | `multi_v7` + `linux-mainline.config` |
| DTB | `dts/rk3506g-lyra-plus-initramfs.dts` | in-tree `rockchip/rk3506g-luckfox-lyra-plus` |
| **console** | **`ttyFIQ0`** | **`ttyS0`** |
| bootargs | dal DTS (`/chosen`) | dal kernel (`CONFIG_CMDLINE_FORCE`) |
| MTD, adb | presenti | assenti (bring-up da sola console) |
| rete | presente | **assente** (`CONFIG_NET` spento) |
| `zImage` | 8.83 MiB | 6.16 MiB |
| `boot.img` | 10.32 MiB | **5.90 MiB** |
| RAM disponibile | — | **116 MB** su 128 (CMA spento) |

Il baudrate resta **1500000**: cambia il nome del device, non l'hardware —
è sempre UART0 `@0xff0a0000`.

> #### Perché il fragment spegne mezzo kernel
>
> `multi_v7_defconfig` è un defconfig **multi-piattaforma**: accende 76
> famiglie di SoC ARMv7, e RK3506 è una di quelle. Così com'è produce uno
> `zImage` di 15.07 MiB e un `boot.img` di 15.09 MiB, che **non entra** nella
> partizione `boot` da 12 MiB — e la build fallisce nella verifica dimensioni
> di `post-image.sh`, invece di darti un'immagine non flashabile.
>
> `linux-mainline.config` spegne quindi 72 piattaforme estranee e i
> sottosistemi che nessun nodo del dtsi minimale reclama, arrivando a 6.16 MiB
> di `zImage` e 6.18 MiB di `boot.img` — 5.8 MiB di margine.
> Il pruning delle sole piattaforme non bastava: 12.11 MiB, 0.13 MiB sopra il
> limite.
>
> **Conseguenza da sapere prima di usarla: questa immagine non ha rete.**
> Si lavora dalla seriale. Come riabilitarla, e perché non si è allargata la
> partizione invece, sono in
> [docs/SCELTE-DI-PROGETTO.md](docs/SCELTE-DI-PROGETTO.md).

> #### Il DTS dichiara quale RAM è di Linux
>
> Il DTS di board ha `linux,usable-memory-range = <0x00200000 0x07e00000>` in
> `/chosen`. **Senza, la board non parte e non stampa niente** — nemmeno con
> `earlycon`, nemmeno con `CONFIG_DEBUG_LL`.
>
> Con `AUTO_ZRELADDR` il decompressore mette la propria page directory a
> `0x00004000` e il kernel a `0x00008000`, dentro la regione di OP-TEE
> (`trust@0`, `0x0–0x62000`), che il firewall del SoC rende inaccessibile dal
> normal world: dal prompt U-Boot anche un semplice `md 0x4000` dà *data
> abort*. La proprietà sposta page directory e kernel a `0x00204000` /
> `0x00208000`.
>
> Sta nel **repo del kernel**, non qui: il DTS è di questa board e la
> correzione va dove vive il DTS. Il framework non porta nessuna patch al
> kernel. La ricostruzione completa, con i riferimenti al sorgente e le due
> ipotesi sbagliate scartate lungo la strada, è in
> [docs/SCELTE-DI-PROGETTO.md](docs/SCELTE-DI-PROGETTO.md).

> #### ⚠️ I due `boot.img` non vanno mescolati
>
> Gli ID dei clock nei dt-bindings RK3506 sono **rinumerati** fra il 6.1
> vendor e mainline (`PCLK_UART0` 113 → 99, `SCLK_UART0` 118 → 104, in
> `include/dt-bindings/clock/rockchip,rk3506-cru.h:112,117` di ciascun
> repo). Un DTB vendor su kernel mainline, o viceversa, **compila, boota e
> programma i clock sbagliati**: nessun errore, solo una board muta.
>
> Per capire a colpo d'occhio quale immagine si ha in mano:
>
> ```bash
> cat output/images/lyra-manifest.txt      # kernel, commit, DTB, console
> ls output/images/boot-*.img             # boot-6.1.99.img oppure boot-6.19.0.img
> ```
>
> `boot-<release>.img` è un hard link a `boot.img` — stesso contenuto, zero
> byte in più, nome inequivocabile. Anche `/etc/issue` sul target lo dice,
> prima del prompt di login.

Il perché di ogni differenza è in
[docs/SCELTE-DI-PROGETTO.md](docs/SCELTE-DI-PROGETTO.md), sezione *Il percorso
mainline 6.19, accanto al vendor 6.1* — incluso il motivo per cui
`resource.img` non si può togliere e `resource_tool` è stato vendorizzato.

#### Con il rootfs sulla SPI NAND

```bash
make lyra_plus_mainline_defconfig
make
```

È il controparte mainline di `lyra_plus_defconfig`: rootfs UBIFS sulla NAND
invece che in RAM. Il diff fra i due defconfig mainline è **lo stesso** che
separa i due vendor — rootfs UBI al posto di initramfs, `BR2_PACKAGE_MTD`,
`host-genimage` — più una cosa in più: un secondo fragment kernel,
`linux-mainline-flash.config`, applicato dopo quello condiviso.

Il fragment in più serve per una ragione precisa, che vale la pena sapere
prima di toccare il layout delle partizioni:

> **Le partizioni MTD non possono arrivare da U-Boot su mainline.** Non è una
> conseguenza di `CONFIG_CMDLINE_FORCE=y`: nemmeno rilassandolo funzionerebbe.
> U-Boot genera un `mtdparts` corretto e in byte, ma con `mtd-id` `spi-nand0`,
> perché il kernel **vendor** forza `mtd->name = "spi-nand0"` con una patch
> locale Rockchip. Mainline non ha quella patch e il nome del device MTD
> diventa `spi0.0`; `cmdlinepart` pretende che l'`mtd-id` combaci
> esattamente, quindi la stringa di U-Boot viene scartata in silenzio. Anche
> il `CMDLINE:` di `parameter.txt` non serve: ha `mtd-id` vuoto (che non è un
> jolly) e le size in settori — è il formato per il tool di flash, non una
> cmdline Linux.
>
> Il layout è quindi dichiarato **nella nostra cmdline**, con l'`mtd-id` di
> mainline e in byte. Costo: lo stesso layout è scritto in tre posti
> (`parameter.txt` e i due fragment) e **nessuno li confronta**. Se cambi
> `parameter.txt`, cambia anche i due fragment. Le righe di sorgente che
> inchiodano la diagnosi sono in
> [docs/SCELTE-DI-PROGETTO.md](docs/SCELTE-DI-PROGETTO.md), sezione *La SPI
> NAND su mainline, e l'`mtd-id` che nessuno fa combaciare*.

La buona notizia è l'altra metà: **il driver SPI NAND di mainline guida
l'FSPI del RK3506 senza una riga di modifica al kernel.** Un solo compatible
generico `rockchip,sfc`, versione dell'IP letta a runtime dal registro
`SFC_VER`, nessuna tabella per SoC da estendere. Tutto il lavoro è il device
tree. Sull'hardware:

```
spi-nand spi0.0: Winbond SPI NAND was found.
spi-nand spi0.0: 256 MiB, block size: 128 KiB, page size: 2048, OOB size: 128
3 cmdlinepart partitions found on MTD device spi0.0
```

Nota per non cercare dalla parte sbagliata: **`rockchip-sfc` non compare nel
`dmesg` nemmeno quando funziona.** Quel driver non ha un solo `dev_info`, solo
`dev_err` e `dev_dbg`. La prova che il probe è andato è che esiste `spi0.0`.

Il boot completo, con la root montata da UBIFS:

```
ubi0: volume 0 ("rootfs") re-sized from 42 to 1748 LEBs
ubi0: attached mtd2 (name "rootfs", size 224 MiB)
ubi0: good PEBs: 1790, bad PEBs: 2, corrupted PEBs: 0
UBIFS (ubi0:0): FS size: 220557312 bytes (210 MiB, 1737 LEBs), max 8456 LEBs
VFS: Mounted root (ubifs filesystem) on device 0:13.
```

La riga `re-sized` è quella che conta: il volume UBI cresce da solo fino a
riempire la partizione (`vol_flags=autoresize`), quindi **la dimensione del
chip non è cablata da nessuna parte** — né nel defconfig, né nella cmdline,
né nel DTS. Su questo esemplare la NAND è da 256 MiB, la partizione `rootfs`
224, il filesystem 210, e `df` mostra 193.8M disponibili.

> `MAXLEBCNT=8456` sembra sovradimensionato (≈ 1 GiB) e la tentazione è
> stringerlo. **Non farlo.** Un valore troppo piccolo non dà errore: tappa il
> filesystem sotto la partizione, in silenzio — al mount UBIFS fa
> `c->leb_cnt = min(c->max_leb_cnt, c->vi.size)`. E la dimensione del volume
> varia da esemplare a esemplare col numero di blocchi guasti (qui 2 su 1792),
> quindi un valore tarato su una scheda ne tapperebbe un'altra. Il costo
> misurato del valore alto è 11 LEB di metadati in tutto, 1.36 MiB su 224.
> Il ragionamento completo è in
> [docs/SCELTE-DI-PROGETTO.md](docs/SCELTE-DI-PROGETTO.md).

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

### Prima di flashare: quale immagine ho in mano?

Un passo di dieci secondi che evita l'errore piu' costoso di questo albero —
flashare il `boot.img` mainline su una board che ha il DTB vendor in NAND, o
viceversa. Non da' errori: da' una board muta (vedi
[Variante mainline 6.19](#variante-mainline-619-kernel-upstream)).

```bash
cat output/images/lyra-manifest.txt
```

```
board=lyra-plus
soc=rk3506g2
kernel_release=6.19.0
kernel_repo=https://github.com/wdalmut/rk3506-kernel-upstream.git
kernel_commit=8f714b5131404d31d6964b686d7b6e7740f9dcab
kernel_defconfig=multi_v7
dtb=rockchip/rk3506g-luckfox-lyra-plus.dtb
console=ttyS0
...
```

Oppure, senza aprire niente:

```bash
ls output/images/boot-*.img
#   boot-6.19.0.img   -> mainline, console ttyS0
#   boot-6.1.99.img   -> vendor,   console ttyFIQ0
```

| | vendor | mainline |
|---|---|---|
| `boot-*.img` | `boot-6.1.99.img` | `boot-6.19.0.img` |
| `console=` nel manifest | `ttyFIQ0` | `ttyS0` |
| `/etc/issue` a boot | `Luckfox Lyra Plus (RK3506G2) - initramfs bring-up` | `... - mainline 6.19 initramfs bring-up` |

### Immagine unica (consigliato)

```bash
cd output/images
sudo rkdeveloptool db MiniLoaderAll.bin      # carica il loader in SRAM
sudo rkdeveloptool uf update.img             # scrive tutto
sudo rkdeveloptool rd                        # reset
```

Le varianti initramfs (vendor e mainline) **non producono `update.img`** se
`afptool`/`rkImageMaker` non sono disponibili, e non hanno comunque un
`rootfs.img` da scrivere: il rootfs e' dentro `boot.img`. Per quelle si usa il
flash per partizione qui sotto, che e' anche il piu' rapido da iterare.

#### Variante initramfs, mainline o vendor

```bash
cd output/images
sudo rkdeveloptool db MiniLoaderAll.bin
sudo rkdeveloptool gpt parameter.txt
sudo rkdeveloptool wl 0x2000 uboot.img       # @ 4 MiB
sudo rkdeveloptool wl 0x4000 boot.img        # @ 8 MiB  <- kernel + DTB + rootfs
sudo rkdeveloptool rd
```

Poi la seriale a **1500000**: `ttyS0` per il mainline, `ttyFIQ0` per il
vendor. La partizione `rootfs` non viene toccata, quindi passare da un
percorso all'altro e' questione dei soli due `wl`.

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
| Device sul target | `ttyFIQ0` (kernel vendor) / `ttyS0` (kernel mainline) |
| UART SoC | UART0, base `0xff0a0000` — la stessa nei due casi |
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

Con `lyra_plus_mainline_initramfs_defconfig` il fiq-debugger non c'e':
`CONFIG_FIQ_DEBUGGER` e' codice vendor, mai mandato upstream. La stessa UART0
e' guidata dal driver `8250-dw` standard e si chiama **`ttyS0`**. Cambia il
nome, non il cavo ne' il baudrate. La cmdline e' cablata nel kernel
(`external/board/lyra-plus/linux-mainline.config`):

```
earlycon=uart8250,mmio32,0xff0a0000 console=ttyS0,1500000 clk_ignore_unused rootwait
```

`earlycon` stampa prima che il driver 8250 abbia fatto probe, quindi prima che
servano clock e pinctrl: se non escono nemmeno quelle righe, il problema e'
prima del kernel. `CONFIG_CMDLINE_FORCE=y` ignora quello che passa U-Boot, cosi'
in bring-up la cmdline non e' fra i sospetti.

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
