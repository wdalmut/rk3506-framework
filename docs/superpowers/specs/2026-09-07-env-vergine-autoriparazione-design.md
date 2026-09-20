# L'environment vergine si ripara da solo al primo boot

Design approvato il 2026-09-07. Emenda la **decisione D6** del design del
2026-09-06 ([env persistente e
ridondante](2026-09-06-uboot-env-persistente-design.md)), la cui premessa è
stata falsificata sull'hardware.

Board di destinazione: **Miranda V3**; veicolo di bring-up la Luckfox Lyra
Plus (RK3506G2), 256 MiB SPI NAND, erase block 128 KiB.

---

## Il problema, osservato sulla scheda

Sequenza reale, 2026-09-06, dopo un riflash completo con l'env appena
introdotto:

1. Le partizioni `env` ed `env_r` sono vergini, mai scritte: tutte `0xFF`.
2. Da Linux, `fw_setenv bootdelay 3`. Riesce, con un avviso.
3. Al boot successivo U-Boot arriva al prompt, il countdown parte da 3.
4. Scaduto il countdown la scheda **non parte**: dump dei registri, stack
   unwinder che gira a vuoto, reset in loop.
5. `env default -a -f ; saveenv ; reset` rimette tutto a posto.

### La causa

`fw_setenv`, quando trova un environment con CRC non valido, **non si limita
a rifiutare**: sostituisce l'intero ambiente con il proprio default compilato
e poi ci applica la modifica richiesta
([`tools/env/fw_env.c:1452-1455`](https://source.denx.de/u-boot/u-boot/-/blob/v2025.10/tools/env/fw_env.c)):

```c
if (!crc0_ok) {
        fprintf(stderr, "Warning: Bad CRC, using default environment\n");
        memcpy(single->data, default_environment, sizeof(default_environment));
        environment.dirty = 1;
}
```

Quel `default_environment` è quello di **uboot-tools 2025.10**, non quello
della nostra U-Boot 2017.09 Rockchip. Estratto dal binario installato sul
target:

```
$ strings output/target/usr/sbin/fw_printenv | grep -E '^(bootcmd|bootdelay|baudrate)='
bootcmd=bootp; setenv bootargs root=/dev/nfs nfsroot=${serverip}:${rootpath} ip=${ipaddr}:${serverip}:${gatewayip}:${netmask}:${hostname}::off; bootm
bootdelay=5
baudrate=115200
```

Boot da rete via BOOTP e NFS. Di `boot_android`, `bootrkp` e `boot_fit` —
i comandi su cui si regge il boot di questa piattaforma — zero occorrenze.

Quindi al boot successivo U-Boot trova un CRC **valido**, si fida, importa, e
scaduto il `bootdelay` esegue `bootp` su una scheda senza rete e poi `bootm`
senza nessuna immagine caricata. Salta in memoria a caso: data abort.

### Perché la D6 era sbagliata

La D6 diceva di non pre-seedare l'area env, perché farlo aggiungerebbe
un'immagine a `update.img` e un valore da tenere allineato «per evitare un
messaggio di errore benigno che si vede una volta sola».

Il messaggio è benigno. Lo **stato** non lo è. Un env vergine è una trappola
armata per il primo `fw_setenv`, e la trappola brucia il boot.

Peggio: la procedura di accettazione conteneva essa stessa la trappola. Il
criterio 2 diceva «da Linux: `fw_setenv pluto 2 ; reboot`». Eseguito come
prima scrittura dopo un riflash, produce esattamente il guasto qui sopra.

---

## Decisione: U-Boot ripara l'env quando lo trova non valido

In fondo a `env_blk_load()`, se l'ambiente caricato in memoria è il default
compilato — cioè nessuna delle due copie era usabile — lo si scrive in flash.

Lo stato vergine cessa di esistere al primo boot, **prima che Linux esista**,
quindi prima che qualcuno possa lanciare `fw_setenv`.

### Il rilevatore

`GD_FLG_ENV_DEFAULT` copre entrambi i modi in cui il caricamento può fallire:

| Modo | Percorso |
|---|---|
| Entrambe le copie con CRC non valido | `env_import_redund()` → `set_default_env("!bad CRC")` (`env/common.c:229-231`) |
| Errore di I/O su entrambe le letture | `env_blk_load()` → `goto fini` → `set_default_env(errmsg)` (`env/env_blk.c:231`) |

Il valore di ritorno di `env_blk_load()` **non** basta a distinguerli: nel
primo caso `env_import_redund()` ritorna 0 e la funzione esce con `ret == 0`.
Il flag sì.

#### Il flag va azzerato all'ingresso, o la riparazione scatta a ogni boot

Una versione precedente di questa spec diceva che `set_default_env()`
(`env/common.c:92`) è «l'unico modo» in cui il flag può essere alzato. **È
falso**, e con quella premessa la riparazione avrebbe fatto una erase/program
di un blocco SPI NAND a ogni boot — su schede sane, in ping-pong fra le due
copie — annunciandola con una diagnostica falsa.

`GD_FLG_ENV_DEFAULT` è un **latch**: ha due setter e nessuno che lo azzeri.

| | |
|---|---|
| Setter 1 | `set_default_env()`, `env/common.c:92` |
| Setter 2 | `set_board_env(..., ready=true)`, `env/common.c:119-120` |
| Clearer | nessuno (`grep -rn GD_FLG_ENV_DEFAULT common/ env/ board/ arch/`) |
| Altro lettore | `board/xilinx/zynqmp/zynqmp.c:261`, non compilato qui |

Il secondo setter è sulla nostra strada. Con `CONFIG_USING_KERNEL_DTB=y` e
`CONFIG_ENV_IS_NOWHERE` non definito — la configurazione di questo albero —
`initr_env_nowhere()` prende il ramo `#else` e finisce con
`return set_board_env((char *)env_minimum, ENV_SIZE, 0, true);`
(`common/board_r.c:537`). In `init_sequence_r`, `initr_env_nowhere` viene
**prima** di `initr_env_switch`, che è il percorso che porta a
`env_relocate()` → `env_load()` → `env_blk_load()`. Quando la riparazione
guarda il flag, quindi, il flag è già alzato da un pezzo.

La correzione è una riga in testa a `env_blk_load()`, in **entrambi** i rami,
prima delle letture:

```c
gd->flags &= ~GD_FLG_ENV_DEFAULT;
```

Così il test in fondo significa «alzato durante *questo* caricamento», che è
la condizione che serve. La riga va accompagnata dal commento che spiega
perché esiste: senza, sembra ridondante e prima o poi qualcuno la toglie.

### Scrive una copia sola

È ciò che farebbe un `saveenv` manuale da questo stato, ed è sufficiente allo
scopo: l'env diventa valido, quindi `fw_setenv` non semina più nulla. L'altra
copia si riempie al primo salvataggio successivo.

**Quale delle due copie viene scritta.** `env_blk_save()` sceglie con
`copy = (gd->env_valid == ENV_VALID)` (`env/env_blk.c:126-127`), e a questo
punto `gd->env_valid` vale `ENV_VALID`: `env_blk` non dichiara `.init`, quindi
`env_init()` cade nel ramo `ret == -ENOENT` e lo imposta così
(`env/env.c:138-142`); e il ramo «entrambi i CRC non validi» di
`env_import_redund()` chiama `set_default_env()` e ritorna **senza toccarlo**
(`env/common.c:229-231`). Quindi `copy = 1` e si scrive
`CONFIG_ENV_OFFSET_REDUND` = `0x1480000`, cioè **`mtd3`, la copia
ridondante**. La primaria (`mtd2`) resta cancellata fino al salvataggio
successivo.

> Una versione precedente di questa sezione affermava l'opposto — che si parte
> da uno stato invalido e che due chiamate consecutive riscriverebbero «due
> volte la primaria». Entrambe le metà erano sbagliate. La **decisione** di
> scrivere una copia sola non cambia: è esattamente ciò che fa un `saveenv`
> manuale, e duplicare fuori da `env_blk_save()` la logica di alternanza per
> forzare una copia per parte sarebbe peggio del problema che risolve.

Il costo accettato è che fra il primo boot e il primo salvataggio successivo
la ridondanza non è ancora reale. È lo stesso stato in cui si trovava la
scheda dopo il primo `saveenv` manuale prima di questa modifica.

### Stampa una riga — e `env_blk_save()` ne stampa altre due

La riga della riparazione è esattamente:

```
*** Environment invalid, writing default to flash
```

La scrittura in flash al primo boot è un effetto collaterale che nessuno ha
chiesto. È innocuo, ma su una linea di produzione ogni scheda fa un ciclo di
erase/write da sola la prima volta che si accende, e chi guarda la seriale ha
diritto di vederlo accadere. Un `printf` è una riga di codice; un effetto
silenzioso è un debito.

`env_save()` però non è silenzioso: `env_blk_save()` stampa incondizionatamente
`Writing to %s%s(%s)... ` e poi `done` (`env/env_blk.c:135-136`). L'output
completo della riparazione è quindi di **tre** righe, l'ultima delle quali con
due `<NULL>`:

```
*** Warning - bad CRC, using default environment
*** Environment invalid, writing default to flash
Writing to redundant <NULL>(<NULL>)... done
```

I `<NULL>` sono `devtype` e `devnum`: `set_default_env()` ha appena sostituito
l'intera hashtable, portandosi via i valori che `rockchip_get_bootdev()` vi
aveva messo, e `boot_devtype_init()` non li rimette perché è già stata
chiamata una volta. `lib/vsprintf.c` stampa `<NULL>` per i puntatori nulli:
non è un crash, e non c'è niente da correggere. Va **documentato**, perché
altrimenti sembra un guasto proprio a chi è stato istruito a segnalare
l'output inatteso.

### Se la scrittura fallisce

Si stampa l'errore e si prosegue con l'ambiente in RAM — il comportamento di
oggi. Riproverà al boot successivo. Una flash che non si lascia scrivere è un
problema più grande di questo, e il boot non deve morirci sopra.

---

## Il ripristino di fabbrica diventa un gesto esplicito

Con questa modifica, azzerare l'ambiente è:

```
# flash_erase /dev/mtd2 0 0
# flash_erase /dev/mtd3 0 0
# reboot
```

Al boot successivo U-Boot riscrive il default compilato.

**`update.img` continua a non toccare l'env.** Il `package-file` generato da
`post-image.sh` elenca `parameter`, `bootloader`, `uboot`, `boot`, `rootfs`;
`env` ed `env_r` non ci sono, quindi `rkdeveloptool uf` non le scrive.

Questa è una scelta, non un residuo. `rkdeveloptool uf` richiede USB e una
persona davanti alla scheda: è un'operazione da banco o da fabbrica, non il
percorso di aggiornamento in campo — quello lo costruirà il progetto che nasce
dal fork, e non passerà da `update.img`. Un aggiornamento firmware che
cancellasse MAC address, numero di serie e calibrazioni sarebbe un difetto,
non un ripristino.

### Alternativa scartata: pre-seed di `env.img` in `update.img`

Era tecnicamente più economica di quanto la D6 stimasse. `mkenvimage` è già
costruito in `$(UBOOT_DIR)/tools/`, e `default_environment` è un simbolo in
`.rodata` dell'ELF di U-Boot: si estrae con `objcopy` e l'offset del simbolo,
quindi **non ci sarebbe stato nessun valore da tenere allineato a mano** —
l'obiezione centrale della D6 non reggeva.

È stata scartata lo stesso, per due motivi:

1. **Renderebbe distruttivo ogni aggiornamento firmware.** Con `env.img` nel
   pacchetto, ogni `rkdeveloptool uf` sovrascriverebbe l'ambiente, e con esso
   i dati per-esemplare che sono la ragione per cui l'env esiste.
2. **Copre meno casi.** Il pre-seed protegge il percorso «riflash completo».
   Lascia scoperti il flash delle singole partizioni — che il README documenta
   come procedura — e la corruzione tardiva di entrambe le copie.
   L'auto-riparazione copre tutti e tre.

Porta anche una catena di estrazione dall'ELF dentro `post-image.sh`
(`objcopy`, offset dal simbolo, `dd`, conversione NUL) più modifiche a
`genimage.cfg`, al `package-file` e a `docs/check-artifacts.sh`, contro una
funzione in un file.

---

## Design per file

### `external/board/lyra-plus/patches/uboot/0007-env-blk-...patch` (nuovo)

`env/env_blk.c`, in testa e in fondo a `env_blk_load()`, nel ramo con
`CONFIG_ENV_OFFSET_REDUND`.

In testa, prima delle letture:

- `gd->flags &= ~GD_FLG_ENV_DEFAULT;`, con il commento che spiega perché non è
  ridondante.

In fondo, dopo che i percorsi di import hanno deciso e prima del `return`:

- se `gd->flags & GD_FLG_ENV_DEFAULT`, stampa la riga e chiama `env_save()`;
- se il salvataggio fallisce, stampa l'errore e prosegue.

La prosa della patch deve spiegare **perché**, non cosa: il comportamento di
`fw_setenv` su CRC non valido, che è la ragione per cui lo stato vergine non
può sopravvivere fino allo spazio utente; e il latch a due setter, che è la
ragione per cui l'azzeramento in testa esiste.

Va valutato in fase di piano se la stessa modifica serva anche nel ramo
`#else` (senza `CONFIG_ENV_OFFSET_REDUND`): questo albero non lo compila, ma
la funzione è la stessa e un fork che tolga la ridondanza ricadrebbe nella
trappola. Se il costo è una riga, si fa.

### `docs/superpowers/specs/2026-09-06-uboot-env-persistente-design.md`

La D6 va **riscritta, non cancellata**: la decisione di non pre-seedare resta,
ma il motivo cambia, e va detto che la motivazione originale è stata
falsificata sull'hardware. Un rimando a questo documento.

### `docs/BOARD-FACTS.md`

Il comportamento di `fw_setenv` su CRC non valido è un **fatto della
piattaforma**, non un dettaglio di questa patch: va registrato con la citazione
del sorgente e il contenuto del default estraneo. È esattamente il tipo di
trappola che quel documento esiste per intercettare.

### `README.md`

- Il primo boot dopo un `flash_erase` dell'env stampa la riga nuova e ripara.
  Il vecchio testo sul `Warning - bad CRC` atteso va aggiornato: quel messaggio
  ora è seguito dalla riparazione.
- La procedura di ripristino di fabbrica.
- Nella sezione sull'environment: `fw_setenv` è sicuro **perché** U-Boot ha
  già riparato. Non presentarlo come una cautela da ricordare.

### `docs/superpowers/plans/2026-09-06-uboot-env-persistente.md`

Il **Task 10** va corretto prima di essere eseguito: il criterio 2 come scritto
è la trappola. E il criterio 3 (`flash_erase /dev/mtd2 0 1`, reboot) ora
interagisce con l'auto-riparazione — cancellare una sola copia non attiva la
riparazione, perché l'altra resta valida, quindi il test resta valido; ma va
detto esplicitamente, altrimenti sembra ambiguo.

---

## Criteri di accettazione

| # | Criterio | Come si verifica |
|---|---|---|
| 1 | L'env vergine si ripara | `flash_erase /dev/mtd2 0 0` e `/dev/mtd3`, reboot. U-Boot stampa la riga nuova; al prompt `printenv bootcmd` dà quello di Rockchip |
| 2 | La riparazione persiste | Un secondo reboot **non** ristampa la riga: la copia scritta è valida |
| 3 | `fw_setenv` non semina più | Su una scheda appena cancellata e riavviata, `fw_setenv pippo 1` da Linux **non** stampa `Warning: Bad CRC` |
| 4 | Il boot regge | Dopo il criterio 3, reboot: la scheda arriva a Linux. È il guasto originale, riprodotto e non più riproducibile |
| 5 | La ridondanza si completa | Dopo un `saveenv` al prompt, `hexdump` di `/dev/mtd2` e `/dev/mtd3` mostrano due copie valide |
| 6 | Nessuna regressione di build | `make lyra_plus_defconfig && make`, e le **sei** patch U-Boot precedenti (`0001`…`0006`) restano applicate |

I criteri 1-5 richiedono la scheda. Il 6 no.

---

## Rischi noti

1. **Scrittura in flash non richiesta al primo boot.** Accettata e resa
   visibile dalla riga stampata. Su una linea di produzione è un ciclo di
   erase/write per scheda, una volta — ma **solo grazie all'azzeramento di
   `GD_FLG_ENV_DEFAULT`** in testa a `env_blk_load()`. Senza quella riga il
   flag risulta alzato a ogni boot, anche con un environment sano, e la
   riparazione fa una erase+program per boot in ping-pong fra le due copie.
   Chiunque tolga quella riga credendola ridondante riporta il rischio da
   «una volta per scheda» a «una volta per boot, per sempre».
2. **Se il salvataggio fallisce, riprova a ogni boot.** Rumoroso ma non
   fatale, e il rumore è il sintomo giusto per una flash che non si scrive.
3. **La patch tocca `env/env_blk.c`**, che è codice vendor poco battuto — zero
   defconfig in questo albero usano `ENV_IS_IN_BLK_DEV`. Vale qui la stessa
   mitigazione del design precedente: i criteri 1-5 lo esercitano sulla
   scheda.
4. **Una settima patch da riapplicare** se lo SHA di U-Boot viene alzato. Il
   mirror è a SHA fisso e la serie Rockchip è ferma, quindi il rischio è lo
   stesso già accettato per le patch 0005 e 0006.
5. **Sulla corruzione tardiva di entrambe le copie, la riparazione distrugge
   i dati per-esemplare.** Al primo boot le due copie sono vergini e non c'è
   niente da perdere; ma se entrambe si corrompono dopo che la scheda è stata
   personalizzata, `set_default_env()` sostituisce MAC address, numero di
   serie e calibrazioni con il default compilato, e la riparazione ne scrive
   subito una copia in flash — prima che chiunque abbia potuto fare un dump
   dei blocchi originali. La riga stampata dice che l'environment non era
   valido, **non** che dei dati sono andati persi. È il prezzo di riparare
   senza chiedere, ed è accettato: un environment non valido lasciato in
   flash è la trappola per `fw_setenv`, cioè una scheda che non parte. Chi
   dovesse recuperare quei dati ha una sola copia da cui provarci, quella
   che la riparazione non ha ancora sovrascritto.
