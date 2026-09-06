# Environment U-Boot persistente e ridondante su SPI NAND

Design approvato il 2026-09-06. Board di destinazione: **Miranda V3**; il
veicolo di bring-up e' la Luckfox Lyra Plus (RK3506G2), 256 MiB SPI NAND,
erase block 128 KiB. I path nell'albero dicono ancora `lyra-plus` perche' la
rinomina e' rimandata all'arrivo della Miranda V3: questo design non la
anticipa.

I fatti su cui questo documento si appoggia stanno in
[BOARD-FACTS.md](../../BOARD-FACTS.md); il *perché* delle scelte, una volta
implementate, va in [SCELTE-DI-PROGETTO.md](../../SCELTE-DI-PROGETTO.md).

---

## Il problema

`output/build/uboot-1625f78b/include/generated/autoconf.h` dice:

```c
#define CONFIG_ENV_SIZE 0x8000
#define CONFIG_ENV_IS_NOWHERE 1
```

Nessun `CONFIG_ENV_OFFSET`, nessun backend. L'ambiente vive solo in RAM e
`saveenv` non persiste. Non è una lacuna legata a un update system: è una
lacuna del bring-up, e pesa su qualunque progetto che nasca da questo
template — MAC address, numero di serie, bootargs modificabili senza
riflashare.

## Ambito

**Dentro:** partizioni MTD dedicate all'env allineate all'erase block; backend
U-Boot persistente *e ridondante* (due copie, perché un power loss durante
`saveenv` non deve lasciare zero copie valide); `parameter.txt` e `mtdparts`
allineati; `fw_printenv`/`fw_setenv` sul target con un `/etc/fw_env.config`
coerente con gli stessi offset.

**Fuori:** `BOOT_ORDER`, contatori di boot, logica A/B, slot multipli, RAUC.
Il template fornisce *un ambiente persistente*; la *policy di boot* la
costruisce il progetto che nasce dal fork.

---

## Fatti accertati, con la fonte

Tutti verificati nell'albero U-Boot già compilato
(`output/build/uboot-1625f78b6dcf9fe401d447da79132b7bc6804538`), non dedotti.

### Backend disponibili in questo vendor tree

`env/Makefile` compila un backend per ogni `CONFIG_ENV_IS_IN_*`. I candidati
concreti sono quattro.

| Backend | Verdetto |
|---|---|
| `ENVF` (Rockchip; **20** defconfig vendor lo usano) | **Insufficiente.** `envf_save()` esporta con `hexport_r(&env_htab, '\0', H_MATCH_KEY \| H_MATCH_IDENT, &res, ..., envf_num, envf_list)` (`env/envf.c:306`): salva **solo** le variabili di una whitelist compile-time, `CONFIG_ENVF_LIST`, default `"blkdevparts mtdparts sys_bootargs app reserved"` (`env/Kconfig:457`). `setenv pippo 1; saveenv` non persisterebbe. |
| `ENV_IS_IN_BLK_DEV` → `env/env_blk.c` | **Scelto.** Env completo (`env_export`/`env_import`), ridondanza ping-pong corretta. |
| `ENV_IS_IN_NAND` → `env/nand.c` | Richiede `nand_info[]` del framework raw NAND. Qui c'è `CONFIG_MTD_SPI_NAND=y` + `CONFIG_MTD_NAND_CORE=y`, non `CONFIG_NAND`. |
| `ENV_IS_IN_UBI` → `env/ubi.c` | `include/environment.h` impone `CONFIG_CMD_UBI` con un `#error`, e vuole UBI attaccata prima del caricamento dell'env. Più superficie, nessun vantaggio qui: l'env non ha bisogno del wear-leveling di UBI su due partizioni da 4 blocchi.

### Perché `env_blk.c` è corretto

- Salva **una copia per volta**, alternata: `copy = (gd->env_valid == ENV_VALID)`,
  e a fine scrittura `gd->env_valid = gd->env_valid == ENV_REDUND ? ENV_VALID : ENV_REDUND`
  (`env/env_blk.c:127-148`). L'altra copia resta intatta per tutta la durata
  della scrittura.
- In lettura legge entrambe e chiama `env_import_redund()`
  (`env/env_blk.c:222`), che confronta i CRC e, se sono validi entrambi,
  decide in base al serial byte con la gestione del wrap `255 → 0`
  (`env/common.c:216-257`).
- Il serial byte lo incrementa `env_export()`:
  `env_out->flags = ++env_flags` (`env/common.c:282`). Non serve toccarlo.

### Due buchi da colmare in U-Boot

1. `config ENV_OFFSET_REDUND` esiste, sotto `if ARCH_ROCKCHIP`, **solo dentro
   il blocco `if ENVF`** (`env/Kconfig:526-534`). Fuori da ENVF non è
   settabile da un fragment Kconfig.
2. `include/environment.h` ha un blocco per `ENV_IS_IN_FLASH`, `_IN_MMC`,
   `_IN_NAND`, `_IN_UBI` che deriva `CONFIG_SYS_REDUNDAND_ENVIRONMENT` da
   `CONFIG_ENV_OFFSET_REDUND`, ma **non ne ha uno per `ENV_IS_IN_BLK_DEV`**.
   Senza quel define, `env_t` non ha il byte `flags`
   (`include/environment.h:165-171`) e `env_import_redund()` non viene
   nemmeno compilato (`env/common.c:214`, guardia
   `#ifdef CONFIG_SYS_REDUNDAND_ENVIRONMENT`): la build fallisce in link.

Entrambi si risolvono con patch minime. Il meccanismo esiste già:
`external/board/lyra-plus/patches/uboot/` contiene quattro patch.

### La scrittura su NAND è già gestita

`drivers/mtd/mtd_blk.c` → `mtd_dwrite()` (riga 567) fa read-modify-write
allineato all'erase block, e `mtd_map_write()` (riga 240) cancella il blocco
prima di scriverlo e **salta i blocchi guasti**. La tabella di rimappatura è
costruita **per partizione** da `mtd_blk_map_table_init()` (riga 43), chiamata
per ogni partizione da `mtd_blk_map_partitions()` (riga 129).

Questo è il fatto che rende compatibili i due lati: `fw_env` su un device di
tipo `MTD_NANDFLASH` usa lo schema `FLAG_INCREMENTAL` — lo stesso serial byte
di `env_export()` — e salta i blocchi guasti entro il numero di settori
dichiarato in `/etc/fw_env.config`. Le due semantiche coincidono **se e solo
se una partizione MTD contiene esattamente una copia**. Da qui la scelta di
due partizioni (D2).

### La tabella partizioni è una GPT

`.config` di U-Boot: `CONFIG_EFI_PARTITION=y`,
`# CONFIG_RKPARM_PARTITION is not set`. E `parameter.txt` dichiara `TYPE: GPT`.
Quindi il percorso è:

```
parameter.txt  --(rkdeveloptool/afptool)-->  GPT sul chip
GPT  --(part_efi)-->  lista partizioni in U-Boot
lista  --(mtd_part_parse, drivers/mtd/mtd_blk.c:381)-->  "mtdparts=..." in bytes
mtdparts  -->  cmdline del kernel  -->  /proc/mtd
```

Due conseguenze:

- una partizione aggiunta a `parameter.txt` si propaga **da sola** fino a
  `/proc/mtd`: non c'è un secondo posto dove dichiararla;
- cambiare `parameter.txt` **riscrive la GPT**, quindi richiede un riflash
  completo. Vedi *Operazione distruttiva*.

`mtd_part_parse()` riserva un erase block all'**ultima** partizione, perché la
GPT di backup sta in coda al chip. È il motivo per cui `rootfs:grow` produce
`0xdf60000` e non 224 MiB tondi (documentato in `README.md:657-665`). Il
design lascia `rootfs` ultima, quindi quel calcolo non cambia.

### Gli indici MTD sono cablati in tre punti

- `ubi.mtd=2` nel bootargs del **DTS del kernel vendor**
  (`docs/BOARD-FACTS.md:81`) — sta nel repo `wdalmut/rk3506-kernel`, non qui,
  ma è patchabile via `external/board/lyra-plus/patches/linux/`;
- `external/board/lyra-plus/linux-mainline-flash.config:53` — `CMDLINE` con
  l'intero `mtdparts` cablato, e `CONFIG_CMDLINE_FORCE`;
- `external/package/hello-lyra/src/main.go:174` — stringa di fallback che
  dichiara `mtd0=uboot mtd1=boot mtd2=rootfs`.

La variante initramfs **non** è fra questi: il suo DTS
(`external/board/lyra-plus/dts/rk3506g-lyra-plus-initramfs.dts:34`) ha
bootargs senza `ubi.mtd=` né `mtdparts=`, per scelta già documentata nel file.

Nemmeno il DTS mainline lo è: il suo nodo `chosen` ha solo `stdout-path`,
nessun `bootargs` (verificato in
`output/build/linux-*/arch/arm/boot/dts/rockchip/rk3506g-luckfox-lyra-plus.dts:14-15`).
Sul percorso mainline la cmdline arriva tutta da `CONFIG_CMDLINE` +
`CONFIG_CMDLINE_FORCE`, che è il punto elencato qui sopra.

---

## Decisioni

### D1 — Backend: `CONFIG_ENV_IS_IN_BLK_DEV`

**Scartato `ENVF`** nonostante sia la strada vendor battuta (20 defconfig):
salva solo una whitelist compile-time, quindi fallisce il criterio di
accettazione 1 per una variabile arbitraria. Allargare `CONFIG_ENVF_LIST` non
risolve: resta una lista chiusa decisa a compile time, cioè l'opposto di "un
ambiente".

**Scartati `ENV_IS_IN_NAND` e `ENV_IS_IN_UBI`** per i motivi in tabella sopra.

Va detto il rischio: **zero defconfig in questo albero usano
`ENV_IS_IN_BLK_DEV`**. È codice vendor poco battuto. Mitigazione: i criteri di
accettazione 1-3 lo esercitano end-to-end su hardware, incluso il caso di CRC
non valido.

### D2 — Due partizioni MTD da 512 KiB, `ENV_SIZE` = un erase block

`env` e `env_r`, 4 erase block ciascuna. L'env occupa esattamente 1 blocco, gli
altri 3 sono riserva per lo skip dei blocchi guasti.

**Perché due partizioni e non una da 1 MiB con due offset interni:** con una
sola partizione, U-Boot rimappa i blocchi guasti sull'intera partizione, quindi
un blocco guasto nella prima metà sposta anche la copia di backup; `fw_env`,
che salta entro il numero di settori della singola copia, no. Divergenza
silenziosa: `fw_setenv` "riesce" ma U-Boot legge altro. Con una partizione per
copia le due semantiche coincidono per costruzione.

**Perché `ENV_SIZE` = `0x20000` e non il default `0x8000`:** l'env occupa un
erase block esatto, senza semantica di scrittura parziale su entrambi i lati.
Costo: 128 KiB × 2 buffer in RAM al caricamento, su un `CONFIG_SYS_MALLOC_LEN`
di 16 MiB.

**Perché 4 blocchi e non 1:** con un solo blocco, il primo blocco che diventa
guasto uccide quella copia per sempre e la ridondanza degrada a copia singola
senza possibilità di riparazione. Sull'esemplare misurato ci sono 2 blocchi
guasti su 1792 (`README.md:647`). Lo spazio costa 1 MiB su un buco di 12.

### D3 — Layout: nel buco a 20 MiB, indici che slittano

Il buco fra 20 e 32 MiB esiste nel `parameter.txt` vendor ed è lì apposta.
Metterci l'env tiene `rootfs` ultima e `grow`, quindi geometria UBI, conteggio
PEB e `MAXLEBCNT=8456` restano intatti.

Il costo è che `rootfs` passa da `mtd2` a `mtd4`. Si paga una volta sola, e la
contropartita è che `ubi.mtd=2` — un indice numerico cablato, cioè una mina
latente — diventa `ubi.mtd=rootfs`, che non si rompe mai più.

**Alternative scartate:**

- *Voci GPT elencate dopo `rootfs`, ma offset fisici a 20 MiB.* Preserverebbe
  gli indici senza patch al DTS, ma `rootfs` perderebbe `grow` (deve essere
  l'ultima voce) e la GPT avrebbe voci non monotone in LBA — accettato dalla
  specifica, ma non verificabile senza provare rkdeveloptool. Inoltre
  `mtd_part_parse()` riserverebbe l'erase block finale a `env_r`, accorciandola.
- *Env in coda al chip, dopo `rootfs`.* Preserverebbe indici e monotonia, ma
  `rootfs` perderebbe `grow`, si accorcerebbe di 1 MiB e andrebbe ricalcolata
  (con il rischio su `MAXLEBCNT` che `README.md:667-671` descrive), e il buco
  di 12 MiB resterebbe sprecato.

### D4 — Fonte unica: `parameter.txt`, con un parser condiviso

Gli offset compaiono in tre posti indipendenti — configurazione di U-Boot,
`parameter.txt`, `/etc/fw_env.config` — e se divergono il sintomo è subdolo.

`parameter.txt` resta la fonte scritta a mano, perché è già il formato del
progetto e già la fonte della GPT. Nasce **un solo parser**,
`external/board/lyra-plus/flash-layout.sh`, e i due consumatori hanno ruoli
diversi:

- `post-build.sh` **genera** `/etc/fw_env.config`. Non è un file da tenere
  allineato: non esiste finché non lo si costruisce.
- `post-image.sh` **verifica** i valori di U-Boot e fa fallire la build se
  divergono.

**Perché U-Boot è verificato e non generato:** Buildroot legge
`BR2_TARGET_UBOOT_CONFIG_FRAGMENT_FILES` prima che qualunque script di questo
repo possa girare. Generare il fragment richiederebbe un hook pre-build
fragile. Una build che muore con un messaggio esplicito ottiene lo stesso
risultato — la divergenza non arriva sulla board — con molto meno macchinario.

**Perché la verifica legge `include/generated/autoconf.h` e non
`uboot.config`:** l'header generato è il valore *effettivo*, e cattura anche
un valore che arrivasse da un default Kconfig o da un board header invece che
dal fragment.

### D5 — Patch ai file core di U-Boot, non al board header

`CONFIG_ENV_OFFSET_REDUND` e `CONFIG_SYS_REDUNDAND_ENVIRONMENT` si potrebbero
definire con una sola patch a `include/configs/evb_rk3506.h`, com'è d'uso in
una quarantina di board upstream. Si è scelto di patchare `env/Kconfig` e
`include/environment.h` perché così **i tre valori numerici restano dentro
`uboot.config`**: visibili nel diff, in un unico posto, e leggibili da chi
legge il fragment. Con la patch al board header il valore `0x1480000` sarebbe
sepolto dentro un file di patch.

Il rischio di rebase è basso: la serie Rockchip di U-Boot è ferma, e il mirror
è a SHA fisso.

### D6 — Le due copie nascono cancellate

Non si pre-seeda l'area con `mkenvimage`. Al primo boot dopo il riflash U-Boot
stampa `*** Error - No Valid Environment Area found`, ricade sul default
environment e prosegue: `env_blk_load()` legge entrambe le copie, entrambe
hanno CRC non valido, `env_import_redund()` chiama `set_default_env("!bad CRC")`
(`env/common.c:230`). Il primo `saveenv` scrive la copia primaria.

È il comportamento corretto e va **documentato come atteso**, altrimenti al
primo boot sembra un guasto. Pre-seedare aggiungerebbe un'immagine `env.img` a
`update.img` e un valore in più da tenere allineato, per evitare un messaggio
di errore benigno che si vede una volta sola.

---

## Layout definitivo

`external/board/lyra-plus/parameter.txt`, riga `CMDLINE` (unità: settori da 512 B):

```
CMDLINE:mtdparts=:0x00002000@0x00002000(uboot),0x00006000@0x00004000(boot),0x00000400@0x0000a000(env),0x00000400@0x0000a400(env_r),-@0x00010000(rootfs:grow)
```

| idx | nome | offset sett. | offset | size sett. | size | stato |
|---|---|---|---|---|---|---|
| — | *loader/IDB* | `0x0` | 0 | `0x2000` | 4 MiB | non dichiarata |
| `mtd0` | `uboot` | `0x2000` | 4 MiB | `0x2000` | 4 MiB | invariata |
| `mtd1` | `boot` | `0x4000` | 8 MiB | `0x6000` | 12 MiB | invariata |
| `mtd2` | `env` | `0xa000` | 20 MiB | `0x400` | 512 KiB | **nuova** |
| `mtd3` | `env_r` | `0xa400` | 20.5 MiB | `0x400` | 512 KiB | **nuova** |
| — | *buco* | `0xa800` | 21 MiB | | 11 MiB | resta |
| `mtd4` | `rootfs` | `0x10000` | 32 MiB | `-` (grow) | 223.375 MiB | **era `mtd2`** |

Occupazione di ciascuna partizione env:

```
mtd2 env    20.0 MiB   [ env ][ risv ][ risv ][ risv ]   4 × 128 KiB
mtd3 env_r  20.5 MiB   [ env ][ risv ][ risv ][ risv ]   4 × 128 KiB
```

Il nome `env_r` sta per *redundant*, coerente con `CONFIG_ENV_OFFSET_REDUND`.

---

## Design per file

### `external/board/lyra-plus/uboot.config`

Oggi è vuoto di proposito. Diventa:

```
# CONFIG_ENV_IS_NOWHERE is not set
CONFIG_ENV_IS_IN_BLK_DEV=y
CONFIG_ENV_SIZE=0x20000
CONFIG_ENV_OFFSET=0x1400000
CONFIG_ENV_OFFSET_REDUND=0x1480000
```

`ENV_IS_NOWHERE` va disattivato esplicitamente perché è una `choice` Kconfig e
Buildroot fonde il fragment con `merge_config.sh`. Il commento esistente sul
perché il file era vuoto va riscritto, non cancellato: la parte su
`CONFIG_SPL_FIT_IMAGE_KB` e sull'AMP resta valida.

`CONFIG_SYS_MMC_ENV_DEV` è già definito a `0` in
`include/configs/evb_rk3506.h:20`; `env_blk.c:39` lo richiede per compilare.

### `external/board/lyra-plus/patches/uboot/0005-...patch`

`env/Kconfig`: sposta `config ENV_OFFSET_REDUND` fuori dal blocco `if ENVF`,
lasciandolo sotto `if ARCH_ROCKCHIP`. I simboli `ENV_NAND_*` e `ENV_NOR_*`
restano dove sono: servono solo a ENVF.

### `external/board/lyra-plus/patches/uboot/0006-...patch`

`include/environment.h`: aggiunge il blocco mancante, nella stessa forma degli
altri backend.

```c
#if defined(CONFIG_ENV_IS_IN_BLK_DEV)
# ifdef CONFIG_ENV_OFFSET_REDUND
#  define CONFIG_SYS_REDUNDAND_ENVIRONMENT
# endif
#endif
```

### La patch al DTS vendor, e come non farla arrivare su mainline

DTS del kernel vendor, `arch/arm/boot/dts/rk3506g-luckfox-lyra-plus.dts`:
bootargs `ubi.mtd=2` → `ubi.mtd=rootfs`.

`BR2_GLOBAL_PATCH_DIR` è condiviso da tutti e quattro i defconfig, e i due
mainline hanno il DTS in un percorso diverso
(`arch/arm/boot/dts/rockchip/rk3506g-luckfox-lyra-plus.dts`, confermato negli
alberi mainline in `output/build/`): una patch messa in
`external/board/lyra-plus/patches/linux/` fallirebbe l'applicazione su
mainline e romperebbe due build su quattro.

La soluzione è nel meccanismo di Buildroot, non in un condizionale.
`pkg-patches-dirs` (`buildroot/package/pkg-utils.mk:166-170`) è:

```make
pkg-patches-dirs = \
	$(foreach dir, $(call pkg-patch-hash-dirs,$(1)),\
		$(wildcard $(if $($(1)_VERSION),\
			$(or $(wildcard $(dir)/$($(1)_VERSION)),$(dir)),\
			$(dir))))
```

Se esiste `<patch-dir>/linux/<LINUX_VERSION>/`, viene usata **quella
sottodirectory al posto** della base. Con `BR2_LINUX_KERNEL_CUSTOM_GIT` la
`VERSION` è lo SHA. Quindi:

```
external/board/lyra-plus/patches/linux/
  README.md                                        <- base, nessuna .patch
  73bca17b67938d649b072408780369f600555263/        <- solo kernel vendor
    0001-arm-dts-rk3506g-luckfox-lyra-plus-ubi-mtd-per-nome.patch
```

Gli alberi mainline hanno uno SHA diverso, non trovano la sottodirectory,
ricadono sulla base e non applicano nulla — che è già la situazione di oggi.

Effetto collaterale voluto: se lo SHA del kernel vendor viene alzato, la
sottodirectory non corrisponde più e la patch smette *silenziosamente* di
applicarsi. Va quindi aggiunto un controllo esplicito — il candidato naturale
è `post-image.sh`, che il DTB ce l'ha già in mano: verificare che il DTB
costruito non contenga `ubi.mtd=2`. Senza quel controllo il bump dello SHA
produrrebbe una board che monta la partizione sbagliata.

Nota di onestà sulla fonte: il testo esatto del bootargs vendor è documentato
in `docs/BOARD-FACTS.md:81` a partire dall'SDK Luckfox
(`$SDK/kernel-6.1/arch/arm/boot/dts/rk3506g-luckfox-lyra-plus.dts` riga 15).
Il kernel vendor non è attualmente costruito in `output/build/`, quindi la
riga esatta nel mirror `wdalmut/rk3506-kernel` allo SHA `73bca17b` va
riletta quando si scrive la patch, non assunta.

### `external/board/lyra-plus/flash-layout.sh` (nuovo)

Un solo parser di `parameter.txt`. Contratto:

- input: percorso di `parameter.txt`;
- per ogni partizione dichiarata nella riga `CMDLINE`, in ordine, espone
  **indice MTD** (posizione, 0-based), **offset in byte**, **size in byte**
  (`-` → vuoto, "grow");
- la conversione settori (512 B) → byte sta qui e solo qui;
- POSIX sh o bash coerente con gli altri script del repo, `bash -n` e
  `shellcheck -S warning` puliti (la CI li esegue su `docs/*.sh` e
  `external/board/*/post-*.sh`: il pattern della CI va esteso per coprirlo).

Sorgibile da `post-build.sh` e da `post-image.sh`.

### `external/board/lyra-plus/post-build.sh`

Genera `$TARGET_DIR/etc/fw_env.config` dai dati di `env` e `env_r`:

```
# Device          Offset  Env.size  Sector size  #sectors
/dev/mtd2         0x0000  0x20000   0x20000      4
/dev/mtd3         0x0000  0x20000   0x20000      4
```

`Env.size` e `Sector size` vengono da `CONFIG_ENV_SIZE` di U-Boot e
dall'erase block; `#sectors` è `size_partizione / erase_block`. L'erase block
(128 KiB) è un fatto della board, non ricavabile da `parameter.txt`: va
dichiarato una volta in `flash-layout.sh` con il riferimento a
`docs/BOARD-FACTS.md`.

Il file va generato solo se `uboot-tools` è nel `.config`; altrimenti si salta
senza errore, così l'aggiunta non è vincolante per un fork che non lo vuole.

### `external/board/lyra-plus/post-image.sh`

1. Sostituisce il blocco python inline che parsa `mtdparts` per il check
   dimensioni: passa a `flash-layout.sh`, così di parser ne resta uno.
2. Aggiunge una verifica nuova, subito dopo la build di U-Boot: legge
   `CONFIG_ENV_OFFSET`, `CONFIG_ENV_OFFSET_REDUND`, `CONFIG_ENV_SIZE` da
   `$UBOOT_DIR/include/generated/autoconf.h` e confronta con `env` / `env_r`.
   `die()` con un messaggio che dice quale dei tre punti diverge e di quanto.
3. Sanità, nello stesso punto: offset allineati a 128 KiB; `ENV_SIZE` non
   maggiore della partizione; `ENV_OFFSET != ENV_OFFSET_REDUND`.
4. Controllo che il DTB costruito non contenga `ubi.mtd=2`, per intercettare
   il caso in cui la patch al DTS vendor abbia smesso di applicarsi (vedi la
   sezione sulla patch al kernel). Il DTB è già in mano allo script alla
   variabile `$DTB`.

Se U-Boot non è configurato con un env persistente (per esempio un fork che
toglie il fragment), la verifica non deve fallire: deve dire che l'env non è
persistente e proseguire.

### `external/configs/*_defconfig` (tutti e quattro)

`BR2_PACKAGE_UBOOT_TOOLS=y`. `BR2_PACKAGE_UBOOT_TOOLS_FWPRINTENV` è già
`default y` (`buildroot/package/uboot-tools/Config.in:92`), quindi non compare
in un defconfig canonico. Dopo la modifica, `make savedefconfig` su tutti e
quattro (criterio 4, verificato dalla CI).

`uboot-tools` è alla 2025.10 (`uboot-tools.mk:7`), indipendente dalla 2017.09
vendor. Il formato dell'env — CRC32 a 32 bit, byte `flags`, coppie
`chiave=valore` NUL-terminate — non è cambiato.

### `external/board/lyra-plus/linux-mainline-flash.config`

`CONFIG_CMDLINE` (riga 53) contiene l'intero `mtdparts` cablato, con
`CONFIG_CMDLINE_FORCE`. Va aggiornato con le due partizioni nuove. Usa già
`ubi.mtd=rootfs`, quindi lo slittamento degli indici non lo tocca.

### `external/package/hello-lyra/src/main.go`

Riga 174: la stringa di fallback dichiara `mtd0=uboot mtd1=boot mtd2=rootfs`.
Va aggiornata. È solo un messaggio, ma è il messaggio che si legge quando
`/proc/mtd` non c'è, cioè esattamente quando ci si sta chiedendo com'è fatta
la flash. Il resto della funzione legge `/proc/mtd` e non cabla nulla.

### `external/board/lyra-plus/genimage.cfg`

Nessuna `partition` da aggiungere: `env` e `env_r` sono cancellate, non hanno
immagine. Cambiano solo i commenti, che oggi elencano gli offset e affermano
che fra 20 e 32 MiB "resta un buco non allocato".

### `docs/check-artifacts.sh`

**Non cambia.** Il suo unico punto sensibile al layout è la riga 183, che
itera sulle voci di `update.img` (`parameter bootloader uboot boot rootfs`), e
`env` non ha immagine. Da riverificare eseguendolo, non da assumere.

### `.github/workflows/checks.yml`

Il job `scripts` esegue `bash -n`, `shellcheck` e il controllo del bit `+x` su
`setup.sh docs/*.sh external/board/*/post-*.sh`. `flash-layout.sh` non
corrisponde a nessuno di quei pattern: il glob va esteso. Il bit `+x` non
serve a un file sorgibile, quindi va escluso dal controllo di eseguibilità o
il file va reso eseguibile per uniformità — decisione da prendere nel piano.

### Documentazione

- `docs/BOARD-FACTS.md`: nuova tabella del layout MTD con la fonte di ogni
  valore, e la nota che gli indici sono slittati.
- `docs/SCELTE-DI-PROGETTO.md`: perché env ridondante e non copia singola;
  perché `ENV_IS_IN_BLK_DEV` e non ENVF; perché due partizioni e non una.
- `README.md`: tabella delle partizioni nell'output atteso (righe 1025-1043),
  e il messaggio `No Valid Environment Area found` atteso al primo boot.

---

## Criteri di accettazione

| # | Criterio | Come si verifica |
|---|---|---|
| 1 | L'env sopravvive al reboot | Da U-Boot: `setenv pippo 1 ; saveenv ; reset ; printenv pippo` |
| 2 | I due lati si vedono | Da Linux `fw_setenv pluto 2 ; reboot`, poi da U-Boot `printenv pluto`. Poi il contrario: `setenv` in U-Boot, `saveenv`, boot, `fw_printenv` |
| 3 | La ridondanza è reale | Le due copie esistono a offset diversi (`cat /proc/mtd`, `hexdump` di `/dev/mtd2` e `/dev/mtd3`). Poi `flash_erase /dev/mtd2 0 1` invalida la primaria, reboot, `printenv pluto` risponde ancora |
| 4 | `make savedefconfig` non produce diff | Job `defconfig` della CI, su tutti e quattro i defconfig |
| 5 | `docs/check-artifacts.sh` passa | Eseguito a mano dopo una build completa |
| 6 | La variante initramfs costruisce e boota | `lyra_plus_initramfs_defconfig` |

Prima di arrivare alla board, la build stessa è un test: se i tre punti
divergono, `post-image.sh` muore.

**Al primo boot dopo il riflash `*** Error - No Valid Environment Area found`
è atteso** (D6), non un guasto.

---

## Operazione distruttiva

Cambiare `parameter.txt` cambia la **GPT** sul chip. Non basta riscrivere una
partizione: serve un riflash completo.

```
rkdeveloptool uf update.img
```

Se dopo il riflash il loader non riparte: MaskROM, poi

```
rkdeveloptool db MiniLoaderAll.bin
rkdeveloptool uf update.img
```

Non ci sono board in campo, quindi il costo è il tempo di un riflash.

---

## Rischi noti

1. **`env_blk.c` è codice vendor poco battuto**: zero defconfig in questo
   albero lo usano. I criteri 1-3 lo esercitano end-to-end; se si rivelasse
   rotto, il ripiego è `ENV_IS_IN_NAND` con una patch che registri il device
   SPI NAND in `nand_info[]` — più invasiva, quindi non è la prima scelta.
2. **La patch al DTS vendor smette di applicarsi in silenzio se lo SHA del
   kernel cambia**, perché è agganciata alla sottodirectory di versione. È il
   prezzo di non romperla su mainline. Mitigazione obbligatoria, non
   facoltativa: il controllo sul DTB costruito descritto sopra. Senza quello,
   un bump dello SHA produce una board che monta la partizione sbagliata
   senza un solo messaggio di errore.
3. **`get_mtd_blk_map_address()` dipende da quando la tabella di rimappatura
   è inizializzata.** Se `mtd_blk_map_partitions()` non è ancora stata
   chiamata al caricamento dell'env, `mtd_map_write()` ricade sullo skip
   lineare a partire dall'offset richiesto — che, partendo dall'inizio di una
   partizione, dà la stessa semantica. Su un chip senza blocchi guasti
   nell'area env i due percorsi sono indistinguibili, quindi il caso va
   provato deliberatamente (criterio 3 con `flash_erase`), non aspettato.
