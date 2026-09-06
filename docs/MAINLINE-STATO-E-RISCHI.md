# Mainline 7.2: stato e rischi

Valutazione del percorso kernel **mainline**, scritta per rispondere a una
domanda operativa: *si può usare al posto del percorso vendor 6.1, e cosa si
accetta facendolo?*

Non è il diario del porting — quello, con il *perché* di ogni decisione, sta in
[SCELTE-DI-PROGETTO.md](SCELTE-DI-PROGETTO.md). Qui c'è lo stato misurato, le
assenze note con il loro costo, e i rischi in ordine di quanto pesano.

Rilevata il **2026-09-03** sul pin di allora (mainline 6.19), **aggiornata il
2026-09-06** dopo il passaggio a **7.2.3**: branch `feature/kernel-6.19` del
framework, kernel `rk3506-kernel-upstream.git` branch `rk3506-lyra-plus-7.2` @
`d5ef611a`. Ogni numero qui sotto ha il comando che lo produce; sono in
[Appendice: come rifare le misure](#appendice-come-rifare-le-misure).

---

## Sommario

| | |
|---|---|
| **Sostituire il percorso vendor?** | No. Il branch è costruito per stare *accanto*, e i DTB dei due kernel non sono interscambiabili: avere sempre l'altro percorso funzionante è il paracadute. |
| **Portare il branch in `master`?** | Sì. Zero righe cambiate nei defconfig vendor; le modifiche agli script condivisi sono generalizzazioni che il percorso vendor esercita comunque. |
| **Base per una board dedicata?** | Sì, ed è la scelta migliore dei due — vedi [Perché su una board propria conviene](#perché-su-una-board-propria-conviene). |
| **Rischio numero uno** | **Nessuna LTS contiene RK3506.** Il supporto è entrato in `v6.19-rc1`, una merge window *dopo* la LTS 6.18: fino alla LTS di fine 2026 si sta per forza su una serie a vita breve. Vedi [rischio 1](#1-nessuna-lts-contiene-rk3506). |
| **Il rischio che tace** | Il layout partizioni duplicato in tre posti, con la dimensione rootfs in byte. Vedi [rischio 4](#4-il-layout-partizioni-è-scritto-in-tre-posti-e-nessuno-li-confronta). |

---

## 1. Stato attuale

### Cosa aggiunge il branch

30 commit sopra `master`, e **nessuna modifica al percorso vendor**:
`lyra_plus_defconfig` e `lyra_plus_initramfs_defconfig` sono bit-identici a
`master`.

| | |
|---|---|
| 2 defconfig | `lyra_plus_mainline_defconfig`, `lyra_plus_mainline_initramfs_defconfig` |
| 2 fragment kernel | `linux-mainline.config` (631 righe), `linux-mainline-flash.config` |
| 1 host package | `rk-resource-tool` — 1575 righe di C vendorizzato, serve a `resource.img` |
| generalizzazioni | `post-image.sh` (manifest, `boot-<release>.img`, verifica dimensioni partizioni), `post-build.sh`, `S45adb`, `S99hello`: nessuno cabla più `ttyFIQ0` |
| 1028 righe di docs | le sezioni mainline di `SCELTE-DI-PROGETTO.md` |

### Il fork del kernel: la forma della storia conta

Questa è la parte che pesa più dei defconfig, e la sua forma non è quella che
sembra.

`rk3506-kernel-upstream.git`, branch **`rk3506-lyra-plus-7.2`**: **19 commit
in totale**. Il commit radice `fed9dc990570` — *"Linux 7.2.3 (upstream tree
snapshot)"* — è **senza parent**, e il suo tree è identico bit per bit a quello
del tag `v7.2.3` reale. Stessa forma del branch 6.19 che l'ha preceduto
(radice `e7711d802e8e`, *"Linux 6.19 (upstream tree snapshot)"*, tree
`41c647acd5b4` uguale a `v6.19`), e la scelta è deliberata.

Contenuto uguale, genealogia assente:

```
$ git merge-base v7.2.3 rk3506-lyra-plus-7.2          # nessun output
$ git merge-base --is-ancestor v7.2.3 rk3506-lyra-plus-7.2 && echo YES || echo NO
NO
$ git rev-parse fed9dc990570^{tree} v7.2.3^{tree}     # due SHA identici
```

**Perché appiattito e non ancorato al tag vero — misurato, non teorico.** Nel
salto del 2026-09-06 il primo tentativo è stato `git rebase --onto v7.2.3 …`
sul tag reale, quello con tutta la storia di Linus dietro. Il branch è passato
da 19 commit a **1 465 336**, e il push su GitHub è morto dopo aver compresso
1 847 423 oggetti e averne annunciati **11 694 909** da scrivere:

```
Compressing objects: 100% (1847423/1847423), done.
Writing objects:   0% (1/11694909)
fatal: the remote end hung up unexpectedly
```

Il repo pubblicato **deve** restare uno snapshot appiattito. La forma corretta
per il prossimo salto è quindi creare la nuova radice dal *tree* del tag e
riapplicarci sopra i 18 commit — non rebasare sul tag:

```sh
# i tag upstream non sono nel nostro remote: vedi rischio 2
ROOT=$(git commit-tree "v<nuova>^{tree}" -m "Linux <nuova> (upstream tree snapshot)")
git switch -c rk3506-lyra-plus-<nuova> rk3506-lyra-plus-7.2
git rebase --onto $ROOT fed9dc990570 rk3506-lyra-plus-<nuova>
```

**Conseguenza sui conteggi, che resta valida.** Senza merge-base con il tag,
`v7.2.3..HEAD` **non conta i commit sopra la 7.2.3**: restituisce l'intero
branch, radice compresa. Il conteggio va fatto dalla radice,
`fed9dc990570..HEAD` → 18. Lo stesso valeva su 6.19 con `e7711d802e8e..HEAD`.

**Attenzione a dove si misura `kernel.release`.** In un worktree git del repo
kernel viene `7.2.3-gd5ef611ad074`: `scripts/setlocalversion` non trova tag
raggiungibili — la radice e' senza parent — e ripiega sulla forma `-g<sha>`.
Ma Buildroot **non** compila da un checkout git: estrae il tarball
`linux-<sha>-git4.tar.gz`, che non ha `.git`, quindi `setlocalversion` non
aggiunge niente e la release e' **`7.2.3` nuda**. E' quella che finisce in
`uname -r`, nel manifest e nel nome `boot-7.2.3.img`. Valeva identico su 6.19,
dove la build dava `6.19.0` e non `6.19.0-g8bcfc17861dc`.

Il vecchio branch `rk3506-lyra-plus` resta su GitHub congelato su 6.19, perché
le misure citate in questi documenti restino riproducibili. Un
`rk3506-lyra-plus-7.2-fullhistory` con la storia vera esiste **solo in
locale**, come il suo omologo 6.19. Vedi
[rischio 2](#2-il-repo-kernel-pubblicato-non-è-rebasabile).

I 18 commit sopra la radice, per provenienza:

| provenienza | commit | cosa tocca |
|---|---|---|
| **Ye Zhang \<ye.zhang@rock-chips.com\>**, 2025-12-27 | 7 | tutto il codice C: `pinctrl-rockchip.c`, `pinctrl-rockchip.h`, `gpio-rockchip.c`, i binding, i dtsi pinctrl/rmio generati (rk3506 e rv1126b) |
| **nostri** | 11 | solo DTS/DTSI e `arch/arm/configs/rk3506_minimal.config` |

**La regola "zero patch nostre al codice C" è rispettata.** I sette di Rockchip
sono la serie [PATCH v4 0/7] cherry-pickata, e uno di essi
(`gpio: rockchip: support new version GPIO`) porta già
`Acked-by: Bartosz Golaszewski`, il maintainer di gpio — ma **non contarli come
base in arrivo**: sono fermi in review da febbraio 2026, vedi
[rischio 3](#3-la-serie-rockchip-è-ferma-non-in-volo). Vanno riportati a ogni
salto di versione.

> **Nota sui numeri.** `SCELTE-DI-PROGETTO.md` citava *17 commit sopra il tag
> `v6.19`*, con una tabella 7 + 9. Erano sbagliati per due motivi: due commit
> USB sono arrivati dopo, e soprattutto `git log v6.19..HEAD` **non misura
> quello che sembra** su un branch senza merge-base con il tag — restituisce
> l'intero branch, radice compresa. Quel documento è stato corretto insieme a
> questo. L'insidia **vale identica** sul branch 7.2: la forma appiattita è
> deliberata, non un residuo.

### Cosa di RK3506 è già in `v7.2.3` upstream

Verificato con `git grep` sul tag, non per deduzione:

| dove | cosa |
|---|---|
| `drivers/clk/rockchip/clk-rk3506.c`, `rst-rk3506.c` | CRU e reset controller |
| `drivers/pinctrl/pinctrl-rockchip.c` | pinctrl (+ i 7 commit in volo per l'RMIO) |
| `drivers/net/ethernet/stmicro/stmmac/dwmac-rk.c` | `rk3506_ops`, compatible `rockchip,rk3506-gmac` |
| `drivers/phy/rockchip/phy-rockchip-inno-dsidphy.c` | DSI D-PHY |
| `drivers/gpu/drm/rockchip/rockchip_vop_reg.{c,h}`, `dw-mipi-dsi-rockchip.c` | **VOP e MIPI-DSI — arrivati in `v7.0-rc1`, non c'erano in 6.19** (`ec27500c8f2b`, *"drm/rockchip: vop: Add support for rk3506"*) |
| `include/dt-bindings/{clock,reset}/rockchip,rk3506-cru.h` | ID di clock e reset |
| solo binding, driver generico | `i2c-rk3x`, `spi-rockchip`, `rockchip-dw-mshc`, `rockchip-saradc`, `snps,dw-wdt`, `snps-dw-apb-uart` |

**Non c'è affatto**: audio, USB2 PHY, TSADC/thermal, OTP, flexbus/DSMC, RGA,
AMP. (Su 6.19 in questa riga c'era anche VOP/display: è la voce che il salto a
7.2.3 ha portato in casa.)

La distinzione fra le ultime due righe è quella che decide il costo di ogni
periferica: *binding upstream + driver generico* significa **lavoro di DTS**;
*assente* significa porting di un driver.

### Cosa funziona oggi, misurato

Boot completo, console `ttyS0` a 1500000, rootfs UBIFS sulla SPI NAND, `adb`
via USB, `pstore`/ramoops.

```
spi-nand spi0.0: Winbond SPI NAND was found.
3 cmdlinepart partitions found on MTD device spi0.0
ubi0: attached mtd2 (name "rootfs", size 224 MiB)
VFS: Mounted root (ubifs filesystem) on device 0:13.
dwc2 ff740000.usb: new device is high-speed
S45adb: gadget ADB attivo su ff740000.usb (0x2207:0x0006)
```

Dimensioni, con il limite che conta:

| artefatto | misura | limite |
|---|---|---|
| `zImage` | 5.68 MiB | — |
| `boot.img` | **5.70 MiB** | 12 MiB (partizione `boot`) → **6.3 MiB di margine** |
| `rootfs.ubi` | 8.62 MiB | 223.4 MiB |

Il margine sul `boot.img` è la cifra da tenere d'occhio prima di accendere
sottosistemi: è quello che rende le voci della sezione seguente economiche.

---

## 2. Le due assenze note

### Il LED — una riga di config, un nodo di DTS

Il vendor lo dichiara in `rk3506-luckfox-lyra.dtsi:76-82`:

```dts
leds: leds {
	compatible = "gpio-leds";
	work_led: work-led {
		gpios = <&gpio1 RK_PA0 GPIO_ACTIVE_HIGH>;
		linux,default-trigger = "heartbeat";
	};
};
```

`gpio1` **è già** nel dtsi minimale. Lato config non serve aggiungere niente:
basta **togliere** la riga 382 di `linux-mainline.config`

```
# CONFIG_NEW_LEDS is not set
```

perché `multi_v7_defconfig` porta già `NEW_LEDS`, `LEDS_CLASS`, `LEDS_GPIO`,
`LEDS_TRIGGERS` e `LEDS_TRIGGER_HEARTBEAT` tutti a `=y` (righe 969-989). Il
fragment li stava spegnendo di proposito, come tutto il resto fuori scope per
una console.

Costo: mezz'ora, margine `boot.img` intatto.

### L'Ethernet — **DTS puro, zero Kconfig**

Questo è il risultato controintuitivo della ricognizione. Il `.config`
effettivamente prodotto oggi contiene già:

```
CONFIG_STMMAC_ETH=y
CONFIG_DWMAC_ROCKCHIP=y
CONFIG_PHYLIB=y
CONFIG_NETDEVICES=y
CONFIG_ETHERNET=y
```

Sono rientrati da `multi_v7` quando la sezione 7/7 del fragment ha riacceso
`CONFIG_NET` — che serviva ad `adbd`, non alla rete. Effetto collaterale
gratuito: **il driver c'è già nel kernel che stai costruendo.**

E tutto il resto esiste upstream, verificato uno per uno:

| serve | c'è |
|---|---|
| compatible | `rockchip,rk3506-gmac` → `rk3506_ops`, con `regs = { 0xff4c8000, 0xff4d0000 }` |
| binding | `rockchip-dwmac.yaml` ha un ramo dedicato a rk3506: **4 clock invece di 5**, che è esattamente quanti ne dichiara il nodo vendor |
| clock ID | `CLK_MAC1` 176, `CLK_MAC1_PTP` 202, `PCLK_MAC1` 173, `ACLK_MAC1` 171 |
| reset ID | `SRST_A_MAC1` 130 |
| pin group | `eth_rmii1_miim_pins`, `eth_rmii1_tx_bus2_pins`, `eth_rmii1_rx_bus2_pins`, `eth_rmii1_clk_pins` — in `rk3506-pinctrl.dtsi`, dai commit Ye Zhang |

Il lavoro è trascrivere il nodo `gmac1` da `rk3506.dtsi:133-182` del kernel
vendor nel dtsi minimale, e il blocco `&gmac1` / `&mdio1` da
`rk3506g-luckfox-lyra-plus.dts:41-61` nel DTS di board.

> **Dove metterlo, sapendo che la board finale non è una Lyra Plus.** Il nodo
> `gmac1` (indirizzi, clock, reset, code MTL) descrive **il SoC**: va nel
> dtsi. `phy-mode`, `clock_in_out`, `snps,reset-gpio`, `pinctrl-0` e il nodo
> `phy@1` sotto `mdio1` descrivono **la board**: vanno nel DTS. Se il PHY o i
> pin RMII cambieranno sul disegno dedicato, con questa divisione si riscrive
> un file e non due.

### Il resto, per costo

| periferica | costo | perché |
|---|---|---|
| i2c, spi, sdmmc, saradc, watchdog | **DTS** | binding upstream, driver generico |
| display (VOP, DSI) | porting driver | il D-PHY c'è, il VOP no |
| audio, TSADC/thermal, OTP, flexbus, RGA, AMP | porting driver | nessuna traccia in mainline |
| USB2 PHY | porting non banale | mainline accede ai registri solo via regmap del GRF, il driver vendor scrive anche nei registri interni del PHY |

---

## 3. I rischi

### 1. Nessuna LTS contiene RK3506

**Com'era.** Il pin stava su **6.19.0**, al tag nudo (`SUBLEVEL = 0`), quindi
senza nemmeno i fix stable di `6.19.y`. Ma 6.19 **non è una LTS**: è uscita il
2026-02-08 ed è andata **EOL il 2026-04-22** con `v6.19.14`. Il percorso
mainline stava quindi su una base *morta*, mentre la serie 6.1 del vendor è
ancora `longterm` viva (6.1.187, EOL Dec 2027) — l'esatto contrario della
ragione per cui il percorso era nato.

**Il fatto scomodo, verificato.** Non esisteva una LTS su cui atterrare. Il
supporto RK3506 (CRU `clk-rk3506.c` `18191dd750e6`, pinctrl `dbd2317d7b9f`) è
entrato in **`v6.19-rc1`**, cioè una merge window **dopo** la LTS 6.18. In
`v6.18` non c'è una riga di RK3506: nessun `clk-rk3506.c`, nessun dt-binding,
nessun `rk3506_pin_ctrl`. Tornare all'ultima LTS avrebbe dato una board che non
parte.

| serie longterm (kernel.org, 2026-09-06) | EOL proiettata | RK3506? |
|---|---|---|
| 6.18 | Dec 2028 | ❌ |
| 6.12 | Dec 2028 | ❌ |
| 6.6 | Dec 2027 | ❌ |
| 6.1 | Dec 2027 | ❌ (il vendor lo aggiunge con patch proprie) |
| 5.15, 5.10 | Dec 2026 | ❌ |

**Cosa si è deciso, il 2026-09-06.** Pin su **`v7.2.3`**, la stable in corso
(7.2 rilasciata 2026-08-16, 7.2.3 del 2026-09-02), **non** una LTS. Il salto è
costato un conflitto di una riga; il DTB prodotto è **bit-identico** a quello
di 6.19 (`md5 112851456441f34951623efca9824efa`), quindi la board vede
esattamente lo stesso device tree. In più sono arrivati VOP e MIPI-DSI.

**Il rischio residuo, che resta scritto.** 7.2 andrà EOL quando esce 7.3
(`7.3-rc1` è del 2026-08-30). Il piano è a due salti: `v7.2.3` ora, `v7.3.x`
quando esce, poi **la LTS di fine 2026** — che sarà la prima LTS in assoluto a
contenere RK3506. Ogni salto costa quanto quello appena misurato. **La
designazione della prossima LTS non è determinata**: kernel.org non la annuncia
in anticipo; è *plausibile*, non verificato, che cada sull'ultima release del
2026, come fu per 6.18.

Fonti: <https://www.kernel.org/>,
<https://www.kernel.org/category/releases.html>, consultate il 2026-09-06.

---

### 2. Il repo kernel pubblicato non è rebasabile

**Cos'è.** `git ls-remote --heads origin` su `rk3506-kernel-upstream`
restituisce solo i nostri branch — `rk3506-lyra-plus` (congelato su 6.19) e
`rk3506-lyra-plus-7.2`. Il branch `rk3506-lyra-plus-fullhistory` (1.414.441
commit) e i tag upstream esistono **solo sulla macchina di sviluppo**, non sono
pushati.

**Il passaggio a 7.2.3 non lo ha risolto, e ha mostrato che non si risolve
pushando il branch ancorato al tag**: quella forma pesa 1,4 M commit e GitHub
chiude la connessione (vedi
[Il fork del kernel](#il-fork-del-kernel-la-forma-della-storia-conta)). Da un
clone fresco servono comunque un remote `torvalds` (più `stable` per i tag
`x.y.z`) e un fetch dei tag, perché quei tag **non sono nel nostro remote**.

**Come si manifesta.** Da un clone fresco — la macchina di un collega, la CI,
la propria fra due anni — il rebase descritto in
[Il fork del kernel](#il-fork-del-kernel-la-forma-della-storia-conta) non è
eseguibile: `v7.3` non è un oggetto che quel repo conosce, e non c'è storia
condivisa con l'albero di Linus da cui recuperarlo. Il recupero è un
`git remote add torvalds …` più un fetch dei tag — un'ora di download.

**Bus factor: uno.**

**Cosa fare.** Documentare nel `README` del repo kernel i due comandi che
servono (`git remote add torvalds …` / `git fetch torvalds --tags`, più
`stable/linux.git` per i tag `x.y.z`), oppure pushare direttamente i tag. Mezz'ora
adesso contro un pomeriggio perso da chiunque provi il bump.

---

### 3. La serie Rockchip è ferma, non "in volo"

**Cos'è.** `Acked-by` del maintainer gpio su uno dei sette è un buon segno, ma
va pesato con il resto. Verificato il **2026-09-06** su `torvalds/master` a
7.3-rc2: **nessuno dei sette è upstream**, e non esistono nemmeno i file che
aggiungono — `rk3506-pinctrl.dtsi`, `rk3506-pinctrl-rmio.dtsi`,
`rv1126b-pinctrl.dtsi`; zero occorrenze di `rmio` e `rv1126b` in
`pinctrl-rockchip.c`, in `v6.19`, `v7.0`, `v7.1`, `v7.2`, `v7.3-rc1` e in
`master`.

Sull'archivio `linux-rockchip` l'ultima revisione è la
[**[PATCH v4 0/7]** del 2025-12-27](https://lore.kernel.org/linux-rockchip/20251227114957.3287944-1-ye.zhang@rock-chips.com/),
quella che abbiamo. **Nessuna v5 è mai stata inviata**, e l'ultimo messaggio
del thread è del **2026-02-08**. È ferma su due obiezioni di *progettazione*,
non su dettagli di stile:

- **Linus Walleij** rifiuta la proprietà custom `rockchip,rmio-pins` e pretende
  lo standard `pinmux = <>`
  ([`CAD++jL=fri43Q...`](https://lore.kernel.org/linux-rockchip/CAD++jL=fri43Q1XbMJoOUeoWJw9RwMDJLjcjO8zSbyHb7z+Dzg@mail.gmail.com/)):
  *"No custom invented properties please."*
- **Krzysztof Kozlowski** boccia le 25 162 righe di `rk3506-pinctrl-rmio.dtsi`
  generato
  ([`b9e275cf...`](https://lore.kernel.org/linux-rockchip/b9e275cf-7c16-47cf-9699-82bc79aa7f90@kernel.org/)):
  *"This is review and maintenance nightmare. […] Upstream is not your SDK."*
  Ye Zhang risponde che in tal caso lo lasceranno cadere.

**Come si manifesta.** I sette commit vanno riportati a **ogni** salto di
versione, finché la serie non riparte — non spariranno per assorbimento a
breve. Nel rebase su 7.2.3 hanno prodotto l'unico conflitto (una riga di
`else if` in `pinctrl-rockchip.c`, dove upstream aveva aggiunto `RV1103B`
accanto a dove il patch aggiunge `RV1126B`).

**La buona notizia.** Il rischio sul **nostro** DTS è circoscritto: tutti i
gruppi che usiamo — `uart0_xfer_pins`, `fspi_clk_pins`, `fspi_csn_pins`,
`fspi_bus4_pins` e i futuri `eth_rmii1_{miim,tx_bus2,rx_bus2,clk}_pins` —
stanno in `rk3506-pinctrl.dtsi` (1 795 righe, `rockchip,pins` classico),
**non** nel file RMIO contestato. `rk3506.dtsi:369` include quest'ultimo ma non
ne usa nulla: se muore upstream, si toglie una riga di `#include`. Nessun
rinominamento di gruppo è in discussione nel thread.

**Cosa fare.** Niente in anticipo. Tenere i link qui sopra accanto ai
cherry-pick e ricontrollare il thread a ogni bump.

---

### 4. Il layout partizioni è scritto in tre posti, e nessuno li confronta

**Cos'è.** Lo stesso layout vive in tre forme diverse:

| dove | forma |
|---|---|
| `parameter.txt` | settori, `mtd-id` vuoto, rootfs `-@0x00010000` (grow) |
| `linux-mainline.config:160` | byte, `mtd-id` `spi0.0`, rootfs `0xdf60000@0x2000000` |
| `linux-mainline-flash.config` | idem, stringa `CONFIG_CMDLINE` intera duplicata |

La duplicazione non è evitabile a costo zero: su mainline il `mtdparts`
generato da U-Boot viene **scartato in silenzio**, perché usa `mtd-id`
`spi-nand0` — nome che esiste solo grazie a una patch locale Rockchip — mentre
su mainline il device MTD si chiama `spi0.0`, e `cmdlinepart` pretende
corrispondenza esatta. La ricostruzione completa è in
[SCELTE-DI-PROGETTO.md](SCELTE-DI-PROGETTO.md), sezione *La SPI NAND su
mainline, e l'`mtd-id` che nessuno fa combaciare*.

**Come si manifesta, e perché è il rischio che tace.** La dimensione del
rootfs è **hard-coded in byte**. Il percorso vendor usa `-` e cresce da sé;
questo no. Montando una NAND diversa da 256 MiB sulla board dedicata, il
percorso mainline **non se ne accorge**: attacca UBI a una regione che non
combacia con il chip e va in panic, o monta una geometria sbagliata. Non
esiste un controllo, in nessuno dei tre file, che confronti il layout con la
flash trovata.

È l'unica voce della lista che sbaglia senza dirlo, ed è quella che tocca
direttamente il *"quando avrò il mio device"*.

**Cosa fare, prima del silicio proprio.** Una delle due:

- un generatore unico che produca i due fragment da `parameter.txt` (una
  ventina di righe di Python in `post-image.sh`, che già fa il parsing di
  `parameter.txt` per la verifica dimensioni);
- portare la patch `mtd->name = "spi-nand0"` sul kernel mainline e passare a
  `CONFIG_CMDLINE_EXTEND`, lasciando il layout a U-Boot. Costo: una patch al
  codice C, cioè rompere la regola "zero patch". Upstream non ha motivo di
  accettarla.

La prima è coerente con le scelte già prese in questo albero.

---

### 5. `CONFIG_CMDLINE_FORCE=y`, e perché rilassarlo non fa quello che sembra

**Cos'è.** `linux-mainline.config` imposta `CONFIG_CMDLINE` +
`CONFIG_CMDLINE_FORCE=y`: qualunque cosa U-Boot metta in `/chosen/bootargs`
viene scartata. È la conseguenza necessaria del [punto 4](#4-il-layout-partizioni-è-scritto-in-tre-posti-e-nessuno-li-confronta)
— serve la *nostra* `mtdparts` — ma il prezzo va contato a parte, e il commento
del fragment che invitava a rilassarlo *"a prompt ottenuto"* era sbagliato in
entrambe le direzioni che suggeriva. È stato corretto insieme a questo
documento.

#### La meccanica esatta, dal codice

Il merge sta tutto in `drivers/of/fdt.c:1113-1134`,
`early_init_dt_scan_chosen()`. Prima `bootargs` del DT finisce in `cmdline`,
poi:

| opzione | codice | risultato |
|---|---|---|
| `CMDLINE_EXTEND` | `strlcat(cmdline," "); strlcat(cmdline, CONFIG_CMDLINE)` | bootargs di U-Boot **davanti**, la nostra stringa **appesa in coda** |
| `CMDLINE_FORCE` | `strscpy(cmdline, CONFIG_CMDLINE)` | solo la nostra |
| nessuna delle due (`FROM_BOOTLOADER`) | `if (!cmdline[0]) strscpy(cmdline, CONFIG_CMDLINE)` | la nostra **solo se** i bootargs sono vuoti |

Le due cose da sapere prima di toccare quel simbolo sono in queste tre righe.

#### Trappola 1: togliere `CMDLINE_FORCE` uccide il boot

`FROM_BOOTLOADER` usa `CONFIG_CMDLINE` **solo se `bootargs` è vuoto**. Su
questa board non lo è mai, anche con il nostro DTS che non dichiara
`/chosen/bootargs`, perché U-Boot ne fabbrica uno da sé:

`board_fdt_chosen_bootargs()` (`arch/arm/mach-rockchip/board.c:1413-1455`)
compone la stringa e `fdt_chosen()` (`common/fdt_support.c:366-375`) la
**riscrive** in `/chosen/bootargs` del FDT consegnato al kernel. Dentro c'è
`bootargs_add_partition()`, e su questa configurazione ne sopravvive un solo
ramo — `CONFIG_ENVF` e `CONFIG_ENV_PARTITION` non sono accesi, `CONFIG_MTD_BLK`
sì:

```c
#ifdef CONFIG_MTD_BLK
	if (!env_get("mtdparts")) {
		char *mtd_par_info = mtd_part_parse(NULL);
		if (mtd_par_info)
			if (memcmp(env_get("devtype"), "mtd", 3) == 0)
				env_update("bootargs", mtd_par_info);
	}
#endif
```

Quindi i bootargs finali sono **non vuoti e inutili**: contengono la sola
`mtdparts=spi-nand0:…`, con l'`mtd-id` che su mainline non combacia con niente.

Risultato di togliere `CMDLINE_FORCE` senza altro: `CONFIG_CMDLINE` viene
scartata in blocco, e la board parte **senza `console=`, senza `earlycon`,
senza `root=`** — muta, con il sintomo indistinguibile da quello del
[bug di OP-TEE](SCELTE-DI-PROGETTO.md). È la peggiore trappola di questa
lista perché la suggeriva un nostro commento.

#### Trappola 2: `CMDLINE_EXTEND` non restituisce il controllo a U-Boot

Con `EXTEND` la nostra stringa è **in coda**, e quasi tutti i parametri del
kernel sono *last-wins*:

| parametro | dove | semantica |
|---|---|---|
| `mtdparts=` | `cmdlinepart.c:395-401` — `mtdpart_setup()` fa `cmdline = s` | ultimo vince |
| `root=` | `do_mounts.c:63-69` — `strscpy(saved_root_name, line)` | ultimo vince |
| `console=` | `printk.c:2508-2555` — `__add_preferred_console()` fa `preferred_console = i` a ogni aggiunta | tutte registrate, **l'ultima** diventa `/dev/console` |
| `earlycon=` | `earlycon.c:230-248` — `-EALREADY` trattato come successo | **primo** vince |

Cioè: con `EXTEND` **noi vinciamo su tutto quello che dichiariamo**. Un
`setenv bootargs 'root=/dev/…'` dato al prompt viene registrato e poi
sovrascritto dalla nostra riga. Non è "ricominciare a leggere i bootargs da
U-Boot": è aggiungere un prefisso che perde ogni collisione.

`EXTEND` è utile solo per i parametri che **non** dichiariamo — `init=`,
`loglevel=`, `initcall_debug`, `panic=` funzionano. Quelli che dichiariamo
(`earlycon`, `console`, `clk_ignore_unused`, `rootwait`, `mtdparts`, e sul
percorso flash anche `ubi.mtd`, `root`, `rootfstype`, `rw`) restano nostri.

E c'è un parametro che si comporta in modo diverso da tutti: **`ubi.mtd`
accumula**. `ubi_mtd_param_parse()` (`build.c:1471-1516`) scrive in
`mtd_dev_param[mtd_devs]` e incrementa `mtd_devs`; `ubi_init()`
(`build.c:1271`) itera su tutti. Se i bootargs arrivassero a portare un
`ubi.mtd`, il secondo attach dello stesso MTD finisce in
`ubi_attach_mtd_dev()` (`build.c:868-874`):

```
ubi: mtd2 is already attached to ubi0
UBI error: cannot attach mtd2
```

Non fatale — UBI è built-in, il loop fa `continue` — ma l'attach che vince è
il **primo**, cioè quello di U-Boot per indice, non il nostro per nome. Che
capovolge la ragione per cui `linux-mainline-flash.config` usa `ubi.mtd=rootfs`
e non `ubi.mtd=2`.

#### Il vincolo sotto tutti e tre: l'environment non è persistente

Questa è la parte che rende la discussione più semplice di quanto sembri.
`output/build/uboot-*/.config` ha:

```
CONFIG_ENV_IS_NOWHERE=y
# CONFIG_USE_BOOTARGS is not set
```

`env/nowhere.c` marca l'environment `ENV_INVALID` e non registra nessun
`.save`: **`saveenv` non ha dove scrivere.** E senza `CONFIG_USE_BOOTARGS`,
`include/env_default.h:31-33` non compila nemmeno una `bootargs=` di default.

Quindi, *indipendentemente* da `CMDLINE_FORCE`, non esiste modo di cambiare i
bootargs in modo persistente da U-Boot: un `setenv` vive un boot. I posti dove
una cmdline può stare in modo permanente sono tre, e nessuno è l'environment:

1. `CONFIG_CMDLINE` nel fragment → ricompilare il kernel;
2. `/chosen/bootargs` nel DTS → ricompilare il DTB (che sta nel FIT dentro
   `boot.img`, quindi stesso riflash);
3. `CMDLINE:` di `parameter.txt` → **non è una cmdline Linux**: `mtd-id` vuoto e
   size in settori, è il formato per il tool di flash.

**Conseguenza per il prodotto**: gli slot A/B decisi dal bootloader e il
recovery "cambia `root=` e riprova" non sono bloccati da `CMDLINE_FORCE`, sono
bloccati da `ENV_IS_NOWHERE`. Rimuovere `CMDLINE_FORCE` non li sbloccherebbe;
servirebbe prima dare a U-Boot un environment scrivibile (una partizione env,
o `CONFIG_ENVF`), che oggi non c'è e che il layout di `parameter.txt` non
prevede.

#### Cosa si può fare oggi, senza ricompilare niente

U-Boot vendor ha degli hotkey, letti da `gd->console_evt` sulla console
seriale durante il boot (`arch/arm/mach-rockchip/hotkey.c:15-24`). Sono la via
d'uscita reale, e vale la pena conoscerli:

| tasto | effetto |
|---|---|
| **Ctrl-P** | stampa i bootargs assemblati: `## bootargs(u-boot)`, `## parts:`, `## bootargs(merged)`. **È il modo per vedere esattamente cosa U-Boot passerebbe**, prima di decidere se rilassare `CMDLINE_FORCE` |
| **Ctrl-A** | shell U-Boot a `BOOTM_STATE_OS_PREP` (FDT già preparato, kernel non ancora avviato) |
| **Ctrl-L** | shell a `BOOTM_STATE_OS_GO` |
| **Ctrl-T** | `fdt print` |
| **Ctrl-I** | aggiunge `initcall_debug debug` ai bootargs — **inefficace con `CMDLINE_FORCE`**, ed è l'unico hotkey che il nostro simbolo neutralizza |
| Ctrl-B / Ctrl-D / Ctrl-F | bootrom / rockusb download / fastboot |

#### Verdetto sul punto 5

`CMDLINE_FORCE` **va tenuto**. Non è il ripiego di un bring-up: è l'unica
delle tre opzioni che dà una cmdline deterministica su una board dove U-Boot
inietta una `mtdparts` sbagliata e non ha un environment dove salvare una
correzione. Il costo reale è un solo hotkey perso (Ctrl-I), non "il controllo
dei bootargs" — che non c'era comunque.

Se un giorno servisse davvero passare parametri dal bootloader, l'ordine
corretto è: **prima** un environment persistente in U-Boot (nuova partizione
env in `parameter.txt`), **poi** `CMDLINE_EXTEND`, **e** togliere dalla nostra
`CONFIG_CMDLINE` ogni parametro che si vuole poter sovrascrivere — perché in
coda vince sempre lei.

---

### 6. I due defconfig mainline puntano a SHA kernel diversi

**Cos'è.**

| defconfig | SHA | |
|---|---|---|
| `lyra_plus_mainline_defconfig` | `d5ef611a` | con i nodi USB |
| `lyra_plus_mainline_initramfs_defconfig` | `51ec1998` | **2 commit indietro**, senza `usb_otg0` |

**Come si manifesta.** Coerente con la scelta documentata (initramfs =
bring-up dalla sola console, senza adb), ma sono due pin da alzare a ogni bump
e niente li lega. In più ogni SHA distinto è un albero kernel in più in
`output/build/` — oggi ce ne sono tre, e i tarball del kernel sono 720 MB dei
1.1 GB totali di download.

**Cosa fare.** Allinearli, e lasciare che sia solo il fragment a distinguere
le due varianti — che è già il criterio con cui è costruito tutto il resto.
Oppure scrivere nel defconfig initramfs *perché* resta indietro.

---

### 7. Il PHY USB2 non è pilotato da nessuno sotto Linux

**Cos'è.** Il nodo `dwc2` è dichiarato **senza `phys`**, e dwc2 lo accetta
(`platform.c:241-252`): `devm_phy_get(dev, "usb2-phy")` torna `-ENODEV`, il
`switch` lo tratta come caso normale, `hsotg->phy` resta `NULL` e il probe
continua. Poi tutte le chiamate al PHY sono protette:

```c
/* __dwc2_lowlevel_hw_enable, platform.c:116-126 */
	} else {
		ret = phy_init(hsotg->phy);        /* NULL -> no-op */
		if (ret == 0) {
			ret = phy_power_on(hsotg->phy);
```

`dwc2_lowlevel_hw_enable()` è chiamata da `gadget.c:4565`, cioè
`dwc2_hsotg_udc_start()` — **ogni volta che un gadget driver si lega all'UDC**,
che è esattamente quello che fa `S45adb` scrivendo su `.../UDC`. Quindi il
punto in cui il PHY *verrebbe* inizializzato viene attraversato a ogni avvio di
`adbd`, e non fa niente.

#### Perché funziona: due ipotesi, e il test che le separa

Il PHY del RK3506 **è** pilotato — ma da U-Boot, non da Linux.
`output/build/uboot-*/.config` ha `CONFIG_PHY_ROCKCHIP_INNO_USB2=y`, il driver
U-Boot conosce `rockchip,rk3506-usb2phy`
(`drivers/phy/phy-rockchip-inno-usb2.c:2042`) e
`arch/arm/dts/rk3506-u-boot.dtsi:139-152` accende `&usb2phy`, `&u2phy_otg0` e
`&usb20_otg0` con `u-boot,dm-pre-reloc`. E il suo `rk3506_usb2phy_tuning()`
(riga 907) è **byte per byte identico** a quello del kernel vendor.

Ma `u-boot,dm-pre-reloc` rende il nodo *disponibile* presto, non lo **proba**:
in U-Boot un device viene probato al primo uso, e su questa board il boot mode
si decide leggendo un registro (`boot_mode.c:159`), non interrogando il PHY.
Restano quindi due possibilità che dal solo sorgente **non si distinguono**:

| | conseguenza |
|---|---|
| **(a)** su un boot normale qualcosa in U-Boot proba il PHY | Linux eredita un PHY **tarato** (occhio HS a 425 mV). Funziona, ma dipende da U-Boot: un cambio nel suo boot path lo toglie senza preavviso |
| **(b)** nessuno lo proba | il PHY sta ai **default di reset** e enumera lo stesso. Tutta la taratura analogica caratterizzata da Rockchip non è applicata |

**Il test che decide, sull'hardware.** La taratura scrive sei campi in
indirizzi noti. Basta leggerne uno — `0xff2b0000 + 0x30`:

```sh
# da Linux (serve CONFIG_DEVMEM + busybox devmem)
devmem 0xff2b0030 32
# oppure dal prompt U-Boot
=> md.l 0xff2b0030 1
```

- **bit 2 == 0** e **bit [6:4] == 0x5** → tarato, siamo nel caso (a);
- qualsiasi altra cosa → default di reset, caso (b).

Finché quel valore non è stato letto, **quale dei due casi valga è ignoto**, e
la differenza non è cosmetica: nel caso (b) l'occhio HS è a 450 mV invece dei
425 mV che Rockchip ha caratterizzato per questo SoC. Su un cavo corto da banco
non si vede; su una board propria, con un cavo lungo o un hub, è esattamente il
margine che manca. **Questo test va fatto prima di congelare il layout della
scheda dedicata.**

#### Cosa non fa nessuno, in concreto

Dalla tabella `rk3506_phy_cfgs` del driver vendor
(`phy-rockchip-inno-usb2.c:3996`), i registri che sotto Linux non vengono mai
toccati:

| registro | dove | a cosa serve |
|---|---|---|
| `phy_sus` `{0x0060,8,0,…}` | GRF | sospensione/ripresa del PHY. Mai scritto: il PHY resta alimentato sempre |
| `bvalid_det_*` `{0x0150/54/58,2}` | GRF | IRQ di attacco/distacco del cavo |
| `idfall/idrise_det_*` | GRF | OTG ID — **irrilevante qui**: `dr_mode = "peripheral"`, non c'è role switch |
| `ls_det_*`, `disfall/disrise_*` | GRF | linestate e disconnect, sorgenti di wakeup |
| `chg_det` `{cp,dcp,dp}` | GRF | riconoscimento del tipo di caricatore |
| `clkout_ctl_phy` `{0x041c,…}` | **blocco PHY** | gating del clock 480 MHz in uscita dal PHY |
| taratura analogica `0x30/0x430/0x94/0x494` | **blocco PHY** | occhio HS, ricevitore differenziale in suspend, sorgente del linestate |

Il costo pratico oggi è: **PHY sempre alimentato** (consumo, e niente wakeup da
USB) e **nessun charger detection**. Il suspend di sistema non è comunque
disponibile su questa board — vedi
[rischio 8](#8-assenze-che-su-un-prodotto-contano) — quindi le due cose si
annullano finché il suspend non serve.

> **Correzione a una mia affermazione precedente.** Avevo scritto che non c'è
> «nessuna garanzia che il PHY si riprenda da un reset USB». È troppo forte: un
> **bus reset** USB è gestito dentro il core dwc2 (registri del controller), il
> PHY non viene reinizializzato nemmeno quando il driver PHY c'è. Il ri-attacco
> del cavo passa per gli interrupt di sessione del controller via UTMI, non per
> gli IRQ del PHY. Non c'è quindi motivo noto per cui `adb` debba cadere in modo
> non riproducibile: il rischio reale è il margine analogico e il consumo, non
> la stabilità dell'enumerazione.

#### Quanto costa portarlo: meno di quanto dicevo, ma non zero

La parte buona è che **il grosso è davvero una copia di tabella**. Il driver
mainline ha già il gancio giusto: `struct rockchip_usb2phy_cfg` include
`int (*phy_tuning)(...)` (`phy-rockchip-inno-usb2.c:180`), e il
`rockchip_usb2phy_port_cfg` mainline copre quasi tutti i campi che la tabella
rk3506 usa:

| | |
|---|---|
| **già in mainline** | `phy_sus`, `bvalid_det_{en,st,clr}`, `idfall/idrise_det_*`, `ls_det_*`, `disfall/disrise_*`, `utmi_avalid`, `utmi_bvalid`, `utmi_id` (vendor: `utmi_iddig`), `utmi_ls`, `utmi_hstdet`, `chg_det` |
| **estensioni vendor, da lasciare fuori** | `bvalid_grf_sel`, `bvalid_grf_con`, `iddig_output`, `iddig_en`, `vbus_det_en`, `port_ls_filter_con` |

E tutti i registri di quella prima riga stanno **nel GRF** a `0xff288000`, che è
esattamente il modello di mainline.

Quello che non entra è il **blocco di registri proprio del PHY** a
`0xff2b0000`. Mainline non ha modo di raggiungerlo:

- il driver non fa mai `ioremap`: `get_reg_base()` (riga 264) ritorna
  `rphy->usbgrf ?: rphy->grf`, e **entrambi** sono regmap di syscon ottenuti da
  `syscon_node_to_regmap(dev->parent->of_node)` o dal phandle
  `rockchip,usbgrf` (righe 1357-1370);
- il `reg` del nodo non è un indirizzo ma un **offset dentro il GRF padre**. Si
  vede nell'unico esempio recente in albero, `rk3576.dtsi:899-930`:

  ```dts
  usb2phy_grf: syscon@2602e000 {
      compatible = "rockchip,rk3576-usb2phy-grf", "syscon", "simple-mfd";
      reg = <0x0 0x2602e000 0x0 0x4000>;
      u2phy0: usb2-phy@0    { compatible = "rockchip,rk3576-usb2phy"; reg = <0x0 0x10>; };
      u2phy1: usb2-phy@2000 { compatible = "rockchip,rk3576-usb2phy"; reg = <0x2000 0x10>; };
  };
  ```

- e infatti **tutte** le `phy_tuning` in mainline scrivono via
  `regmap_write(rphy->grf, …)` (righe 1509, 1517, 1541). Nessuna tocca un
  blocco PHY.

Il driver vendor invece fa `devm_ioremap_resource()` (riga 2444) e poi
`readl`/`writel` diretti. Le sei scritture della taratura RK3506 sono tutte lì:

```c
phy_clear_bits (rphy->phy_base + 0x30,  BIT(2));            /* rx diff off in suspend */
phy_update_bits(rphy->phy_base + 0x30,  GENMASK(6,4), 0x05 << 4);  /* occhio HS 425 mV */
phy_update_bits(rphy->phy_base + 0x94,  GENMASK(6,3), 0x03 << 3);  /* linestate da TX  */
/* + gli stessi tre a +0x430 / +0x494 per la porta otg1 */
```

Quindi il porting si divide in due pezzi molto diversi:

1. **la tabella GRF** — meccanica, riusa struttura e semantica esistenti, ed è
   la parte che porta suspend del PHY, IRQ di bvalid/linestate/disconnect e
   charger detection. Fattibile come patch normale;
2. **l'accesso al blocco PHY** — una modifica *strutturale* a un driver
   condiviso da 13 SoC e al suo binding, per un modello di indirizzamento che
   mainline oggi non prevede. Va concordata con il maintainer, non decisa da
   noi.

E il punto che rende la cosa meno urgente di quanto sembri: **anche portando
solo il pezzo 1** si otterrebbe tutto il controllo funzionale, lasciando la
taratura analogica dov'è oggi — cioè o a U-Boot, o ai default. Non si
peggiorerebbe niente.

**Cosa fare.**

1. **Prima di tutto, leggere `0xff2b0030` sulla board** e scrivere il risultato
   in [BOARD-FACTS.md](BOARD-FACTS.md): decide se la taratura c'è o no, ed è
   cinque minuti.
2. Se il caso è (b) e la board dedicata avrà un percorso USB non banale (cavo
   lungo, connettore diverso, hub), mettere in conto il pezzo 1 del porting —
   oppure verificare l'occhio HS con uno strumento invece che per deduzione.
3. Nel frattempo tenere la **seriale** come canale primario di lavoro: non
   perché `adb` sia instabile, ma perché è l'unico che non dipende da un
   sottosistema che nessuno sta pilotando.

---

### 8. Assenze che su un prodotto contano

**Cos'è.** Il dtsi minimale dichiara fuori scope, per scelta esplicita:
watchdog, TSADC/thermal, OPP/cpufreq, PMU e regolatori, RTC, DMA, i2c, spi,
mmc, audio, PWM. In più `rockchip,rk3506` non è in `rockchip_board_dt_compat[]`
(`arch/arm/mach-rockchip/rockchip.c:54-63`), quindi la board ripiega su
`GENERIC_DT`, `rockchip_dt_init()` non gira e **`rockchip_suspend_init()`
nemmeno**.

**Come si manifesta.** Nessun watchdog per il recovery in campo. Nessuna
protezione termica. La CPU gira alla frequenza che le ha lasciato il
bootloader. Nessun suspend.

Per un bring-up è irrilevante — ed è il motivo per cui sono fuori. Per un
prodotto è una lista di lavoro da pianificare, non da scoprire. Le prime
cinque (i2c, spi, sdmmc, saradc, watchdog) sono **DTS puro**: binding upstream,
driver generico.

---

### 9. Il pruning delle piattaforme è il costo ricorrente di ogni bump

**Cos'è.** 72 simboli `ARCH_*` e 41 `SOC_*` spenti a mano, perché
`multi_v7_defconfig` accende 76 famiglie di SoC e senza pruning il `boot.img`
è 15.09 MiB contro 12 di partizione.

**Come si manifesta.** Se mainline aggiunge una famiglia di SoC, quella non è
nella lista, rientra, e lo `zImage` ricresce. **Fallisce forte**: la verifica
dimensioni di `post-image.sh` fa abortire la build invece di produrre
un'immagine non flashabile. Mitigazione buona.

Il rischio gemello è invece silenzioso: un simbolo Kconfig che upstream
**rimuove** sparisce senza che `merge_config` dica niente — avvisa solo sui
simboli *ridefiniti*. Il controllo che se ne accorge è rileggere il `.config`
prodotto, non il fragment.

Con 6.3 MiB di margine oggi non è urgente. Il comando per rigenerare le due
liste dai Kconfig del kernel è nel commento del fragment.

---

### 10. I due `boot.img` non sono interscambiabili, e sbagliare non dà errori

**Cos'è.** Gli ID dei clock nei dt-bindings RK3506 sono **rinumerati** fra
vendor 6.1 e mainline: `PCLK_UART0` 113 → 99, `SCLK_UART0` 118 → 104.

**Come si manifesta.** Un DTB vendor su kernel mainline, o viceversa,
**compila, boota e programma i clock sbagliati**: nessun errore, solo una
board muta.

**Mitigazione, già in piedi**: `lyra-manifest.txt`, `boot-<release>.img` come
hard link a `boot.img` (zero byte in più, nome inequivocabile), e `/etc/issue`
che lo dice prima del prompt di login. Resta una procedura umana, e ora le
immagini in giro sono quattro invece di due.

---

## 4. Verdetto

**Non sostituire `master`.** Il branch non lo chiede: è costruito
esplicitamente accanto, con i defconfig vendor intatti come termine di
paragone. È il pregio di design principale di questo lavoro e va conservato —
anche perché il [rischio 10](#10-i-due-bootimg-non-sono-interscambiabili-e-sbagliare-non-dà-errori)
rende preziosissimo avere sempre l'altro percorso funzionante da cui
ripartire.

**Portare il branch in `master`, sì.** Non aggiunge rischio a chi usa il
percorso vendor: zero righe cambiate nei suoi defconfig, e le modifiche a
`post-image.sh`, `S45adb`, `S99hello` sono generalizzazioni — parametrizzano
la console invece di cablarla — che il percorso vendor esercita comunque a
ogni build.

### Perché su una board propria conviene

Il DTS vendor della Lyra Plus eredita `rk3506-luckfox-lyra.dtsi`: ~1300 righe
di pannelli DSI Waveshare, `adc-keys`, backlight, `fiq-debugger`, regolatori
di quella board. Su un disegno dedicato va potato tutto, e potare un file di
terzi è lavoro che non finisce mai.

Il dtsi minimale mainline è invece **un file nostro**: 340 righe, ogni nodo
giustificato in commento, ogni assenza deliberata. Su una board nuova si parte
da lì — non da *lì meno mille righe*. E la regola "zero patch al codice C" è
oggi rispettata davvero, quindi il costo del bump di versione è concentrato nel
fragment, dove si vede.

### Ordine di lavoro

1. ~~**Decidere il pin di versione prima di aggiungere feature.**~~ **Fatto il
   2026-09-06**: pin su `v7.2.3`, con il piano a due salti verso la LTS di fine
   2026. [Rischio 1](#1-nessuna-lts-contiene-rk3506). Il prossimo salto —
   `v7.3.x`, quando esce — va fatto sempre prima di aggiungere feature: oggi i
   commit nostri sono 11, tutti DTS.
2. **Documentare (o pushare) i tag upstream** nel repo kernel, così il bump è
   eseguibile da un clone fresco.
   [Rischio 2](#2-il-repo-kernel-pubblicato-non-è-rebasabile).
3. **LED**: togliere una riga dal fragment, aggiungere il nodo.
   [Dettagli](#il-led--una-riga-di-config-un-nodo-di-dts).
4. **Ethernet**: solo DTS, nessun Kconfig, con la divisione dtsi/dts descritta
   sopra. [Dettagli](#lethernet--dts-puro-zero-kconfig).
5. **Unificare i due SHA kernel** dei defconfig mainline, o scrivere perché
   divergono. [Rischio 6](#6-i-due-defconfig-mainline-puntano-a-sha-kernel-diversi).
6. **Prima del silicio proprio**: risolvere il layout partizioni triplicato.
   [Rischio 4](#4-il-layout-partizioni-è-scritto-in-tre-posti-e-nessuno-li-confronta) —
   l'unico che tace quando sbagli.

---

## Appendice: come rifare le misure

Dal framework:

```sh
# cosa aggiunge il branch
git diff --stat master...HEAD
git log --oneline master..HEAD | wc -l

# i defconfig vendor sono intatti?
git diff master...HEAD -- external/configs/lyra_plus_defconfig \
                          external/configs/lyra_plus_initramfs_defconfig   # vuoto

# dimensioni e margine (dopo una build mainline)
ls -l output/images/{zImage,boot.img,rootfs.ubi}
cat output/images/lyra-manifest.txt

# net ed eth sono gia' accesi nel .config prodotto?
K=$(ls -d output/build/linux-* | grep -v headers | head -1)
grep -E '^CONFIG_(STMMAC_ETH|DWMAC_ROCKCHIP|PHYLIB|NET)=' $K/.config

# cosa spegne il fragment fra LED e rete
grep -nE 'NEW_LEDS|CONFIG_NET' external/board/lyra-plus/linux-mainline.config
```

Dal kernel (`~/git/rk3506-kernel-upstream`):

```sh
# prima di tutto: i tag upstream non sono nel nostro remote (rischio 2)
git remote add torvalds https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git
git fetch torvalds --tags
# per i tag x.y.z serve anche stable/linux.git; se basta un tag solo:
#   git remote add stable https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
#   git fetch stable tag v7.2.3

B=rk3506-lyra-plus-7.2

# la forma della storia: sul branch 7.2 l'ancestry c'e'
git merge-base --is-ancestor v7.2.3 $B && echo "ancestry ok"
git rev-list --count v7.2.3..$B                      # 18
git log --format='%an' v7.2.3..$B | sort | uniq -c   # 7 Ye Zhang + 11 nostri

# ...sul vecchio branch 6.19, congelato, NON c'era: li' si contava dalla radice
git rev-parse e7711d802e8e^{tree} v6.19^{tree}       # due SHA identici
git merge-base --is-ancestor v6.19 rk3506-lyra-plus || echo "nessuna ancestry"
git rev-list --count e7711d802e8e..rk3506-lyra-plus  # 18

# cosa e' upstream in v7.2.3 per rk3506
git grep -l rk3506 v7.2.3 -- drivers include Documentation

# la serie Ye Zhang e' atterrata? (finche' e' vuoto, no)
git grep -c -i rmio v7.2.3 -- drivers/pinctrl/pinctrl-rockchip.c
git cat-file -e torvalds/master:arch/arm/boot/dts/rockchip/rk3506-pinctrl.dtsi \
  2>/dev/null && echo ATTERRATA || echo "ancora fuori"

# gli ID dei clock sono cambiati fra due tag? (se no, nessun rischio silenzioso)
diff <(git show v6.19:include/dt-bindings/clock/rockchip,rk3506-cru.h) \
     <(git show v7.2.3:include/dt-bindings/clock/rockchip,rk3506-cru.h)

# i pezzi che servono all'ethernet
git grep -n 'rk3506-gmac' $B -- drivers Documentation
git grep -nE 'MAC1' $B -- 'include/dt-bindings/clock/rockchip,rk3506-cru.h'
git grep -nE 'SRST_A_MAC1' $B -- 'include/dt-bindings/reset/rockchip,rk3506-cru.h'
git grep -n 'eth_rmii1_' $B -- arch/arm/boot/dts/rockchip/rk3506-pinctrl.dtsi

# cosa pubblica il remote
git ls-remote --heads origin
```
