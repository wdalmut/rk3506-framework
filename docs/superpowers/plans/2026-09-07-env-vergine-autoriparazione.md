# Auto-riparazione dell'environment vergine — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** far sì che U-Boot riscriva l'environment quando lo trova non valido, così che lo stato vergine non sopravviva fino allo spazio utente, dove `fw_setenv` lo trasformerebbe in una scheda che non parte.

**Architecture:** una funzione statica in `env/env_blk.c`, chiamata da entrambi i rami di `env_blk_load()`, che riconosce dal flag `GD_FLG_ENV_DEFAULT` che l'ambiente in memoria è il default compilato — cioè che nessuna delle due copie era usabile — stampa una riga e chiama `env_save()`. Perché quella lettura significhi qualcosa, `env_blk_load()` azzera il flag in testa a entrambi i rami: il flag è un latch con due setter e nessun clearer, e `initr_env_nowhere()` lo alza prima che qualunque driver di environment giri. Nessun artefatto nuovo, nessun cambio a `update.img` o a `parameter.txt`. Il resto del piano corregge i documenti che descrivevano il vecchio comportamento, compresa la procedura di accettazione che conteneva essa stessa la trappola.

**Tech Stack:** U-Boot 2017.09 Rockchip (SHA `1625f78b6dcf9fe401d447da79132b7bc6804538`), Buildroot 2026.02.3, Docker per la build.

**Spec:** [docs/superpowers/specs/2026-09-07-env-vergine-autoriparazione-design.md](../specs/2026-09-07-env-vergine-autoriparazione-design.md)

## Global Constraints

- **Il rilevatore è `gd->flags & GD_FLG_ENV_DEFAULT`** (`include/asm-generic/global_data.h:180`). Copre sia il CRC non valido su entrambe le copie sia l'errore di I/O; il valore di ritorno di `env_blk_load()` no.
- **Il flag va azzerato in testa a `env_blk_load()`, in entrambi i rami.** Non è un dettaglio: è un latch con **due** setter — `set_default_env()` (`env/common.c:92`) e `set_board_env(..., ready=true)` (`env/common.c:119-120`) — e **nessuno** che lo azzeri. Con `CONFIG_USING_KERNEL_DTB=y` e `CONFIG_ENV_IS_NOWHERE` non definito, `initr_env_nowhere()` passa dal secondo (`common/board_r.c:537`) e in `init_sequence_r` sta prima di `initr_env_switch`, cioè del percorso che arriva a `env_blk_load()`. Senza l'azzeramento la riparazione scatta a **ogni** boot, anche su una scheda sana. La riga porta un commento che spiega perché non è ridondante.
- **Si salva una copia sola.** `env_save()` → `env_blk_save()`, una chiamata. Da questo stato `gd->env_valid` vale `ENV_VALID` (`env_blk` non dichiara `.init`, quindi `env_init()` lo imposta così — `env/env.c:138-142` — e il ramo «entrambi i CRC non validi» di `env_import_redund()` non lo tocca — `env/common.c:229-231`), quindi `env_blk_save()` sceglie `copy = 1` e scrive la copia **ridondante** (`mtd3`, `0x1480000`). È ciò che farebbe un `saveenv` manuale; la primaria si riempie al salvataggio successivo. Non tentare di scriverle entrambe: richiederebbe di duplicare fuori da `env_blk_save()` la logica di alternanza su `gd->env_valid` (`env/env_blk.c:126-127` e `:148`).
- **La riga stampata è esattamente:** `*** Environment invalid, writing default to flash`
- **Un salvataggio fallito non è fatale:** si stampa l'errore e si prosegue con l'ambiente in RAM.
- **La riparazione scatta solo se ENTRAMBE le copie sono inutilizzabili.** Con una sola copia cancellata, `env_import_redund()` usa l'altra e non alza il flag: nessuna riparazione. È voluto — è ciò che rende ancora valido il criterio 3 del piano precedente.
- **Nessun fork.** Il delta a U-Boot è una patch in `external/board/lyra-plus/patches/uboot/`, nel formato delle esistenti: riga `From:`, riga `Subject: [PATCH n/m] ...`, prosa in italiano che spiega il *perché*, poi `diff -u` con prefissi `a/` e `b/`. Lo SHA nei defconfig non cambia.
- **Lingua:** commenti e messaggi dei file di codice in italiano **senza lettere accentate** (`e'`, `perche'`), tranne le stringhe stampate da U-Boot che restano in inglese come tutte le altre del file. I `.md` usano gli accenti veri.
- **SPDX e percorsi:** header invariati, i path restano `external/board/lyra-plus/`.
- `bash -n` e `shellcheck -S warning` restano silenziosi su tutti gli script del board; il job `docs` della CI non deve trovare link morti.

---

## File Structure

| File | Responsabilità | Azione |
|---|---|---|
| `external/board/lyra-plus/patches/uboot/0007-env-blk-repair-invalid-environment-on-load.patch` | La riparazione. Unico delta funzionale del piano. | **Crea** |
| `docs/superpowers/specs/2026-09-06-uboot-env-persistente-design.md` | La D6: la decisione resta, il motivo cambia. | Modifica |
| `docs/superpowers/plans/2026-09-06-uboot-env-persistente.md` | Il Task 10: la procedura hardware conteneva la trappola. | Modifica |
| `docs/BOARD-FACTS.md` | Il comportamento di `fw_setenv` su CRC non valido come fatto della piattaforma. | Modifica |
| `README.md` | Primo boot, ripristino di fabbrica, sezione sull'environment. | Modifica |

**Fatti già verificati nell'albero — non ri-derivarli:**

- `CONFIG_CMD_SAVEENV=y` (`.config:546`), quindi `drv->save` esiste e `env_save()` non tornerà `-ENOSYS`.
- `env_save()` (`env/env.c:111-127`) è un wrapper sottile su `drv->save()`, senza guardie di rientranza: chiamarlo da dentro `env_blk_load()` funziona.
- Le patch 0005 e 0006 toccano `env/Kconfig` e `include/environment.h`. **Nessuna tocca `env/env_blk.c`**, quindi il file estratto in `output/build/uboot-*/env/env_blk.c` è già pristino e può servire da base per il `diff -u` senza ripartire da un'estrazione pulita.

---

## Task 1: la patch che ripara

**Files:**
- Create: `external/board/lyra-plus/patches/uboot/0007-env-blk-repair-invalid-environment-on-load.patch`

**Interfaces:**
- Consumes: `GD_FLG_ENV_DEFAULT`, `env_save()`, `set_default_env()` — tutti già disponibili in `env/env_blk.c` tramite `<common.h>` ed `<environment.h>`, già inclusi in testa al file.
- Produces: niente per i task successivi. I task 2 e 3 documentano questo comportamento ma non dipendono da simboli.

**Il contesto che rende la patch necessaria**, da mettere nella sua prosa: `fw_setenv`, trovando un CRC non valido, non si limita a rifiutare — sostituisce l'intero ambiente con il default compilato dentro `fw_env`, che è quello di uboot-tools e contiene `bootcmd=bootp; ...; bootm`, senza nessuno dei comandi di boot Rockchip. Il boot successivo trova un CRC valido, si fida, ed esegue quel bootcmd: `bootp` su una scheda senza rete, poi `bootm` senza immagine caricata. Data abort. Osservato sulla scheda il 2026-09-06.

- [ ] **Step 1: Scrivi il test che fallisce**

Crea `/tmp/test-env-repair.sh` (usa e getta, **non** va committato):

```bash
#!/usr/bin/env bash
set -uo pipefail
U="$(ls -d output/build/uboot-* 2>/dev/null | head -1)"
[ -n "$U" ] || { echo "FAIL: nessun output/build/uboot-*"; exit 1; }
NM="$(ls output/host/bin/*-linux-*-nm 2>/dev/null | head -1)"

fail=0
check() {
	if [ "$2" = "$3" ]; then echo "ok   $1"
	else echo "FAIL $1"; echo "     got:  '$2'"; echo "     want: '$3'"; fail=1; fi
}

# 1. La stringa e' compilata dentro il binario finale.
if strings "$U/u-boot" | grep -qx '\*\*\* Environment invalid, writing default to flash'; then
	echo "ok   la riga di riparazione e' nel binario"
else
	echo "FAIL la riga di riparazione NON e' nel binario"; fail=1
fi

# 2. env_blk.o referenzia davvero env_save: prova che la chiamata esiste e non
#    e' stata ottimizzata via. Simbolo indefinito 'U', risolto in fase di link.
if [ -n "$NM" ] && [ -f "$U/env/env_blk.o" ]; then
	if "$NM" "$U/env/env_blk.o" | grep -qE '^ +U env_save$'; then
		echo "ok   env_blk.o chiama env_save"
	else
		echo "FAIL env_blk.o non referenzia env_save"
		"$NM" "$U/env/env_blk.o" | grep -i env_ | sed 's/^/     /'
		fail=1
	fi
else
	echo "FAIL nm o env/env_blk.o non trovati"; fail=1
fi

# 3. Le sei patch precedenti restano applicate: nessuna regressione.
n="$(grep -c 'patches/uboot/000[1-6]-' "$U/.applied_patches_list" 2>/dev/null || echo 0)"
check "sei patch U-Boot applicate" "$n" "6"

# 4. La patch nuova e' fra quelle applicate.
if grep -q '0007-env-blk-repair' "$U/.applied_patches_list" 2>/dev/null; then
	echo "ok   la 0007 e' applicata"
else
	echo "FAIL la 0007 non risulta applicata"; fail=1
fi

# 5. L'azzeramento del flag c'e' in ENTRAMBI i rami di env_blk_load(): senza,
#    la riparazione scatta a ogni boot invece che sul solo env non valido.
n="$(grep -c 'gd->flags &= ~GD_FLG_ENV_DEFAULT;' "$U/env/env_blk.c" 2>/dev/null || echo 0)"
check "GD_FLG_ENV_DEFAULT azzerato in entrambi i rami" "$n" "2"

exit $fail
```

- [ ] **Step 2: Esegui il test sull'albero attuale per vederlo fallire**

Run: `bash /tmp/test-env-repair.sh`

Expected: FAIL sui controlli 1, 2, 4 e 5; il controllo 3 passa (sei patch, `0001`…`0006`). Oggi `env_blk.o` non referenzia `env_save`, la stringa non esiste e il flag non viene azzerato.

- [ ] **Step 3: Prepara le copie per il diff**

`env/env_blk.c` non è toccato da nessuna patch esistente, quindi il file estratto è già pristino.

```bash
U="$(ls -d output/build/uboot-* | head -1)"
mkdir -p /tmp/p7/a/env /tmp/p7/b/env
cp "$U/env/env_blk.c" /tmp/p7/a/env/env_blk.c
cp "$U/env/env_blk.c" /tmp/p7/b/env/env_blk.c
```

- [ ] **Step 4: Scrivi la funzione di riparazione**

In `/tmp/p7/b/env/env_blk.c`, subito **dopo** la chiusura di `read_env()` e **prima** di `#ifdef CONFIG_ENV_OFFSET_REDUND`. Nel file pristino sono le righe 169-171:

```c
}

#ifdef CONFIG_ENV_OFFSET_REDUND
```

Inserisci fra le due, separata da righe vuote:

```c
/*
 * Un environment non valido non puo' sopravvivere fino allo spazio utente.
 *
 * fw_setenv, trovando un CRC non valido, NON si limita a rifiutare: sostituisce
 * l'intero ambiente con il default compilato dentro fw_env (tools/env/fw_env.c,
 * ramo "Warning: Bad CRC, using default environment"), che e' quello di
 * uboot-tools e non contiene nessuno dei comandi di boot Rockchip. Il boot
 * successivo trova un CRC valido, si fida, ed esegue un bootcmd estraneo.
 *
 * Si ripara qui, al primo boot, prima che Linux esista.
 *
 * Il rilevatore e' GD_FLG_ENV_DEFAULT: copre sia il CRC non valido su entrambe
 * le copie (via env_import_redund) sia l'errore di I/O, che il valore di
 * ritorno di env_blk_load() non distingue -- nel primo caso
 * env_import_redund() ritorna 0.
 *
 * ATTENZIONE: quel flag e' un latch, non uno stato. Ha DUE setter --
 * set_default_env() (env/common.c:92) e set_board_env(..., ready=true)
 * (env/common.c:119-120) -- e nessuno che lo azzeri. initr_env_nowhere() usa
 * il secondo (common/board_r.c:537, ramo #else con CONFIG_ENV_IS_NOWHERE non
 * definito) e in init_sequence_r viene prima di initr_env_switch, che e' il
 * percorso che porta fin qui. Al nostro arrivo il flag e' quindi gia' alzato
 * anche con un environment perfettamente sano. E' per questo che
 * env_blk_load() lo azzera in testa: solo cosi' qui significa "alzato durante
 * QUESTO caricamento". Senza quell'azzeramento questa funzione scriverebbe la
 * flash a ogni boot.
 *
 * Si scrive UNA copia, che e' esattamente cio' che farebbe un saveenv manuale
 * partendo da questo stato. env_blk_save() sceglie con
 * copy = (gd->env_valid == ENV_VALID) (env/env_blk.c:126-127), e qui
 * gd->env_valid vale ENV_VALID: env_init() lo mette cosi' perche' env_blk non
 * dichiara .init (env/env.c:138-142), e il ramo "entrambi i CRC non validi" di
 * env_import_redund() non lo tocca (env/common.c:229-231). Si scrive dunque la
 * copia RIDONDANTE; la primaria si riempie al salvataggio successivo.
 *
 * env_blk_save() stampa una riga sua, "Writing to redundant <NULL>(<NULL>)...
 * done": i <NULL> sono devtype e devnum, che set_default_env() ha appena tolto
 * dall'hashtable. E' atteso e innocuo -- lib/vsprintf.c stampa "<NULL>" per i
 * puntatori nulli.
 */
static __maybe_unused void env_blk_repair(void)
{
	int ret;

	if (!(gd->flags & GD_FLG_ENV_DEFAULT))
		return;

	puts("*** Environment invalid, writing default to flash\n");

	ret = env_save();
	if (ret)
		printf("*** Error - failed to write environment (%d)\n", ret);
}
```

- [ ] **Step 5: Azzera il flag in testa a entrambi i rami, poi chiamala in fondo a entrambi**

**L'azzeramento non è opzionale.** `GD_FLG_ENV_DEFAULT` è un latch con due
setter e nessun clearer, e `initr_env_nowhere()` lo alza prima che qualunque
driver di environment giri: senza azzerarlo, la lettura in fondo è sempre vera
e la riparazione riscrive la flash a ogni boot. Va inserito **prima delle
letture**, subito dopo le dichiarazioni, in tutti e due i rami, con il
commento che ne spiega la ragione — altrimenti sembra una riga morta:

```c
	/*
	 * GD_FLG_ENV_DEFAULT e' un latch con due setter e nessuno che lo
	 * azzeri, e initr_env_nowhere() lo alza prima che qualunque driver di
	 * environment giri (common/board_r.c:537 -> env/common.c:119-120).
	 * Azzerandolo qui, in fondo alla funzione il flag significa "alzato
	 * durante QUESTO caricamento", che e' la condizione che interessa a
	 * env_blk_repair(). Senza, la riparazione scatterebbe a ogni boot
	 * anche con un environment sano: vedi il commento su env_blk_repair().
	 * Non e' una riga ridondante, non toglierla.
	 */
	gd->flags &= ~GD_FLG_ENV_DEFAULT;
```

Nel ramo **con** ridondanza va subito dopo i due
`ALLOC_CACHE_ALIGN_BUFFER(env_t, tmp_env…, 1);` e prima di
`blk_desc = rockchip_get_bootdev();`. Nel ramo **senza** ridondanza va dopo
`u32 offset; int ret;`, sempre prima di `blk_desc = rockchip_get_bootdev();`.

Poi le chiamate in fondo. Nel ramo **con** ridondanza, la fine di
`env_blk_load()` nel file pristino è:

```c
fini:
	fini_blk_hwpart_for_env();
err:
	if (ret)
		set_default_env(errmsg);

#endif
	return ret;
}
```

Diventa:

```c
fini:
	fini_blk_hwpart_for_env();
err:
	if (ret)
		set_default_env(errmsg);

	env_blk_repair();

#endif
	return ret;
}
```

Nel ramo **senza** ridondanza (dopo `#else /* ! CONFIG_ENV_OFFSET_REDUND */`) la fine è:

```c
fini:
	fini_blk_hwpart_for_env();
err:
	if (ret)
		set_default_env(errmsg);
#endif
	return ret;
}
```

Diventa:

```c
fini:
	fini_blk_hwpart_for_env();
err:
	if (ret)
		set_default_env(errmsg);

	env_blk_repair();
#endif
	return ret;
}
```

Questo albero compila solo il primo ramo, ma la funzione è condivisa e coprire anche il secondo costa una riga: un fork che togliesse `CONFIG_ENV_OFFSET_REDUND` ricadrebbe altrimenti nella trappola. Duplicare il corpo invece di condividere la funzione sarebbe un difetto, non un'ottimizzazione.

- [ ] **Step 6: Genera la patch**

```bash
( cd /tmp/p7 && diff -u a/env/env_blk.c b/env/env_blk.c ) > /tmp/0007.diff
cat /tmp/0007.diff   # controlla a occhio: tre hunk, nessuna riga inattesa
```

Poi:

```bash
cat > external/board/lyra-plus/patches/uboot/0007-env-blk-repair-invalid-environment-on-load.patch <<'HDREOF'
From: rk3506-framework <walter.dalmut@corley.it>
Subject: [PATCH 7/7] env_blk: repair an invalid environment at load time

Un environment non valido in flash non e' uno stato neutro che il primo
saveenv sistemera': e' una trappola armata per lo spazio utente.

fw_setenv, quando trova un CRC non valido, NON si limita a rifiutare la
scrittura. Sostituisce l'intero ambiente con il default compilato dentro
fw_env stesso (tools/env/fw_env.c, ramo "Warning: Bad CRC, using default
environment") e poi ci applica la modifica richiesta. Quel default e' quello
di uboot-tools, non quello di questa U-Boot: contiene

    bootcmd=bootp; setenv bootargs root=/dev/nfs ... ; bootm

e nessuno di boot_android, bootrkp, boot_fit. Al boot successivo U-Boot trova
un CRC valido, si fida, importa, e scaduto il bootdelay esegue bootp su una
scheda senza rete e poi bootm senza nessuna immagine caricata. Data abort e
reset in loop. Osservato su hardware il 2026-09-06.

La riparazione va fatta qui, al primo boot, prima che Linux esista e quindi
prima che qualcuno possa lanciare fw_setenv.

Il rilevatore e' GD_FLG_ENV_DEFAULT, che copre sia il CRC non valido su
entrambe le copie (via env_import_redund) sia l'errore di I/O. Il valore di
ritorno di env_blk_load() non li distingue, perche' nel primo caso
env_import_redund() ritorna 0.

Il flag pero' non si puo' leggere cosi' com'e': e' un latch con DUE setter --
set_default_env() (env/common.c:92) e set_board_env(..., ready=true)
(env/common.c:119-120) -- e nessuno che lo azzeri. Su questa configurazione
initr_env_nowhere() usa il secondo (CONFIG_USING_KERNEL_DTB=y e
CONFIG_ENV_IS_NOWHERE non definito, common/board_r.c:537) e in
init_sequence_r sta prima di initr_env_switch, che e' il percorso che arriva
a env_blk_load(). Il flag e' quindi gia' alzato all'ingresso anche con un
environment perfettamente sano. Per questo env_blk_load() lo azzera in testa,
in entrambi i rami: solo cosi' la lettura in fondo significa "alzato durante
questo caricamento", e la riparazione non scatta a ogni boot facendo una
erase+program di un blocco SPI NAND su una scheda che non ne ha bisogno.

Si scrive una copia sola, che e' esattamente cio' che farebbe un saveenv
manuale partendo da questo stato: gd->env_valid vale ENV_VALID (env_blk non
dichiara .init, quindi env_init() lo imposta cosi', env/env.c:138-142, e il
ramo "entrambi i CRC non validi" di env_import_redund() non lo tocca,
env/common.c:229-231), percio' env_blk_save() sceglie copy = 1 e scrive la
copia ridondante. La primaria si riempie al salvataggio successivo.

env_blk_save() stampa anche la propria riga "Writing to redundant
<NULL>(<NULL>)... done": devtype e devnum non ci sono piu' perche'
set_default_env() ha appena sostituito l'hashtable. E' atteso, e vsprintf
gestisce i puntatori nulli.

Un salvataggio fallito stampa e prosegue con l'ambiente in RAM: una flash che
non si lascia scrivere e' un problema piu' grande di questo, e il boot non
deve morirci sopra.

HDREOF
cat /tmp/0007.diff >> external/board/lyra-plus/patches/uboot/0007-env-blk-repair-invalid-environment-on-load.patch
```

- [ ] **Step 7: Ricostruisci da zero e verifica che la patch si applichi**

Le patch si applicano all'estrazione, quindi serve ripartire dal sorgente:

```bash
rm -rf output/build/uboot-*
make uboot 2>&1 | tail -40
```

`make uboot`, non `uboot-rebuild`: cancellata la build dir non ci sono più gli stamp su cui `-rebuild` si appoggia.

Expected: nella traccia compare `Applying 0007-env-blk-repair-...patch` senza `FAILED`. Le build passano da Docker e durano circa quattro minuti; se una chiamata in foreground va in timeout non significa che sia fallita — rilanciala in background e verifica con `docker ps`.

- [ ] **Step 8: Esegui il test per verificare che passi**

Run: `bash /tmp/test-env-repair.sh`

Expected: PASS, cinque righe `ok`. In particolare `nm env/env_blk.o` mostra ` U env_save`, che è la prova a livello di compilazione che la chiamata esiste davvero e non è stata eliminata, e il controllo 5 prova che l'azzeramento del flag è arrivato nell'albero estratto in entrambi i rami.

- [ ] **Step 9: Verifica che non ci siano regressioni sull'env**

La patch tocca lo stesso file dei task precedenti: conferma che il backend è ancora quello e che la ridondanza è ancora reale.

```bash
U="$(ls -d output/build/uboot-* | head -1)"
grep -E "CONFIG_ENV_(IS_IN_BLK_DEV|OFFSET|OFFSET_REDUND|SIZE)" "$U/include/generated/autoconf.h"
output/host/bin/arm-buildroot-linux-gnueabihf-gcc-nm "$U/env/common.o" | grep env_import_redund
```

Expected: `CONFIG_ENV_IS_IN_BLK_DEV 1`, `CONFIG_ENV_OFFSET 0x1400000`, `CONFIG_ENV_OFFSET_REDUND 0x1480000`, `CONFIG_ENV_SIZE 0x20000`, e `T env_import_redund`.

- [ ] **Step 10: Commit**

```bash
git add external/board/lyra-plus/patches/uboot/0007-env-blk-repair-invalid-environment-on-load.patch
git commit -m "uboot: l'environment non valido si ripara al caricamento

Un env non valido in flash non e' uno stato neutro. fw_setenv, trovandolo,
sostituisce l'intero ambiente con il default compilato dentro fw_env — che
e' quello di uboot-tools e ha bootcmd=bootp; ...; bootm, senza nessun
comando di boot Rockchip. Il boot successivo trova un CRC valido, si fida,
ed esegue quello: data abort e reset in loop. Osservato su hardware.

Si ripara al caricamento, prima che Linux esista e quindi prima che
qualcuno possa lanciare fw_setenv. Il rilevatore e' GD_FLG_ENV_DEFAULT, che
copre sia il CRC non valido su entrambe le copie sia l'errore di I/O.

Il flag va azzerato in testa a env_blk_load(): e' un latch con due setter e
nessun clearer, e initr_env_nowhere() lo alza prima che qualunque driver di
environment giri. Senza l'azzeramento la riparazione scatta a ogni boot.

Una copia sola, come un saveenv manuale da questo stato: gd->env_valid vale
ENV_VALID, quindi env_blk_save() sceglie copy = 1 e scrive la copia
ridondante; la primaria si riempie al salvataggio successivo. E una riga
stampata: la scrittura in flash al primo boot e' un effetto collaterale che
nessuno ha chiesto, e chi guarda la seriale ha diritto di vederlo."
```

---

## Task 2: i due documenti di progetto che descrivevano il vecchio comportamento

**Files:**
- Modify: `docs/superpowers/specs/2026-09-06-uboot-env-persistente-design.md` (sezione `### D6`, righe ~252-275)
- Modify: `docs/superpowers/plans/2026-09-06-uboot-env-persistente.md` (Task 10, Step 4 riga ~1891, Step 5 riga ~1902, Step 6 riga ~1915)

**Interfaces:**
- Consumes: il comportamento realizzato dal Task 1.
- Produces: niente.

**Perché è un task a sé:** il Task 10 di quel piano è la procedura che l'umano eseguirà al banco, e come scritta contiene la trappola che ha bloccato la scheda. Correggerlo non è cosmetica.

- [ ] **Step 1: Riscrivi la D6**

La sezione si intitola `### D6 — Le due copie nascono cancellate`. La **decisione** resta — non si pre-seeda — ma la motivazione cambia e va detto che quella originale è stata falsificata. Il titolo diventa `### D6 — Le due copie nascono cancellate, e U-Boot le ripara`.

Il nuovo testo deve contenere, in questo ordine:

1. Le due copie nascono cancellate e non si pre-seeda con `mkenvimage`: **questa parte resta**.
2. **La motivazione originale era sbagliata**, e va detto esplicitamente. Diceva che lo stato vergine costava solo «un messaggio di errore benigno che si vede una volta sola». Il messaggio è benigno; lo stato no. `fw_setenv` su un env con CRC non valido semina il default di uboot-tools, con `bootcmd=bootp; ...; bootm`, e il boot successivo muore. Osservato su hardware il 2026-09-06.
3. **La decisione nuova:** U-Boot ripara al caricamento, quindi lo stato vergine non arriva mai allo spazio utente. Rimando al design del 2026-09-07.
4. **Perché il pre-seed resta scartato**, con i motivi nuovi: renderebbe distruttivo ogni `rkdeveloptool uf` — e con esso i dati per-esemplare che sono la ragione per cui l'env esiste — e coprirebbe meno casi del solo riflash completo.
5. Il paragrafo esistente sul messaggio dedotto dal sorgente e sul caveat ECC resta valido e va **conservato**, aggiornato per dire che quel messaggio è ora seguito dalla riga di riparazione.

Aggiungi in testa alla sezione una riga di rimando:

```markdown
> **Emendata il 2026-09-07** da
> [L'environment vergine si ripara da solo al primo boot](2026-09-07-env-vergine-autoriparazione-design.md).
> La decisione di non pre-seedare resta; la motivazione originale era sbagliata.
```

- [ ] **Step 2: Correggi il Task 10, Step 4 (criterio 1)**

Il testo attuale dice che al primo boot U-Boot avrà stampato `*** Warning - bad CRC, using default environment` e che è atteso. Ora quel messaggio è **seguito** dalla riparazione. Il nuovo Expected deve dire che al primo boot dopo un riflash compaiono **due** righe:

```
*** Warning - bad CRC, using default environment
*** Environment invalid, writing default to flash
```

e che al secondo boot non compare nessuna delle due, perché la copia scritta è valida. Conserva il caveat ECC esistente: se comparisse `*** Error - No Valid Environment Area found` invece della prima riga, il driver SPI-NAND ritorna un errore ECC sulle pagine cancellate invece di `0xFF`; la riparazione scatta lo stesso, perché quel percorso alza lo stesso flag.

- [ ] **Step 3: Correggi il Task 10, Step 5 (criterio 2) — è lo step che ha bloccato la scheda**

Il testo attuale fa eseguire `fw_setenv pluto 2` da Linux senza dire nulla. Se quella è la prima scrittura dopo un riflash su una build **senza** la patch del Task 1, produce il guasto osservato.

Il nuovo testo deve:

- dire che lo step è sicuro **perché** U-Boot ha già riparato l'env al primo boot, non presentarlo come una cautela da ricordare;
- aggiungere un controllo prima del test vero, che vale anche come verifica della riparazione:

```
# fw_printenv bootcmd
```

Expected: il `bootcmd` di Rockchip (`boot_fit;boot_android ...`). Se invece esce `bootcmd=bootp; ...` l'ambiente è stato seminato da `fw_setenv` e la riparazione non ha funzionato: fermati e riporta, non proseguire con il reboot.

- [ ] **Step 4: Chiarisci il Task 10, Step 6 (criterio 3)**

Quel test cancella **una sola** copia (`flash_erase /dev/mtd2 0 1`) e verifica che il boot usi la ridondante. La riparazione **non** interferisce, e va detto esplicitamente perché ora sembrerebbe ambiguo: con una copia sola cancellata `env_import_redund()` usa l'altra e non alza `GD_FLG_ENV_DEFAULT`, quindi nessuna riparazione parte e il test resta quello di prima.

Aggiungi anche la conseguenza utile: se dopo quel test si vuole ripristinare la ridondanza, basta un `saveenv`, che scriverà la copia mancante.

- [ ] **Step 5: Verifica i link**

```bash
rc=0
for f in README.md docs/*.md docs/superpowers/specs/*.md docs/superpowers/plans/*.md; do
	dir="$(dirname "$f")"
	for l in $(grep -ohE '\]\([^)#]+(#[^)]*)?\)' "$f" | sed 's/^](//; s/)$//; s/#.*//'); do
		case "$l" in http*|""|../../*) continue ;; esac
		[ -e "$dir/$l" ] || { echo "MORTO in $f: $l"; rc=1; }
	done
done
[ $rc = 0 ] && echo "nessun link morto"
```

Expected: `nessun link morto`.

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/specs/2026-09-06-uboot-env-persistente-design.md \
        docs/superpowers/plans/2026-09-06-uboot-env-persistente.md
git commit -m "docs: la D6 e la procedura hardware descrivevano il vecchio comportamento

La D6 diceva che lo stato vergine costava un messaggio benigno. Costava una
scheda che non parte, se il primo a scrivere era fw_setenv. La decisione di
non pre-seedare resta, con motivi nuovi; la motivazione vecchia e' marcata
come falsificata invece che riscritta come se fosse sempre stata cosi'.

Il Task 10 conteneva la trappola: il criterio 2 fa scrivere fw_setenv come
prima operazione dopo un riflash. Ora dice perche' e' sicuro e come
accorgersi che non lo e'. Il criterio 3 chiarisce che cancellare una sola
copia non attiva la riparazione, quindi il test resta valido."
```

---

## Task 3: la documentazione che leggerà chi usa la scheda

**Files:**
- Modify: `docs/BOARD-FACTS.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: il comportamento realizzato dal Task 1.
- Produces: niente.

- [ ] **Step 1: `docs/BOARD-FACTS.md` — il comportamento di `fw_setenv` è un fatto della piattaforma**

Non è un dettaglio di questa patch: è un comportamento di `uboot-tools` che chiunque lavori su questa board incontrerà, ed è esattamente il tipo di trappola che quel documento esiste per intercettare. Aggiungi una sezione con:

- cosa fa `fw_setenv` su un CRC non valido, con la citazione del ramo in `tools/env/fw_env.c` («Warning: Bad CRC, using default environment»);
- il contenuto del default estraneo, che è verificabile sul target con
  `strings /usr/sbin/fw_printenv | grep '^bootcmd='`:

  ```
  bootcmd=bootp; setenv bootargs root=/dev/nfs nfsroot=${serverip}:${rootpath} ip=...; bootm
  ```

- che nessuno di `boot_android`, `bootrkp`, `boot_fit` compare in quel binario;
- che su questa board la trappola è disinnescata da U-Boot, che ripara al caricamento, con rimando al design del 2026-09-07.

- [ ] **Step 2: `README.md` — il primo boot**

La sezione che descrive il primo boot dopo un riflash dice oggi che `*** Warning - bad CRC, using default environment` è atteso. Aggiornala: quel messaggio è ora seguito da

```
*** Environment invalid, writing default to flash
```

e al boot successivo non compare più nessuna delle due. Spiega in una riga perché U-Boot scrive senza che gliel'abbiano chiesto: perché un env non valido non deve arrivare allo spazio utente, dove `fw_setenv` lo trasformerebbe in una scheda che non parte.

- [ ] **Step 3: `README.md` — il ripristino di fabbrica**

Aggiungi la procedura, con la spiegazione del perché non passa da `update.img`:

````markdown
### Riportare l'environment allo stato di fabbrica

```
# flash_erase /dev/mtd2 0 0
# flash_erase /dev/mtd3 0 0
# reboot
```

Al boot successivo U-Boot trova entrambe le copie non valide e riscrive il
default compilato, annunciandolo sulla seriale.

**`update.img` non tocca l'environment**, ed è voluto: il `package-file`
elenca `parameter`, `bootloader`, `uboot`, `boot` e `rootfs`, quindi un
riflash lascia intatti MAC address, numero di serie e calibrazioni. Un
aggiornamento firmware che li cancellasse sarebbe un difetto, non un
ripristino — per azzerarli serve il gesto esplicito qui sopra.
````

- [ ] **Step 4: `README.md` — la sezione sull'environment**

Nella sezione *L'environment U-Boot*, aggiungi che `fw_setenv` da Linux è sicuro **perché** U-Boot ha già riparato un eventuale env non valido al boot. Formulalo come una proprietà del sistema, non come una cautela che l'utente deve ricordarsi: se qualcuno deve ricordarsi una regola per non rompere la scheda, il sistema è progettato male.

- [ ] **Step 5: Verifica i link**

```bash
rc=0
for f in README.md docs/*.md; do
	dir="$(dirname "$f")"
	for l in $(grep -ohE '\]\([^)#]+(#[^)]*)?\)' "$f" | sed 's/^](//; s/)$//; s/#.*//'); do
		case "$l" in http*|""|../../*) continue ;; esac
		[ -e "$dir/$l" ] || { echo "MORTO in $f: $l"; rc=1; }
	done
done
[ $rc = 0 ] && echo "nessun link morto"
```

Expected: `nessun link morto`.

- [ ] **Step 6: Commit**

```bash
git add docs/BOARD-FACTS.md README.md
git commit -m "docs: fw_setenv semina un ambiente estraneo, e la board lo disinnesca

BOARD-FACTS prende il comportamento di fw_setenv su CRC non valido come
fatto della piattaforma, con il default estraneo verificabile sul target.
Non e' un dettaglio di implementazione: e' una trappola di uboot-tools che
chiunque lavori su questa board incontrerebbe.

Il README aggiorna il primo boot, aggiunge il ripristino di fabbrica e dice
che fw_setenv e' sicuro perche' U-Boot ha gia' riparato — come proprieta'
del sistema, non come regola da ricordare."
```

---

## Task 4: verifica sull'hardware

**Files:** nessuno.

**Interfaces:**
- Consumes: tutto.
- Produces: la conferma dei criteri di accettazione della spec.

Richiede la scheda. Non dispacciabile a un subagent.

- [ ] **Step 1: Build e riflash**

```bash
make lyra_plus_defconfig
make
rkdeveloptool uf output/images/update.img
```

- [ ] **Step 2: Criterio 1 — l'env vergine si ripara**

Da Linux, sulla scheda:
```
# flash_erase /dev/mtd2 0 0
# flash_erase /dev/mtd3 0 0
# reboot
```

Expected: **tre** righe, non una — la terza la stampa `env_blk_save()`, che non è silenzioso:

```
*** Warning - bad CRC, using default environment
*** Environment invalid, writing default to flash
Writing to redundant <NULL>(<NULL>)... done
```

I `<NULL>` sono attesi: sono `devtype` e `devnum`, che `set_default_env()` ha appena tolto dall'hashtable un istante prima della riparazione, e `boot_devtype_init()` non li rimette perché è già stata chiamata. Non è un guasto e non c'è niente da correggere. La parola `redundant` conferma che è la copia di `mtd3` a essere stata scritta.

Interrompi l'autoboot e verifica che l'ambiente sia quello giusto:
```
=> printenv bootcmd
```
Expected: il `bootcmd` di Rockchip, `boot_fit;boot_android ${devtype} ${devnum};`.

- [ ] **Step 3: Criterio 2 — la riparazione persiste**

```
=> reset
```

Expected: la riga di riparazione **non** compare più. La copia scritta è valida.

- [ ] **Step 4: Criterio 3 — `fw_setenv` non semina più**

Boota fino a Linux, poi:
```
# fw_setenv pippo 1
```

Expected: **nessun** `Warning: Bad CRC`. È la prova che U-Boot ha riparato prima che Linux esistesse.

- [ ] **Step 5: Criterio 4 — il boot regge**

```
# reboot
```

Expected: la scheda arriva a Linux. Questo è il guasto originale, riprodotto nella stessa sequenza che lo aveva causato, e non più riproducibile.

- [ ] **Step 6: Criterio 5 — la ridondanza si completa**

Dal prompt di U-Boot:
```
=> saveenv
=> reset
```
poi da Linux:
```
# hexdump -C /dev/mtd2 | head -2
# hexdump -C /dev/mtd3 | head -2
```

Expected: entrambe iniziano con un CRC32 seguito dal byte `flags`, e i due `flags` differiscono. **Prima** di questo `saveenv` la sola valida era `mtd3`, non `mtd2`: la riparazione scrive una copia sola, di proposito, e da quello stato `env_blk_save()` sceglie la **ridondante** (`gd->env_valid` vale `ENV_VALID`, quindi `copy = 1`). Se prima del `saveenv` fai un `hexdump` e trovi `/dev/mtd2` ancora tutta `0xFF`, è il comportamento atteso, non un guasto: guarda `/dev/mtd3`.

- [ ] **Step 7: Riporta cosa hai visto**

Se una delle righe attese non compare, o ne compare una che non è prevista, riportala: la spec dichiara che i messaggi sono **dedotti dal sorgente e non osservati su hardware**, e questo è il momento in cui smettono di esserlo. In particolare, se al posto di `*** Warning - bad CRC` esce `*** Error - No Valid Environment Area found`, il driver SPI-NAND ritorna un errore ECC sulle pagine cancellate invece di `0xFF` — la riparazione scatta lo stesso, ma il caveat della spec va chiuso con il dato reale.

---

## Self-Review

**Copertura della spec.**

| Sezione della spec | Task |
|---|---|
| Il rilevatore `GD_FLG_ENV_DEFAULT`, azzerato in testa a `env_blk_load()` | 1 |
| Scrive una copia sola (la **ridondante**), con il motivo | 1 |
| La riga stampata | 1 |
| Salvataggio fallito non fatale | 1 |
| Il ramo `#else` senza ridondanza — *domanda lasciata aperta dalla spec* | 1, Step 5: si copre, costa una riga, e la funzione è condivisa |
| Riscrittura della D6 | 2 |
| Correzione del Task 10 | 2 |
| `BOARD-FACTS.md`: il fatto su `fw_setenv` | 3 |
| `README.md`: primo boot, ripristino di fabbrica, sezione env | 3 |
| Criteri di accettazione 1-5 | 4 |
| Criterio 6 (nessuna regressione di build) | 1, Step 7 e Step 9 |

**Consistenza dei nomi.** `env_blk_repair()` è definita nel Task 1 Step 4 e chiamata con quel nome nello Step 5. `GD_FLG_ENV_DEFAULT`, `env_save()` e `set_default_env()` sono simboli esistenti di U-Boot, non introdotti qui. La stringa stampata è identica nel codice (Task 1), nei test (Task 1 Step 1), nei documenti (Task 2 e 3) e nella procedura hardware (Task 4).

**Ordine e dipendenze.** 1 → 2 → 3 → 4. I task 2 e 3 non dipendono l'uno dall'altro e potrebbero girare in parallelo; l'ordine scritto mette prima i documenti di progetto, che contengono la procedura sbagliata, e poi quelli utente.

**Cosa non è coperto, di proposito.** Il pre-seed di `env.img` in `update.img` — scartato dalla spec, con i motivi. La riparazione di una **singola** copia non valida: sarebbe una funzione diversa (scrubbing), invaliderebbe il criterio 3 del piano precedente, e la ridondanza esiste proprio per rendere raro quel caso.
