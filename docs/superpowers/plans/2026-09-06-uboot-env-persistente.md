# Environment U-Boot persistente e ridondante — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** dare alla board un ambiente U-Boot che sopravvive al reboot, ridondante su due partizioni MTD, leggibile e scrivibile anche da Linux con `fw_printenv`/`fw_setenv`.

**Architecture:** backend `CONFIG_ENV_IS_IN_BLK_DEV` (`env/env_blk.c`) su due partizioni MTD nuove da 512 KiB nel buco a 20 MiB di `parameter.txt`, una copia per partizione. `parameter.txt` resta la fonte unica degli offset: nasce un solo parser (`flash-layout.sh`), `post-build.sh` **genera** `/etc/fw_env.config` e `post-image.sh` **verifica** i valori di U-Boot e fa fallire la build se divergono. Gli indici MTD slittano (`rootfs` da `mtd2` a `mtd4`) e i tre punti che li cablavano vengono corretti.

**Tech Stack:** Buildroot 2025.x, U-Boot 2017.09 Rockchip (SHA `1625f78b6dcf9fe401d447da79132b7bc6804538`), kernel vendor 6.1 (SHA `73bca17b67938d649b072408780369f600555263`) e mainline 7.2.3, bash, GitHub Actions.

**Spec:** [docs/superpowers/specs/2026-09-06-uboot-env-persistente-design.md](../specs/2026-09-06-uboot-env-persistente-design.md)

## Global Constraints

- **Board:** Miranda V3 come destinazione, Luckfox Lyra Plus (RK3506G2) come veicolo di bring-up. I path restano `external/board/lyra-plus/`: **non rinominare nulla**.
- **Erase block:** `0x20000` (128 KiB). Settore di `parameter.txt`: 512 B.
- **Offset env (byte, assoluti dall'inizio del chip):** `CONFIG_ENV_OFFSET=0x1400000` (20 MiB), `CONFIG_ENV_OFFSET_REDUND=0x1480000` (20.5 MiB), `CONFIG_ENV_SIZE=0x20000`.
- **Partizioni env:** `env` e `env_r`, `0x400` settori (512 KiB, 4 erase block) ciascuna.
- **`rootfs` resta l'ultima partizione e resta `grow`.** Il suo offset (`0x10000` settori = 32 MiB) e la dimensione calcolata (`0xdf60000`) non cambiano.
- **Lingua:** commenti, messaggi e documentazione in italiano, senza lettere accentate nei file di codice (il resto dell'albero usa `e'`, `perche'`). I `.md` invece usano gli accenti veri.
- **Licenza:** ogni file nuovo inizia con `# SPDX-License-Identifier: GPL-2.0-or-later` e `# Copyright (C) 2026 Corley S.r.l.`.
- **Nessun fork:** ogni delta a U-Boot o al kernel deve essere una patch leggibile in `external/board/lyra-plus/patches/`. Gli SHA nei defconfig non si toccano.
- **`make savedefconfig` non deve produrre diff** su nessuno dei quattro defconfig (job `defconfig` della CI).
- **Le due copie nascono cancellate.** Al primo boot dopo il riflash `*** Warning - bad CRC, using default environment` e' **atteso**, non un guasto. Il messaggio e' dedotto dal sorgente (`env/env_blk.c:158-169` e `env/common.c:73-78`, :229-231), non osservato su hardware: `read_env()` segnala solo errori di I/O, e una pagina cancellata si rilegge come `0xFF`, quindi il ramo `*** Error - No Valid Environment Area found` non viene preso.

---

## File Structure

| File | Responsabilita' | Azione |
|---|---|---|
| `external/board/lyra-plus/flash-layout.sh` | Parser unico di `parameter.txt`. Converte settori → byte. Sorgibile ed eseguibile. | **Crea** |
| `external/board/lyra-plus/parameter.txt` | Fonte unica del layout, e quindi della GPT. | Modifica |
| `external/board/lyra-plus/uboot.config` | Fragment Kconfig di U-Boot: backend e offset dell'env. | Modifica |
| `external/board/lyra-plus/patches/uboot/0005-env-make-ENV_OFFSET_REDUND-available-outside-ENVF.patch` | Rende `ENV_OFFSET_REDUND` settabile con `ENV_IS_IN_BLK_DEV`. | **Crea** |
| `external/board/lyra-plus/patches/uboot/0006-environment-derive-SYS_REDUNDAND_ENVIRONMENT-for-BLK.patch` | Fa esistere il byte `flags` in `env_t` e compilare `env_import_redund()`. | **Crea** |
| `external/board/lyra-plus/patches/linux/73bca17b.../0001-...ubi-mtd-per-nome.patch` | `ubi.mtd=2` → `ubi.mtd=rootfs` nel DTS vendor. Solo per lo SHA vendor. | **Crea** |
| `external/board/lyra-plus/post-image.sh` | Usa `flash-layout.sh`; verifica offset U-Boot ↔ `parameter.txt`; verifica il DTB. | Modifica |
| `external/board/lyra-plus/post-build.sh` | Genera `/etc/fw_env.config` dagli stessi dati. | Modifica |
| `external/board/lyra-plus/linux-mainline.config` | `mtdparts` in `CONFIG_CMDLINE` (variante initramfs). | Modifica |
| `external/board/lyra-plus/linux-mainline-flash.config` | `mtdparts` in `CONFIG_CMDLINE` (variante con root su flash). | Modifica |
| `external/configs/*_defconfig` (×4) | `BR2_PACKAGE_UBOOT_TOOLS=y`. | Modifica |
| `external/package/hello-lyra/src/main.go` | Stringa di fallback quando `/proc/mtd` non c'e'. | Modifica |
| `external/board/lyra-plus/genimage.cfg` | Commenti sul layout. | Modifica |
| `.github/workflows/checks.yml` | Glob degli script da controllare. | Modifica |
| `docs/BOARD-FACTS.md`, `docs/SCELTE-DI-PROGETTO.md`, `README.md` | Documentazione. | Modifica |

**Layout risultante** (`parameter.txt`, settori da 512 B):

| idx | nome | offset sett. | offset | size sett. | size |
|---|---|---|---|---|---|
| `mtd0` | `uboot` | `0x2000` | 4 MiB | `0x2000` | 4 MiB |
| `mtd1` | `boot` | `0x4000` | 8 MiB | `0x6000` | 12 MiB |
| `mtd2` | `env` | `0xa000` | 20 MiB | `0x400` | 512 KiB |
| `mtd3` | `env_r` | `0xa400` | 20.5 MiB | `0x400` | 512 KiB |
| `mtd4` | `rootfs` | `0x10000` | 32 MiB | `-` (grow) | 223.375 MiB |

---

## Scostamenti dalla spec, gia' decisi

Due cose sono emerse leggendo il codice e **non** stanno nella spec. Sono nel piano.

1. **`linux-mainline.config:197` va aggiornato, non solo `linux-mainline-flash.config:53`.** Entrambi cablano l'intero `mtdparts` in `CONFIG_CMDLINE`. La spec cita solo il secondo. Lasciare il primo com'e' e' un bug vero, non un'imprecisione: su `lyra_plus_mainline_initramfs_defconfig` le partizioni `env`/`env_r` non esisterebbero, `/dev/mtd2` sarebbe `rootfs`, e il `/etc/fw_env.config` generato (Task 6) farebbe scrivere `fw_setenv` **dentro la rootfs**. Vedi Task 7.
2. **`config ENV_OFFSET_REDUND` prende un `depends on ENVF || ENV_IS_IN_BLK_DEV`.** La spec dice solo "spostalo fuori dal blocco `if ENVF`". Spostarlo e basta lo renderebbe visibile a tutti i board Rockchip, con `default ENV_OFFSET`: per un board con `ENV_IS_IN_MMC` questo definirebbe `CONFIG_ENV_OFFSET_REDUND == CONFIG_ENV_OFFSET`, e `include/environment.h:63-67` accenderebbe `CONFIG_SYS_REDUNDAND_ENVIRONMENT` con **le due copie allo stesso offset**. Il `depends on` mantiene la visibilita' odierna per ENVF e aggiunge solo il nostro caso. Vedi Task 4.

---

## Task 1: `flash-layout.sh`, il parser unico

**Files:**
- Create: `external/board/lyra-plus/flash-layout.sh`
- Modify: `.github/workflows/checks.yml:65`, `:75`, `:81`

**Interfaces:**
- Consumes: niente.
- Produces:
  - `LYRA_ERASE_BLOCK=131072`, `LYRA_SECTOR=512` — variabili shell.
  - `flash_layout <parameter.txt>` — stampa una riga TAB-separata per partizione, in ordine: `<idx>\t<nome>\t<offset_byte>\t<size_byte|grow>`. Ritorna 1 se il file non e' leggibile o la riga `CMDLINE` manca o una voce non e' riconosciuta.
  - `flash_part <parameter.txt> <nome>` — stampa `<idx> <offset_byte> <size_byte|grow>` separati da spazio per la sola partizione richiesta. Ritorna 1 se non esiste.

- [ ] **Step 1: Scrivi il test che fallisce**

Crea `/tmp/test-flash-layout.sh` (file usa e getta, **non** va committato):

```bash
#!/usr/bin/env bash
set -euo pipefail
. external/board/lyra-plus/flash-layout.sh

fail=0
check() {
	local desc="$1" got="$2" want="$3"
	if [ "$got" = "$want" ]; then
		echo "ok   $desc"
	else
		echo "FAIL $desc"; echo "     got:  $got"; echo "     want: $want"; fail=1
	fi
}

P=external/board/lyra-plus/parameter.txt

check "erase block" "$LYRA_ERASE_BLOCK" "131072"
check "uboot"  "$(flash_part "$P" uboot)"  "0 4194304 4194304"
check "boot"   "$(flash_part "$P" boot)"   "1 8388608 12582912"
check "rootfs e' grow" "$(flash_part "$P" rootfs | cut -d' ' -f3)" "grow"

# Una partizione inesistente deve fallire, non stampare una riga vuota.
if flash_part "$P" nonesiste >/dev/null 2>&1; then
	echo "FAIL partizione inesistente dovrebbe fallire"; fail=1
else
	echo "ok   partizione inesistente fallisce"
fi

# Un parameter.txt senza CMDLINE deve fallire.
tmp="$(mktemp)"; echo "TYPE: GPT" > "$tmp"
if flash_layout "$tmp" >/dev/null 2>&1; then
	echo "FAIL CMDLINE mancante dovrebbe fallire"; fail=1
else
	echo "ok   CMDLINE mancante fallisce"
fi
rm -f "$tmp"

exit $fail
```

- [ ] **Step 2: Esegui il test per verificare che fallisca**

Run: `bash /tmp/test-flash-layout.sh`
Expected: FAIL — `flash-layout.sh: No such file or directory`

- [ ] **Step 3: Scrivi `flash-layout.sh`**

```bash
#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 Corley S.r.l.
#
# flash-layout.sh — parser unico di parameter.txt.
#
# Gli offset delle partizioni compaiono in tre posti indipendenti: la
# configurazione di U-Boot, parameter.txt e /etc/fw_env.config. Se divergono il
# sintomo e' subdolo (fw_setenv "riesce" e U-Boot legge altro), quindi
# parameter.txt e' la fonte unica e questo e' l'unico parser che la legge.
#
# La conversione settori (512 B) -> byte sta QUI e solo qui.
#
# Uso, sorgendolo:
#     . "$BOARD_DIR/flash-layout.sh"
#     flash_layout parameter.txt          # tutte le partizioni
#     flash_part   parameter.txt env      # una sola
#
# Uso, eseguendolo (stampa la tabella, comodo a mano):
#     ./flash-layout.sh parameter.txt

# Erase block della SPI NAND. NON e' ricavabile da parameter.txt: e' un fatto
# della board, misurato. Fonte: docs/BOARD-FACTS.md.
LYRA_ERASE_BLOCK=131072

# Unita' della riga CMDLINE di parameter.txt.
LYRA_SECTOR=512

# flash_layout <parameter.txt>
#
# Stampa una riga per partizione, TAB-separata, nell'ordine di dichiarazione:
#     <indice mtd>  <nome>  <offset in byte>  <size in byte, oppure "grow">
flash_layout() {
	local param="$1"
	local parts ent size off name idx=0

	if [ ! -r "$param" ]; then
		printf 'flash-layout: parameter.txt non leggibile: %s\n' "$param" >&2
		return 1
	fi

	# La riga e':
	#     CMDLINE:mtdparts=<mtd-id>:<size>@<off>(<nome>[:flag]),...
	# L'mtd-id e' vuoto in questo repository, ma il parser non ci conta.
	parts="$(sed -n 's/^CMDLINE:.*mtdparts=[^:]*:\(.*\)$/\1/p' "$param" | tail -1)"
	parts="${parts%%[[:space:]]}"
	if [ -z "$parts" ]; then
		printf 'flash-layout: nessuna riga CMDLINE con mtdparts= in %s\n' "$param" >&2
		return 1
	fi

	local IFS=,
	for ent in $parts; do
		if [[ ! "$ent" =~ ^(-|0x[0-9a-fA-F]+)@(0x[0-9a-fA-F]+)\(([^):]+) ]]; then
			printf 'flash-layout: voce mtdparts non riconosciuta: %s\n' "$ent" >&2
			return 1
		fi
		size="${BASH_REMATCH[1]}"
		off="${BASH_REMATCH[2]}"
		name="${BASH_REMATCH[3]}"

		if [ "$size" = - ]; then
			# "grow": la dimensione la calcola U-Boot a runtime, perche'
			# dipende da dove finisce la GPT di backup.
			printf '%d\t%s\t%d\tgrow\n' \
				"$idx" "$name" "$(( off * LYRA_SECTOR ))"
		else
			printf '%d\t%s\t%d\t%d\n' \
				"$idx" "$name" "$(( off * LYRA_SECTOR ))" \
				"$(( size * LYRA_SECTOR ))"
		fi
		idx=$(( idx + 1 ))
	done
}

# flash_part <parameter.txt> <nome>
#
# Stampa "<indice> <offset in byte> <size in byte|grow>" per una partizione.
# Ritorna 1 se quel nome non e' dichiarato.
flash_part() {
	flash_layout "$1" | awk -F'\t' -v n="$2" \
		'$2 == n { print $1, $3, $4; found = 1 } END { exit !found }'
}

# Eseguito direttamente: stampa la tabella.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
	param="${1:-}"
	if [ -z "$param" ]; then
		printf 'uso: %s <parameter.txt>\n' "$0" >&2
		exit 1
	fi
	printf '%-4s %-10s %14s %14s\n' idx nome offset size
	while IFS=$'\t' read -r idx name off size; do
		printf 'mtd%-1s %-10s %14s %14s\n' "$idx" "$name" "$off" "$size"
	done < <(flash_layout "$param")
fi
```

- [ ] **Step 4: Rendi eseguibile e ri-esegui il test**

```bash
chmod +x external/board/lyra-plus/flash-layout.sh
bash /tmp/test-flash-layout.sh
```
Expected: PASS — sei righe `ok`, exit 0.

- [ ] **Step 5: Controlla sintassi e shellcheck, come fa la CI**

```bash
bash -n external/board/lyra-plus/flash-layout.sh
shellcheck -S warning external/board/lyra-plus/flash-layout.sh
```
Expected: nessun output da entrambi.

- [ ] **Step 6: Estendi il glob della CI**

`flash-layout.sh` non corrisponde a `external/board/*/post-*.sh`. In `.github/workflows/checks.yml`, nel job `scripts`, sostituisci il pattern in **tutti e tre** i punti (righe 65, 75, 81) con `external/board/*/*.sh`.

Riga 65:
```yaml
          for f in setup.sh docs/*.sh external/board/*/*.sh; do
```

Riga 75:
```yaml
          shellcheck -S warning setup.sh docs/*.sh external/board/*/*.sh || true
```

Righe 81-82:
```yaml
          for f in setup.sh docs/*.sh external/board/*/*.sh \
                   external/board/*/rootfs_overlay/etc/init.d/S*; do
```

Il bit `+x` su un file sorgibile non serve, ma si sceglie di darglielo (Step 4) invece di aggiungere un'eccezione al controllo: un'eccezione e' una riga in piu' da capire per sempre, il bit `+x` non fa danno.

- [ ] **Step 7: Verifica che il glob prenda tutti e tre gli script**

Run: `ls external/board/*/*.sh`
Expected: esattamente `flash-layout.sh`, `post-build.sh`, `post-image.sh` sotto `external/board/lyra-plus/`.

- [ ] **Step 8: Commit**

```bash
git add external/board/lyra-plus/flash-layout.sh .github/workflows/checks.yml
git commit -m "board: un solo parser di parameter.txt, e la CI lo controlla

Gli offset delle partizioni finiranno in tre posti indipendenti (U-Boot,
parameter.txt, /etc/fw_env.config). Perche' non divergano serve prima una
fonte unica con un solo parser: flash-layout.sh legge parameter.txt e
converte settori in byte, e la conversione sta li' e solo li'.

Il glob della CI passa da post-*.sh a *.sh, altrimenti il file nuovo non
sarebbe ne' controllato con bash -n ne' passato a shellcheck."
```

---

## Task 2: `post-image.sh` usa il parser (refactor a comportamento invariato)

**Files:**
- Modify: `external/board/lyra-plus/post-image.sh:301-330`

**Interfaces:**
- Consumes: `flash_layout` da Task 1.
- Produces: niente di nuovo. Questo task **non deve cambiare nessun comportamento**: e' la sostituzione del blocco python inline con il parser condiviso.

- [ ] **Step 1: Registra l'output attuale come riferimento**

Prima di toccare qualsiasi cosa, cattura cosa stampa oggi il blocco python. Serve un `BINARIES_DIR` con dentro `parameter.txt` e almeno una `*.img`.

```bash
mkdir -p /tmp/binref
cp external/board/lyra-plus/parameter.txt /tmp/binref/
head -c 3000000 /dev/zero > /tmp/binref/uboot.img
head -c 3000000 /dev/zero > /tmp/binref/boot.img
head -c 3000000 /dev/zero > /tmp/binref/rootfs.img

python3 - /tmp/binref/parameter.txt /tmp/binref <<'PYEOF' | tee /tmp/sizecheck.before
import re, sys, os
param, bindir = sys.argv[1], sys.argv[2]
line = next(l for l in open(param) if l.startswith('CMDLINE'))
parts = line.split('mtdparts=', 1)[1].split(':', 1)[1].strip()
rc = 0
for ent in parts.split(','):
    m = re.match(r'(-|0x[0-9a-fA-F]+)@(0x[0-9a-fA-F]+)\(([^):]+)', ent)
    if not m:
        continue
    size, off, name = m.group(1), int(m.group(2), 16), m.group(3)
    img = os.path.join(bindir, name + '.img')
    if not os.path.exists(img):
        print(f"    {name:8} (nessuna {name}.img, salto)")
        continue
    fsz = os.path.getsize(img)
    if size == '-':
        print(f"    {name:8} {fsz/2**20:8.2f} MiB  -> partizione 'grow', nessun limite fisso")
        continue
    lim = int(size, 16) * 512
    ok = 'OK' if fsz <= lim else 'TROPPO GRANDE'
    print(f"    {name:8} {fsz/2**20:8.2f} MiB / {lim/2**20:8.2f} MiB  {ok}")
    if fsz > lim:
        rc = 1
sys.exit(rc)
PYEOF
echo "exit=$?"
```
Expected: tre righe, tutte `OK` o `grow`, `exit=0`.

- [ ] **Step 2: Scrivi il test che confronta vecchio e nuovo**

Crea `/tmp/test-sizecheck.sh` (usa e getta):

```bash
#!/usr/bin/env bash
set -uo pipefail
. external/board/lyra-plus/flash-layout.sh

BINARIES_DIR=/tmp/binref
mib() { awk -v b="$1" 'BEGIN { printf "%8.2f", b / 1048576 }'; }

layout="$(flash_layout "$BINARIES_DIR/parameter.txt")" || exit 1

rc=0
while IFS=$'\t' read -r _idx name off size; do
	img="$BINARIES_DIR/$name.img"
	if [ ! -f "$img" ]; then
		printf '    %-8s (nessuna %s.img, salto)\n' "$name" "$name"
		continue
	fi
	fsz="$(stat -c%s "$img")"
	if [ "$size" = grow ]; then
		printf "    %-8s %s MiB  -> partizione 'grow', nessun limite fisso\n" \
			"$name" "$(mib "$fsz")"
		continue
	fi
	if [ "$fsz" -le "$size" ]; then ok=OK; else ok="TROPPO GRANDE"; rc=1; fi
	printf '    %-8s %s MiB / %s MiB  %s\n' \
		"$name" "$(mib "$fsz")" "$(mib "$size")" "$ok"
done <<<"$layout"

exit $rc
```

Poi:
```bash
bash /tmp/test-sizecheck.sh > /tmp/sizecheck.after; echo "exit=$?"
diff -u /tmp/sizecheck.before /tmp/sizecheck.after && echo "IDENTICO"
```
Expected: `IDENTICO`, ed entrambi `exit=0`. Se il diff non e' vuoto, aggiusta la formattazione del nuovo finche' non lo e' — l'output deve restare identico byte per byte.

- [ ] **Step 3: Verifica che il test rilevi davvero una regressione**

```bash
head -c 5000000 /dev/zero > /tmp/binref/uboot.img   # 4.77 MiB in 4 MiB
bash /tmp/test-sizecheck.sh; echo "exit=$?"
```
Expected: la riga `uboot` dice `TROPPO GRANDE`, `exit=1`.

Ripristina: `head -c 3000000 /dev/zero > /tmp/binref/uboot.img`

- [ ] **Step 4: Applica la sostituzione in `post-image.sh`**

Ancora per contenuto, non per numero di riga. Aggiungi il source subito dopo la riga

```bash
TOPDIR="$(cd "$BOARD_DIR/../../.." && pwd)"
```

perche' li' `BOARD_DIR` e' gia' definito:

```bash
# Parser unico di parameter.txt: LYRA_ERASE_BLOCK, LYRA_SECTOR,
# flash_layout(), flash_part().
# shellcheck source=flash-layout.sh
. "$BOARD_DIR/flash-layout.sh"
```

Poi sostituisci **l'intero blocco** che va dalla riga

```bash
msg "verifica dimensioni contro parameter.txt"
```

fino alla riga `PYEOF` inclusa — cioe' il `msg`, l'invocazione `python3 - ... <<'PYEOF'`, tutto lo script python e il terminatore — con:

```bash
msg "verifica dimensioni contro parameter.txt"
# Controllo che l'SDK fa in mk-firmware.sh:52-64: ogni immagine deve entrare
# nella partizione dichiarata. Le partizioni senza immagine (env, env_r) non
# hanno niente da controllare e vengono saltate.
mib() { awk -v b="$1" 'BEGIN { printf "%8.2f", b / 1048576 }'; }

# flash_layout emette tutto o niente: se una voce di mtdparts non e'
# riconosciuta non stampa nessuna riga e fallisce. Il suo stato di uscita va
# raccolto QUI, perche' dentro una process substitution andrebbe perso e una
# partizione che sparisce dall'elenco non darebbe nessun sintomo.
layout="$(flash_layout "$BINARIES_DIR/parameter.txt")" \
	|| die "parameter.txt non parsabile (vedi l'errore qui sopra)"

size_rc=0
while IFS=$'\t' read -r _idx name off size; do
	img="$BINARIES_DIR/$name.img"
	if [ ! -f "$img" ]; then
		printf '    %-8s (nessuna %s.img, salto)\n' "$name" "$name"
		continue
	fi
	fsz="$(stat -c%s "$img")"
	if [ "$size" = grow ]; then
		printf "    %-8s %s MiB  -> partizione 'grow', nessun limite fisso\n" \
			"$name" "$(mib "$fsz")"
		continue
	fi
	if [ "$fsz" -le "$size" ]; then ok=OK; else ok="TROPPO GRANDE"; size_rc=1; fi
	printf '    %-8s %s MiB / %s MiB  %s\n' \
		"$name" "$(mib "$fsz")" "$(mib "$size")" "$ok"
done <<<"$layout"

[ "$size_rc" = 0 ] || die "una immagine non entra nella sua partizione (vedi sopra)"
```

Nota: `$off` non serve qui, ma la `read` deve consumare tutti e quattro i campi.

- [ ] **Step 5: Controlla sintassi e shellcheck**

```bash
bash -n external/board/lyra-plus/post-image.sh
shellcheck -S warning external/board/lyra-plus/post-image.sh
```
Expected: nessun output. Se shellcheck segnala `_idx`/`off` inutilizzati (SC2034), aggiungi `# shellcheck disable=SC2034` sopra il `while` con il motivo: i campi vanno letti tutti perche' la riga e' TAB-separata.

- [ ] **Step 6: Verifica che python non serva piu' per il layout**

Run: `grep -n "python3\|PYEOF" external/board/lyra-plus/post-image.sh`
Expected: nessun output. Il parser e' uno solo.

- [ ] **Step 7: Commit**

```bash
git add external/board/lyra-plus/post-image.sh
git commit -m "post-image: il check dimensioni usa flash-layout.sh

Sostituisce il blocco python inline che parsava mtdparts per conto suo.
L'output e' identico byte per byte, verificato con un diff contro quello
del blocco precedente: e' un refactor, non un cambio di comportamento.

Il valore non e' nelle righe risparmiate ma nel fatto che da qui in poi
esiste un solo posto che sa come si legge parameter.txt."
```

---

## Task 3: le due partizioni `env` in `parameter.txt`

**Files:**
- Modify: `external/board/lyra-plus/parameter.txt:12`

**Interfaces:**
- Consumes: `flash_layout` da Task 1.
- Produces: le partizioni `env` (mtd2, offset `0x1400000`, size `0x80000`) ed `env_r` (mtd3, offset `0x1480000`, size `0x80000`). `rootfs` diventa mtd4.

- [ ] **Step 1: Scrivi il test che fallisce**

Crea `/tmp/test-layout-env.sh` (usa e getta):

```bash
#!/usr/bin/env bash
set -uo pipefail
. external/board/lyra-plus/flash-layout.sh
P=external/board/lyra-plus/parameter.txt

fail=0
check() {
	if [ "$2" = "$3" ]; then echo "ok   $1"
	else echo "FAIL $1"; echo "     got:  $2"; echo "     want: $3"; fail=1; fi
}

check "env"    "$(flash_part "$P" env)"    "2 20971520 524288"
check "env_r"  "$(flash_part "$P" env_r)"  "3 21495808 524288"
check "rootfs e' mtd4" "$(flash_part "$P" rootfs | cut -d' ' -f1)" "4"
check "rootfs resta a 32 MiB" "$(flash_part "$P" rootfs | cut -d' ' -f2)" "33554432"
check "rootfs resta grow" "$(flash_part "$P" rootfs | cut -d' ' -f3)" "grow"

# env ed env_r non si sovrappongono e sono allineate all'erase block.
eoff=$(flash_part "$P" env   | cut -d' ' -f2)
esz=$( flash_part "$P" env   | cut -d' ' -f3)
roff=$(flash_part "$P" env_r | cut -d' ' -f2)
check "env_r inizia dopo env" "$(( roff >= eoff + esz ))" "1"
check "env allineata all'erase block"   "$(( eoff % LYRA_ERASE_BLOCK ))" "0"
check "env_r allineata all'erase block" "$(( roff % LYRA_ERASE_BLOCK ))" "0"
check "env e' 4 erase block" "$(( esz / LYRA_ERASE_BLOCK ))" "4"

exit $fail
```

- [ ] **Step 2: Esegui il test per verificare che fallisca**

Run: `bash /tmp/test-layout-env.sh`
Expected: FAIL — `env` ed `env_r` non esistono; `rootfs` e' ancora mtd2.

- [ ] **Step 3: Modifica `parameter.txt`**

Sostituisci la riga 12 con:

```
CMDLINE:mtdparts=:0x00002000@0x00002000(uboot),0x00006000@0x00004000(boot),0x00000400@0x0000a000(env),0x00000400@0x0000a400(env_r),-@0x00010000(rootfs:grow)
```

`env` e `env_r` stanno nel buco fra 20 e 32 MiB che esiste gia' nel `parameter.txt` vendor. `rootfs` resta l'ultima e resta `grow`: geometria UBI, conteggio PEB e `MAXLEBCNT=8456` non cambiano.

- [ ] **Step 4: Esegui il test per verificare che passi**

Run: `bash /tmp/test-layout-env.sh`
Expected: PASS — nove righe `ok`, exit 0.

- [ ] **Step 5: Verifica che il check dimensioni salti le partizioni senza immagine**

```bash
cp external/board/lyra-plus/parameter.txt /tmp/binref/
bash /tmp/test-sizecheck.sh; echo "exit=$?"
```
Expected: cinque righe; `env` ed `env_r` dicono `(nessuna env.img, salto)` e `(nessuna env_r.img, salto)`; `exit=0`.

- [ ] **Step 6: Guarda la tabella a occhio**

Run: `external/board/lyra-plus/flash-layout.sh external/board/lyra-plus/parameter.txt`

Expected: una riga di intestazione piu' cinque righe, `mtd0` … `mtd4`, con i
nomi `uboot boot env env_r rootfs` e i valori `4194304/4194304`,
`8388608/12582912`, `20971520/524288`, `21495808/524288`, `33554432/grow`.
**Non** verificare l'allineamento delle colonne: la formattazione non e' un
requisito e non c'e' niente che la fissi.

Controllo meccanico della forma:
```bash
external/board/lyra-plus/flash-layout.sh external/board/lyra-plus/parameter.txt \
	| awk 'NR>1 { print $1, $2, $3, $4 }'
```
Expected:
```
mtd0 uboot 4194304 4194304
mtd1 boot 8388608 12582912
mtd2 env 20971520 524288
mtd3 env_r 21495808 524288
mtd4 rootfs 33554432 grow
```

- [ ] **Step 7: Commit**

```bash
git add external/board/lyra-plus/parameter.txt
git commit -m "parameter: due partizioni per l'env, nel buco a 20 MiB

env ed env_r, 512 KiB ciascuna (4 erase block: uno per la copia, tre di
riserva per lo skip dei blocchi guasti). Una partizione per copia, non una
sola da 1 MiB con due offset interni: con una sola partizione U-Boot
rimappa i blocchi guasti sull'intera partizione mentre fw_env salta entro
il numero di settori della singola copia, e le due semantiche divergono in
silenzio.

Il buco fra 20 e 32 MiB c'era gia' nel parameter.txt vendor. Metterci
l'env tiene rootfs ultima e 'grow', quindi la geometria UBI e MAXLEBCNT
non cambiano. Il prezzo e' che rootfs passa da mtd2 a mtd4.

Cambiare parameter.txt riscrive la GPT: serve un riflash completo."
```

---

## Task 4: U-Boot — backend env persistente e ridondante

**Files:**
- Modify: `external/board/lyra-plus/uboot.config`
- Create: `external/board/lyra-plus/patches/uboot/0005-env-make-ENV_OFFSET_REDUND-available-outside-ENVF.patch`
- Create: `external/board/lyra-plus/patches/uboot/0006-environment-derive-SYS_REDUNDAND_ENVIRONMENT-for-BLK.patch`

**Interfaces:**
- Consumes: gli offset di Task 3.
- Produces: in `$(UBOOT_DIR)/include/generated/autoconf.h` compaiono `CONFIG_ENV_IS_IN_BLK_DEV 1`, `CONFIG_ENV_OFFSET 0x1400000`, `CONFIG_ENV_OFFSET_REDUND 0x1480000`, `CONFIG_ENV_SIZE 0x20000`. Task 5 li legge da li'.

**Contesto verificato prima di iniziare:**
- `CONFIG_BLK=y` e nessun `CONFIG_CHAIN_OF_TRUST`, quindi `ENV_IS_IN_BLK_DEV` e' selezionabile (`env/Kconfig:361-363`).
- `CONFIG_SYS_MMC_ENV_DEV` e' gia' `0` in `include/configs/evb_rk3506.h:20`; `env_blk.c:39` lo richiede.
- `env_blk_save()` chiama `blk_dwrite()` senza `BLK_MTD_CONT_WRITE`, quindi `mtd_dwrite()` prende il ramo read-modify-write allineato all'erase block (`drivers/mtd/mtd_blk.c:607-635`), che cancella e salta i blocchi guasti.
- `get_env_addr()` (`env/env_blk.c:21-35`) usa `CONFIG_ENV_OFFSET` come offset **assoluto dall'inizio del device**, non dall'inizio di una partizione. Per questo il fragment porta `0x1400000` e non `0x0`.

- [ ] **Step 1: Scrivi il test che fallisce**

Crea `/tmp/test-uboot-env.sh` (usa e getta):

```bash
#!/usr/bin/env bash
set -uo pipefail
U="$(ls -d output/build/uboot-* 2>/dev/null | head -1)"
[ -n "$U" ] || { echo "FAIL: nessun output/build/uboot-*"; exit 1; }
A="$U/include/generated/autoconf.h"
NM="$(ls output/host/bin/*-linux-*-nm 2>/dev/null | head -1)"

fail=0
def() { sed -n "s/^#define $1 \\(.*\\)\$/\\1/p" "$A" | tail -1; }
check() {
	if [ "$2" = "$3" ]; then echo "ok   $1"
	else echo "FAIL $1"; echo "     got:  '$2'"; echo "     want: '$3'"; fail=1; fi
}

check "backend BLK_DEV attivo"   "$(def CONFIG_ENV_IS_IN_BLK_DEV)" "1"
check "ENV_IS_NOWHERE spento"    "$(def CONFIG_ENV_IS_NOWHERE)"    ""
check "ENV_OFFSET"               "$(def CONFIG_ENV_OFFSET)"        "0x1400000"
check "ENV_OFFSET_REDUND"        "$(def CONFIG_ENV_OFFSET_REDUND)" "0x1480000"
check "ENV_SIZE"                 "$(def CONFIG_ENV_SIZE)"          "0x20000"

# La ridondanza non e' un simbolo Kconfig: e' un define derivato in
# include/environment.h. La prova che c'e' davvero e' che env/common.c abbia
# compilato env_import_redund(), che sta sotto #ifdef
# CONFIG_SYS_REDUNDAND_ENVIRONMENT (env/common.c:214).
if [ -n "$NM" ] && [ -f "$U/env/common.o" ]; then
	if "$NM" "$U/env/common.o" | grep -q ' T env_import_redund'; then
		echo "ok   env_import_redund compilata"
	else
		echo "FAIL env_import_redund NON compilata: la ridondanza non esiste"
		fail=1
	fi
else
	echo "FAIL nm o env/common.o non trovati"; fail=1
fi

[ -f "$U/env/env_blk.o" ] && echo "ok   env_blk.o costruito" \
	|| { echo "FAIL env_blk.o non costruito"; fail=1; }

exit $fail
```

- [ ] **Step 2: Esegui il test sull'albero attuale per vederlo fallire**

Run: `bash /tmp/test-uboot-env.sh`
Expected: FAIL su tutto. Oggi `autoconf.h` dice `CONFIG_ENV_IS_NOWHERE 1` e `CONFIG_ENV_SIZE 0x8000`, in `env/` c'e' `nowhere.o` e non `env_blk.o`, e `nm env/common.o` mostra solo `T env_import`.

- [ ] **Step 3: Scrivi il fragment `uboot.config`**

Il file oggi e' vuoto di proposito e il commento spiega perche'. Il commento **va riscritto, non cancellato**: la parte su `CONFIG_SPL_FIT_IMAGE_KB` e sull'AMP resta valida. Il file diventa:

```
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 Corley S.r.l.
# Fragment applicato sopra configs/rk3506_luckfox_defconfig
# (U-Boot 2017.09 Rockchip, SHA 1625f78b).
#
# Il defconfig vendor e' gia' corretto per Lyra Plus su SPI NAND:
#   CONFIG_ROCKCHIP_RK3506=y        CONFIG_DEFAULT_DEVICE_TREE="rk3506-luckfox"
#   CONFIG_SPL_OPTEE=y              CONFIG_ROCKCHIP_FIT_IMAGE_PACK=y
#   CONFIG_MTD_SPI_NAND=y           CONFIG_ROCKCHIP_SFC=y
#   CONFIG_DEBUG_UART_BASE=0xff0a0000  (stessa UART del fiq-debugger kernel)
#   CONFIG_SPL_FIT_IMAGE_KB=2048    CONFIG_SPL_FIT_IMAGE_MULTIPLE=2
# Gli ultimi due determinano uboot.img = 2 copie del FIT paddate a 2 MiB
# = 4 MiB esatti, cioe' la dimensione della partizione `uboot`.
# Toccarli senza aggiornare parameter.txt rompe il flash.
#
# NON aggiungere qui il fragment "rk-amp" del defconfig locale dell'SDK:
# l'AMP e' fuori scope (vedi docs/BOARD-FACTS.md, TODO-8).
#
# ---------------------------------------------------------------------------
# Environment persistente e ridondante
# ---------------------------------------------------------------------------
# Il defconfig vendor lascia ENV_IS_NOWHERE: l'ambiente vive in RAM e saveenv
# non persiste. Qui si sceglie ENV_IS_IN_BLK_DEV (env/env_blk.c) e non ENVF,
# che pure e' la strada vendor battuta (20 defconfig): envf_save() esporta solo
# le variabili di una whitelist compile-time, CONFIG_ENVF_LIST (env/envf.c:306,
# env/Kconfig:457), quindi `setenv pippo 1; saveenv` non persisterebbe. Una
# lista chiusa decisa a compile time e' l'opposto di un ambiente.
#
# ENV_IS_NOWHERE va spento ESPLICITAMENTE: e' una choice Kconfig e Buildroot
# fonde questo file con merge_config.sh, che non disattiva da solo l'opzione
# precedente della choice.
#
# Gli offset sono ASSOLUTI dall'inizio del chip, non relativi a una partizione:
# env_blk.c usa rockchip_get_bootdev(), cioe' il device intero, e get_env_addr()
# (env/env_blk.c:21-35) passa CONFIG_ENV_OFFSET dritto a blk_dread/blk_dwrite.
# Devono combaciare con le partizioni env ed env_r di parameter.txt, e
# post-image.sh fa fallire la build se divergono.
#
#   0x1400000 = 20   MiB = partizione `env`    (0x0000a000 settori)
#   0x1480000 = 20.5 MiB = partizione `env_r`  (0x0000a400 settori)
#   0x20000   = 128  KiB = un erase block
#
# ENV_SIZE e' un erase block esatto, non il default 0x8000: cosi' non c'e'
# semantica di scrittura parziale ne' da parte di U-Boot ne' di fw_setenv.
# Costo: 128 KiB x 2 buffer in RAM al caricamento, su CONFIG_SYS_MALLOC_LEN
# di 16 MiB.
#
# ENV_OFFSET_REDUND e CONFIG_SYS_REDUNDAND_ENVIRONMENT hanno bisogno delle
# patch 0005 e 0006: senza, il primo non e' settabile e il secondo non viene
# derivato, e la ridondanza sparisce IN SILENZIO (env_t senza il byte flags,
# env_import_redund() non compilata).
# CONFIG_ENV_IS_NOWHERE is not set
CONFIG_ENV_IS_IN_BLK_DEV=y
CONFIG_ENV_SIZE=0x20000
CONFIG_ENV_OFFSET=0x1400000
CONFIG_ENV_OFFSET_REDUND=0x1480000
```

- [ ] **Step 4: Ricostruisci U-Boot e osserva il fallimento parziale**

```bash
make lyra_plus_defconfig
make uboot-reconfigure
bash /tmp/test-uboot-env.sh
```
Expected: `ENV_IS_IN_BLK_DEV`, `ENV_IS_NOWHERE`, `ENV_OFFSET`, `ENV_SIZE` ed `env_blk.o` passano; **`ENV_OFFSET_REDUND` e `env_import_redund` falliscono**. `merge_config.sh` ha stampato un avviso perche' il simbolo non e' settabile: `config ENV_OFFSET_REDUND` sta dentro `if ENVF` (`env/Kconfig:526`).

Questo e' esattamente il fallimento silenzioso che il piano deve rendere impossibile: la build **riesce**, e la ridondanza non c'e'.

- [ ] **Step 5: Scrivi la patch 0005 (env/Kconfig)**

Ricava il diff da una copia pristina, perche' l'albero estratto da Buildroot non e' un repo git:

```bash
U="$(ls -d output/build/uboot-* | head -1)"
mkdir -p /tmp/p/a/env /tmp/p/b/env
cp "$U/env/Kconfig" /tmp/p/a/env/Kconfig
cp "$U/env/Kconfig" /tmp/p/b/env/Kconfig
```

Modifica `/tmp/p/b/env/Kconfig`: sposta `config ENV_OFFSET_REDUND` **fuori** da `if ENVF` e dagli il `depends on`. Da:

```
if ENVF
config ENV_OFFSET_REDUND
	hex "Environment redundant(backup) offset"
	default ENV_OFFSET
	help
	  Redundant(backup) offset from the start of the device (or partition),
	  this size must be ENV_SIZE.

if CMD_NAND || MTD_SPI_NAND
```

a:

```
config ENV_OFFSET_REDUND
	hex "Environment redundant(backup) offset"
	depends on ENVF || ENV_IS_IN_BLK_DEV
	default ENV_OFFSET
	help
	  Redundant(backup) offset from the start of the device (or partition),
	  this size must be ENV_SIZE.

if ENVF

if CMD_NAND || MTD_SPI_NAND
```

I simboli `ENV_NAND_*` e `ENV_NOR_*` **restano dentro `if ENVF`**: servono solo a ENVF.

Genera la patch:

```bash
( cd /tmp/p && diff -u a/env/Kconfig b/env/Kconfig ) > /tmp/0005.diff
cat > external/board/lyra-plus/patches/uboot/0005-env-make-ENV_OFFSET_REDUND-available-outside-ENVF.patch <<'EOF'
From: rk3506-framework <walter.dalmut@corley.it>
Subject: [PATCH 5/6] env: make ENV_OFFSET_REDUND settable outside ENVF

Su ARCH_ROCKCHIP `config ENV_OFFSET_REDUND` sta dentro il blocco `if ENVF`,
quindi con qualunque altro backend non e' settabile da un fragment Kconfig:
merge_config.sh avvisa e va avanti, e l'ambiente resta a copia singola.

Serve per usare ENV_IS_IN_BLK_DEV (env/env_blk.c) con due copie: quel
backend legge CONFIG_ENV_OFFSET_REDUND in get_env_addr() e alterna le due
copie in env_blk_save(), ma solo se il simbolo esiste.

Il simbolo esce da `if ENVF` e prende `depends on ENVF || ENV_IS_IN_BLK_DEV`
invece di restare senza vincoli. Senza il depends on sarebbe visibile a
tutti i board Rockchip con il suo `default ENV_OFFSET`, e per un board con
ENV_IS_IN_MMC questo definirebbe CONFIG_ENV_OFFSET_REDUND uguale a
CONFIG_ENV_OFFSET: include/environment.h:63-67 accenderebbe
CONFIG_SYS_REDUNDAND_ENVIRONMENT con le due copie allo STESSO offset, cioe'
una ridondanza finta. Con il depends on la visibilita' per ENVF resta
identica a oggi.

ENV_NAND_* e ENV_NOR_* restano dentro `if ENVF`: li usa solo ENVF.

EOF
cat /tmp/0005.diff >> external/board/lyra-plus/patches/uboot/0005-env-make-ENV_OFFSET_REDUND-available-outside-ENVF.patch
```

- [ ] **Step 6: Scrivi la patch 0006 (include/environment.h)**

```bash
U="$(ls -d output/build/uboot-* | head -1)"
mkdir -p /tmp/p/a/include /tmp/p/b/include
cp "$U/include/environment.h" /tmp/p/a/include/environment.h
cp "$U/include/environment.h" /tmp/p/b/include/environment.h
```

In `/tmp/p/b/include/environment.h`, subito dopo `#endif /* CONFIG_ENV_IS_IN_UBI */` (riga 105) e prima del commento `/* Embedded env is only supported for some flash types */`, inserisci una riga vuota e poi:

```c
#if defined(CONFIG_ENV_IS_IN_BLK_DEV)
# ifdef CONFIG_ENV_OFFSET_REDUND
#  define CONFIG_SYS_REDUNDAND_ENVIRONMENT
# endif
# ifndef CONFIG_ENV_SIZE
#  error "Need to define CONFIG_ENV_SIZE when using CONFIG_ENV_IS_IN_BLK_DEV"
# endif
#endif /* CONFIG_ENV_IS_IN_BLK_DEV */
```

Genera la patch:

```bash
( cd /tmp/p && diff -u a/include/environment.h b/include/environment.h ) > /tmp/0006.diff
cat > external/board/lyra-plus/patches/uboot/0006-environment-derive-SYS_REDUNDAND_ENVIRONMENT-for-BLK.patch <<'EOF'
From: rk3506-framework <walter.dalmut@corley.it>
Subject: [PATCH 6/6] environment: derive SYS_REDUNDAND_ENVIRONMENT for BLK_DEV

include/environment.h deriva CONFIG_SYS_REDUNDAND_ENVIRONMENT da
CONFIG_ENV_OFFSET_REDUND per ENV_IS_IN_FLASH, _IN_MMC, _IN_NAND e _IN_UBI,
ma non ha un blocco per ENV_IS_IN_BLK_DEV.

Senza quel define la ridondanza sparisce in silenzio, e in due punti:
env_t non ha il byte `flags` (include/environment.h:165-171), quindi il
serial number con cui si decide quale copia e' piu' recente non viene
nemmeno scritto; e env_import_redund() non viene compilata (env/common.c:214).
env_blk.c compila lo stesso, perche' i suoi blocchi sono sotto
#ifdef CONFIG_ENV_OFFSET_REDUND, e si ottiene un ambiente che si crede
ridondante e non lo e'.

Si aggiunge il blocco mancante nella stessa forma degli altri backend,
incluso il controllo su CONFIG_ENV_SIZE.

EOF
cat /tmp/0006.diff >> external/board/lyra-plus/patches/uboot/0006-environment-derive-SYS_REDUNDAND_ENVIRONMENT-for-BLK.patch
```

- [ ] **Step 7: Ricostruisci da zero e verifica che le patch si applichino**

Le patch si applicano all'estrazione, quindi serve ripartire dal sorgente:

```bash
rm -rf output/build/uboot-*
make uboot 2>&1 | tail -40
```
`make uboot`, non `uboot-rebuild`: cancellata la build dir non ci sono piu' gli
stamp su cui `-rebuild` si appoggia, e comunque qui serve proprio il percorso
che ri-estrae e ri-applica le patch.

Expected: nella traccia compaiono `Applying 0005-...patch` e `Applying 0006-...patch` senza `FAILED`. Verifica anche:
```bash
cat output/build/uboot-*/.applied_patches_list
```
Expected: sei righe, `0001` … `0006`.

- [ ] **Step 8: Esegui il test per verificare che passi**

Run: `bash /tmp/test-uboot-env.sh`
Expected: PASS — sette righe `ok`, exit 0. In particolare `nm env/common.o` mostra ora `T env_import_redund`, che e' la prova a livello di compilazione che la ridondanza esiste davvero.

- [ ] **Step 9: Verifica che `uboot.img` entri ancora nei 4 MiB**

`ENV_SIZE` piu' grande non tocca la dimensione del binario, ma va confermato invece che assunto:

```bash
ls -l output/build/uboot-*/uboot.img
```
Expected: 4194304 byte (`CONFIG_SPL_FIT_IMAGE_KB=2048` × `MULTIPLE=2`). Se il file non c'e', e' perche' `fit.sh` gira in `post-image.sh`: in quel caso rimanda questo controllo a Task 10 e annotalo.

- [ ] **Step 10: Commit**

```bash
git add external/board/lyra-plus/uboot.config \
        external/board/lyra-plus/patches/uboot/0005-*.patch \
        external/board/lyra-plus/patches/uboot/0006-*.patch
git commit -m "uboot: env persistente e ridondante su due partizioni MTD

Il defconfig vendor lasciava ENV_IS_NOWHERE: l'ambiente viveva in RAM e
saveenv non persisteva. Non era una lacuna legata a un update system, era
una lacuna del bring-up, e pesava su qualunque progetto nato da questo
template: MAC address, numero di serie, bootargs modificabili senza
riflashare.

Backend ENV_IS_IN_BLK_DEV e non ENVF: envf_save() salva solo una whitelist
compile-time, quindi non e' un ambiente. Due copie a 20 e 20.5 MiB, offset
assoluti perche' env_blk.c lavora sul device intero.

Le due patch a U-Boot colmano due buchi che insieme farebbero sparire la
ridondanza senza un messaggio: ENV_OFFSET_REDUND non settabile fuori da
ENVF, e SYS_REDUNDAND_ENVIRONMENT non derivato per BLK_DEV. Si patchano i
file core invece del board header per tenere i tre valori numerici dentro
uboot.config, dove si leggono.

Verificato che env/common.o ora esporta env_import_redund, che sotto
CONFIG_SYS_REDUNDAND_ENVIRONMENT e' la prova che la ridondanza c'e'."
```

---

## Task 5: `post-image.sh` fa fallire la build se i due lati divergono

**Files:**
- Modify: `external/board/lyra-plus/post-image.sh` (nuovo blocco nella sezione 1, subito dopo il `die` che valida `UBOOT_DIR`)

**Interfaces:**
- Consumes: `flash_part` da Task 1; le partizioni di Task 3; i simboli in `autoconf.h` da Task 4.
- Produces: la build muore con un messaggio esplicito se `uboot.config` e `parameter.txt` non dicono la stessa cosa. Nessuna interfaccia per i task successivi.

**Perche' si verifica invece di generare:** Buildroot legge `BR2_TARGET_UBOOT_CONFIG_FRAGMENT_FILES` prima che qualunque script di questo repository possa girare. Generare il fragment richiederebbe un hook pre-build fragile. Una build che muore ottiene lo stesso risultato — la divergenza non arriva sulla board — con molto meno macchinario.

**Perche' si legge `autoconf.h` e non `uboot.config`:** l'header generato e' il valore *effettivo*, e cattura anche un valore che arrivasse da un default Kconfig o da un board header invece che dal fragment.

- [ ] **Step 1: Scrivi il test che fallisce**

Il test e' la build stessa: si perturba `uboot.config` e ci si aspetta che muoia.

```bash
cp external/board/lyra-plus/uboot.config /tmp/uboot.config.orig
sed -i 's/^CONFIG_ENV_OFFSET=0x1400000$/CONFIG_ENV_OFFSET=0x1400020/' \
	external/board/lyra-plus/uboot.config
make uboot-reconfigure
make 2>&1 | tail -20
echo "exit=${PIPESTATUS[0]}"
```
Expected **oggi**: la build **NON** muore. Nessuno confronta i due lati, e una board flashata con questo `update.img` avrebbe l'env a un offset che non e' quello della partizione.

Ripristina prima di proseguire: `cp /tmp/uboot.config.orig external/board/lyra-plus/uboot.config`

- [ ] **Step 2: Aggiungi il blocco di verifica**

Ancora per contenuto: Task 2 ha gia' spostato le righe di questo file, quindi non
usare numeri di riga. Inserisci subito dopo

```bash
[ -n "$UBOOT_DIR" ] || die "directory di build di U-Boot non trovata sotto $BUILD_DIR"
```

il blocco:

```bash
# ---------------------------------------------------------------------------
# 1a. Coerenza degli offset dell'environment
# ---------------------------------------------------------------------------
# Gli offset dell'env sono dichiarati in due posti indipendenti: uboot.config
# (che diventa autoconf.h) e parameter.txt (che diventa la GPT, e da li'
# mtdparts). Il terzo posto, /etc/fw_env.config, e' GENERATO da post-build.sh
# a partire da parameter.txt, quindi non puo' divergere.
#
# Se i due che restano divergono il sintomo e' subdolo: fw_setenv "riesce" e
# U-Boot legge un'altra area. Meglio morire qui.
#
# Si legge include/generated/autoconf.h e non uboot.config perche' l'header
# generato e' il valore EFFETTIVO: cattura anche un valore che arrivasse da un
# default Kconfig o da include/configs/evb_rk3506.h invece che dal fragment.
UBOOT_AUTOCONF="$UBOOT_DIR/include/generated/autoconf.h"
uboot_def() { sed -n "s/^#define $1 \\(.*\\)\$/\\1/p" "$UBOOT_AUTOCONF" | tail -1; }

if [ ! -r "$UBOOT_AUTOCONF" ]; then
	warn "autoconf.h di U-Boot non leggibile, salto la verifica degli offset env:
    $UBOOT_AUTOCONF"
elif [ -z "$(uboot_def CONFIG_ENV_IS_IN_BLK_DEV)" ]; then
	# Un fork che toglie il fragment deve poter costruire lo stesso.
	warn "U-Boot non ha CONFIG_ENV_IS_IN_BLK_DEV: l'environment NON e'
    persistente, saveenv non scrivera' da nessuna parte. Salto la verifica
    degli offset."
else
	msg "verifica offset env: uboot.config <-> parameter.txt"

	env_off="$(uboot_def CONFIG_ENV_OFFSET)"
	env_red="$(uboot_def CONFIG_ENV_OFFSET_REDUND)"
	env_size="$(uboot_def CONFIG_ENV_SIZE)"

	[ -n "$env_off" ]  || die "CONFIG_ENV_OFFSET assente da autoconf.h"
	[ -n "$env_size" ] || die "CONFIG_ENV_SIZE assente da autoconf.h"
	[ -n "$env_red" ]  || die "CONFIG_ENV_OFFSET_REDUND assente da autoconf.h.
    L'env sarebbe a copia singola, e in silenzio: env_t resterebbe senza il
    byte 'flags' e env_import_redund() non verrebbe compilata.
    Quasi sempre significa che le patch 0005/0006 a U-Boot non si sono
    applicate. Controlla output/build/uboot-*/.applied_patches_list."

	env_off=$(( env_off )); env_red=$(( env_red )); env_size=$(( env_size ))

	p_env="$(flash_part "$BOARD_DIR/parameter.txt" env)" \
		|| die "parameter.txt non dichiara la partizione 'env'"
	p_red="$(flash_part "$BOARD_DIR/parameter.txt" env_r)" \
		|| die "parameter.txt non dichiara la partizione 'env_r'"

	read -r _ p_env_off p_env_size <<<"$p_env"
	read -r _ p_red_off p_red_size <<<"$p_red"

	[ "$env_off" = "$p_env_off" ] || die "CONFIG_ENV_OFFSET non e' l'offset della partizione 'env':
    uboot.config    CONFIG_ENV_OFFSET  = $env_off
    parameter.txt   partizione 'env'   @ $p_env_off
    differenza      $(( env_off - p_env_off )) byte
    parameter.txt e' la fonte: allinea uboot.config."

	[ "$env_red" = "$p_red_off" ] || die "CONFIG_ENV_OFFSET_REDUND non e' l'offset della partizione 'env_r':
    uboot.config    CONFIG_ENV_OFFSET_REDUND = $env_red
    parameter.txt   partizione 'env_r'       @ $p_red_off
    differenza      $(( env_red - p_red_off )) byte
    parameter.txt e' la fonte: allinea uboot.config."

	# Sanita': le due copie devono stare in partizioni diverse, ognuna deve
	# entrarci, e ogni offset deve cadere su un confine di erase block —
	# altrimenti mtd_map_write() cancella un blocco che contiene altro.
	[ "$env_off" != "$env_red" ] \
		|| die "CONFIG_ENV_OFFSET e CONFIG_ENV_OFFSET_REDUND coincidono ($env_off):
    non e' ridondanza, e' una copia sola scritta due volte."

	[ "$env_size" -le "$p_env_size" ] \
		|| die "CONFIG_ENV_SIZE ($env_size) e' piu' grande della partizione 'env' ($p_env_size)."
	[ "$env_size" -le "$p_red_size" ] \
		|| die "CONFIG_ENV_SIZE ($env_size) e' piu' grande della partizione 'env_r' ($p_red_size)."

	[ $(( env_off % LYRA_ERASE_BLOCK )) = 0 ] \
		|| die "CONFIG_ENV_OFFSET ($env_off) non e' allineato all'erase block ($LYRA_ERASE_BLOCK)."
	[ $(( env_red % LYRA_ERASE_BLOCK )) = 0 ] \
		|| die "CONFIG_ENV_OFFSET_REDUND ($env_red) non e' allineato all'erase block ($LYRA_ERASE_BLOCK)."
	[ $(( env_size % LYRA_ERASE_BLOCK )) = 0 ] \
		|| die "CONFIG_ENV_SIZE ($env_size) non e' un multiplo dell'erase block ($LYRA_ERASE_BLOCK)."

	printf '    env    @ %-10s size %-8s (partizione %s B)\n' \
		"$env_off" "$env_size" "$p_env_size"
	printf '    env_r  @ %-10s size %-8s (partizione %s B)\n' \
		"$env_red" "$env_size" "$p_red_size"
fi
```

- [ ] **Step 3: Verifica sintassi e shellcheck**

```bash
bash -n external/board/lyra-plus/post-image.sh
shellcheck -S warning external/board/lyra-plus/post-image.sh
```
Expected: nessun output.

- [ ] **Step 4: Esegui il test — ora la build deve morire**

```bash
sed -i 's/^CONFIG_ENV_OFFSET=0x1400000$/CONFIG_ENV_OFFSET=0x1400020/' \
	external/board/lyra-plus/uboot.config
make uboot-reconfigure
make 2>&1 | tail -20; echo "exit=${PIPESTATUS[0]}"
```
Expected: la build muore con
```
*** lyra-plus: CONFIG_ENV_OFFSET non e' l'offset della partizione 'env':
    uboot.config    CONFIG_ENV_OFFSET  = 20971552
    parameter.txt   partizione 'env'   @ 20971520
    differenza      32 byte
```
e exit diverso da 0.

- [ ] **Step 5: Verifica anche il caso non allineato**

```bash
sed -i 's/^CONFIG_ENV_OFFSET=0x1400020$/CONFIG_ENV_OFFSET=0x1400000/' \
	external/board/lyra-plus/uboot.config
sed -i 's/^CONFIG_ENV_SIZE=0x20000$/CONFIG_ENV_SIZE=0x8000/' \
	external/board/lyra-plus/uboot.config
make uboot-reconfigure && make 2>&1 | tail -10
```
Expected: muore con `CONFIG_ENV_SIZE (32768) non e' un multiplo dell'erase block (131072)`.

- [ ] **Step 6: Ripristina e verifica che la build passi**

```bash
cp /tmp/uboot.config.orig external/board/lyra-plus/uboot.config
git diff --stat external/board/lyra-plus/uboot.config   # deve essere vuoto
make uboot-reconfigure && make 2>&1 | tail -30
```
Expected: la build arriva in fondo, e fra i messaggi compare
```
>>> lyra-plus: verifica offset env: uboot.config <-> parameter.txt
    env    @ 20971520   size 131072  (partizione 524288 B)
    env_r  @ 21495808   size 131072  (partizione 524288 B)
```

- [ ] **Step 7: Commit**

```bash
git add external/board/lyra-plus/post-image.sh
git commit -m "post-image: la build muore se gli offset env divergono

Gli offset dell'env stanno in due posti indipendenti — uboot.config, che
diventa autoconf.h, e parameter.txt, che diventa la GPT. Se divergono
fw_setenv 'riesce' e U-Boot legge un'altra area: nessun errore, solo un
ambiente che non torna. Meglio non far uscire dalla build un update.img
fatto cosi'.

Si legge include/generated/autoconf.h e non uboot.config perche' l'header
generato e' il valore effettivo, e cattura anche un valore arrivato da un
default Kconfig o dal board header.

Un fork che toglie il fragment continua a costruire: senza
CONFIG_ENV_IS_IN_BLK_DEV lo script avvisa che l'env non e' persistente e
prosegue."
```

---

## Task 6: `/etc/fw_env.config` generato, e `uboot-tools` sul target

**Files:**
- Modify: `external/board/lyra-plus/post-build.sh`
- Modify: `external/configs/lyra_plus_defconfig`, `lyra_plus_initramfs_defconfig`, `lyra_plus_mainline_defconfig`, `lyra_plus_mainline_initramfs_defconfig`

**Interfaces:**
- Consumes: `flash_layout`/`flash_part`/`LYRA_ERASE_BLOCK` da Task 1; le partizioni di Task 3; `CONFIG_ENV_SIZE` di Task 4.
- Produces: `$TARGET_DIR/etc/fw_env.config` con una riga per copia.

**Nota su `uboot-tools`:** `BR2_PACKAGE_UBOOT_TOOLS_FWPRINTENV` e' gia' `default y` (`buildroot/package/uboot-tools/Config.in:92`), quindi non comparira' nei defconfig dopo `savedefconfig`: basta `BR2_PACKAGE_UBOOT_TOOLS=y`. Il package e' alla 2025.10 (`uboot-tools.mk:7`), indipendente dalla 2017.09 vendor; il formato dell'env — CRC32, byte `flags`, coppie `chiave=valore` NUL-terminate — non e' cambiato.

- [ ] **Step 1: Aggiungi `BR2_PACKAGE_UBOOT_TOOLS=y` a tutti e quattro i defconfig**

```bash
for d in external/configs/*_defconfig; do
	grep -q '^BR2_PACKAGE_UBOOT_TOOLS=y$' "$d" || echo 'BR2_PACKAGE_UBOOT_TOOLS=y' >> "$d"
done
```

- [ ] **Step 2: Rigenera i defconfig canonici**

```bash
for d in external/configs/*_defconfig; do
	name="$(basename "$d")"
	make -C buildroot O="$PWD/out-$name" BR2_EXTERNAL="$PWD/external" "$name"
	make -C buildroot O="$PWD/out-$name" BR2_EXTERNAL="$PWD/external" savedefconfig
done
git diff --stat external/configs/
```
Expected: quattro file modificati, e ognuno ha `BR2_PACKAGE_UBOOT_TOOLS=y` nella posizione canonica.

- [ ] **Step 3: Verifica che `savedefconfig` sia idempotente (criterio 4)**

```bash
for d in external/configs/*_defconfig; do
	name="$(basename "$d")"
	make -C buildroot O="$PWD/out-$name" BR2_EXTERNAL="$PWD/external" savedefconfig
done
git diff --exit-code external/configs/ && echo "IDEMPOTENTE"
```
Expected: `IDEMPOTENTE` — nessun ulteriore diff rispetto allo Step 2. Pulisci: `rm -rf out-*_defconfig`.

- [ ] **Step 4: Scrivi il test che fallisce**

Crea `/tmp/test-fwenv.sh` (usa e getta):

```bash
#!/usr/bin/env bash
set -uo pipefail
F=output/target/etc/fw_env.config
fail=0

[ -f "$F" ] || { echo "FAIL $F non esiste"; exit 1; }
echo "--- $F"; cat "$F"

check() {
	if grep -qE "$2" "$F"; then echo "ok   $1"
	else echo "FAIL $1 (regex: $2)"; fail=1; fi
}
check "riga per /dev/mtd2 (env)"   '^/dev/mtd2[[:space:]]+0x0000[[:space:]]+0x20000[[:space:]]+0x20000[[:space:]]+4$'
check "riga per /dev/mtd3 (env_r)" '^/dev/mtd3[[:space:]]+0x0000[[:space:]]+0x20000[[:space:]]+0x20000[[:space:]]+4$'

n="$(grep -cvE '^[[:space:]]*(#|$)' "$F")"
if [ "$n" = 2 ]; then echo "ok   esattamente due copie"
else echo "FAIL $n righe utili invece di 2"; fail=1; fi

[ -x output/target/usr/sbin/fw_printenv ] || [ -x output/target/usr/bin/fw_printenv ] \
	&& echo "ok   fw_printenv installato" \
	|| { echo "FAIL fw_printenv non installato"; fail=1; }

exit $fail
```

Run: `bash /tmp/test-fwenv.sh`
Expected: FAIL — `output/target/etc/fw_env.config` non esiste.

- [ ] **Step 5: Genera il file in `post-build.sh`**

In fondo a `post-build.sh`, dopo il blocco `securetty`, aggiungi:

```bash
# ---------------------------------------------------------------------------
# /etc/fw_env.config
# ---------------------------------------------------------------------------
# Dice a fw_printenv/fw_setenv dove sta l'ambiente. E' GENERATO, non tenuto
# allineato a mano: gli stessi offset stanno in parameter.txt (e quindi nella
# GPT, e quindi in /proc/mtd) e in uboot.config. Se divergessero, fw_setenv
# "riuscirebbe" e U-Boot leggerebbe un'altra area — nessun errore, solo un
# ambiente che non torna. post-image.sh verifica gli altri due lati.
#
# Una riga per copia, cioe' una per partizione: e' cosi' che le due semantiche
# di skip dei blocchi guasti coincidono. fw_env su un device MTD_NANDFLASH usa
# lo schema FLAG_INCREMENTAL — lo stesso serial byte che scrive env_export() —
# e salta i blocchi guasti entro il numero di settori dichiarato qui.
#
# Il file si genera solo se fw_printenv e' nel .config: un fork che non lo
# vuole non deve trovarsi un file che punta a partizioni che non usa.
if grep -q '^BR2_PACKAGE_UBOOT_TOOLS_FWPRINTENV=y$' "${BR2_CONFIG:-/dev/null}"; then
	# shellcheck source=flash-layout.sh
	. "$BOARD_DIR/flash-layout.sh"

	# CONFIG_ENV_SIZE viene da U-Boot, non si cabla: post-image.sh ha gia'
	# verificato che ci stia dentro la partizione.
	uboot_ver="$(sed -n 's/^BR2_TARGET_UBOOT_CUSTOM_REPO_VERSION="\(.*\)"$/\1/p' "$BR2_CONFIG")"
	uboot_autoconf="${BASE_DIR:-}/build/uboot-$uboot_ver/include/generated/autoconf.h"
	env_size="$(sed -n 's/^#define CONFIG_ENV_SIZE \(.*\)$/\1/p' "$uboot_autoconf" 2>/dev/null | tail -1)"

	# flash_layout emette tutto o niente e il suo stato di uscita si perde
	# dentro una process substitution: si raccoglie qui. Un fw_env.config
	# troncato punterebbe a partizioni sbagliate senza dirlo a nessuno.
	layout="$(flash_layout "$BOARD_DIR/parameter.txt")" || {
		echo "post-build.sh: parameter.txt non parsabile, /etc/fw_env.config non generato" >&2
		exit 1
	}

	if [ -z "$env_size" ] && ! grep -q '^BR2_TARGET_UBOOT=y$' "$BR2_CONFIG"; then
		# Un fork che tiene fw_printenv ma toglie U-Boot dal build: non c'e'
		# un CONFIG_ENV_SIZE da leggere e non e' un errore.
		echo "post-build.sh: U-Boot non e' nel build, /etc/fw_env.config non generato" >&2
	elif [ -z "$env_size" ]; then
		# Qui invece U-Boot c'e' e l'header non si legge: un fw_env.config
		# mancante non da' sintomi fino alla board, quindi si muore adesso.
		echo "post-build.sh: CONFIG_ENV_SIZE non leggibile da" >&2
		echo "               $uboot_autoconf" >&2
		echo "               /etc/fw_env.config non puo' essere generato." >&2
		exit 1
	else
		{
			echo "# Generato da board/lyra-plus/post-build.sh da parameter.txt."
			echo "# NON modificare a mano: gli offset devono restare quelli"
			echo "# della GPT e di uboot.config."
			printf '# %-16s %-8s %-9s %-12s %s\n' \
				Device Offset Env.size 'Sector size' '#sectors'
			while IFS=$'\t' read -r idx name _off size; do
				case "$name" in env|env_r) ;; *) continue ;; esac
				printf '/dev/mtd%-10s %-8s %-9s %-12s %s\n' \
					"$idx" 0x0000 \
					"$(printf '0x%x' "$(( env_size ))")" \
					"$(printf '0x%x' "$LYRA_ERASE_BLOCK")" \
					"$(( size / LYRA_ERASE_BLOCK ))"
			done <<<"$layout"
		} > "$TARGET_DIR/etc/fw_env.config"
	fi
fi
```

Nota: `Offset` e' `0x0000` perche' e' l'offset **dentro** `/dev/mtdN`, e ogni partizione contiene una sola copia che parte dal suo inizio.

- [ ] **Step 6: Verifica sintassi e shellcheck**

```bash
bash -n external/board/lyra-plus/post-build.sh
shellcheck -S warning external/board/lyra-plus/post-build.sh
```
Expected: nessun output.

- [ ] **Step 7: Ricostruisci e verifica che il test passi**

```bash
make lyra_plus_defconfig
make 2>&1 | tail -20
bash /tmp/test-fwenv.sh
```
Expected: PASS. Il file contiene:
```
# Generato da board/lyra-plus/post-build.sh da parameter.txt.
# NON modificare a mano: gli offset devono restare quelli
# della GPT e di uboot.config.
# Device           Offset   Env.size  Sector size  #sectors
/dev/mtd2          0x0000   0x20000   0x20000      4
/dev/mtd3          0x0000   0x20000   0x20000      4
```

- [ ] **Step 8: Verifica il ramo "fork che non vuole i tool"**

```bash
grep -n 'BR2_PACKAGE_UBOOT_TOOLS' output/.config | head
```
Expected: `BR2_PACKAGE_UBOOT_TOOLS_FWPRINTENV=y` presente. Il ramo negativo non e' costruibile a mano senza un secondo build completo: basta rileggere la guardia e confermare che senza quel simbolo il blocco non parte e la build non fallisce.

- [ ] **Step 9: Commit**

```bash
git add external/board/lyra-plus/post-build.sh external/configs/
git commit -m "target: fw_printenv/fw_setenv, con un fw_env.config generato

/etc/fw_env.config non e' un file da tenere allineato a mano: non esiste
finche' post-build.sh non lo costruisce da parameter.txt, cioe' dalla
stessa fonte della GPT. Env.size viene da CONFIG_ENV_SIZE di U-Boot, non
cablata.

Una riga per copia, una copia per partizione: e' l'unica geometria in cui
lo skip dei blocchi guasti di U-Boot e quello di fw_env cadono sugli
stessi blocchi fisici.

BR2_PACKAGE_UBOOT_TOOLS su tutti e quattro i defconfig; _FWPRINTENV e'
gia' default y e quindi non compare in un defconfig canonico."
```

---

## Task 7: gli indici MTD slittati — kernel e DTS

**Files:**
- Modify: `external/board/lyra-plus/linux-mainline.config:197`
- Modify: `external/board/lyra-plus/linux-mainline-flash.config:53`
- Create: `external/board/lyra-plus/patches/linux/73bca17b67938d649b072408780369f600555263/0001-arm-dts-rk3506g-luckfox-lyra-plus-ubi-mtd-per-nome.patch`
- Modify: `external/board/lyra-plus/post-image.sh` (dopo la riga che definisce `$DTB`)

**Interfaces:**
- Consumes: il layout di Task 3.
- Produces: `/proc/mtd` mostra cinque partizioni su tutti e quattro i percorsi, e `/dev/mtd2`/`/dev/mtd3` sono davvero `env`/`env_r`.

**Perche' anche `linux-mainline.config` e non solo il fragment `-flash`:** entrambi cablano l'intero `mtdparts` in `CONFIG_CMDLINE` (`CONFIG_CMDLINE` e' un simbolo string e Kconfig non sa appendere, quindi la stringa e' duplicata). Se si aggiorna solo `-flash`, su `lyra_plus_mainline_initramfs_defconfig` le partizioni `env`/`env_r` non esistono, `/dev/mtd2` e' `rootfs`, e il `/etc/fw_env.config` di Task 6 fa scrivere `fw_setenv` **dentro la rootfs**.

**Perche' la patch al DTS sta in una sottodirectory di versione:** `BR2_GLOBAL_PATCH_DIR` e' condiviso da tutti e quattro i defconfig, e i due mainline hanno il DTS in `arch/arm/boot/dts/rockchip/`. Una patch in `patches/linux/` fallirebbe l'applicazione su mainline e romperebbe due build su quattro. `pkg-patches-dirs` (`buildroot/package/pkg-utils.mk:166-170`) usa `<patch-dir>/linux/<LINUX_VERSION>/` **al posto** della base quando esiste, e con `BR2_LINUX_KERNEL_CUSTOM_GIT` la `VERSION` e' lo SHA.

- [ ] **Step 1: Aggiorna le due `CONFIG_CMDLINE` mainline**

Il nuovo `mtdparts`, in byte, con mtd-id `spi0.0` (mainline non ha la patch Rockchip che forza `mtd->name = "spi-nand0"`, quindi il nome ricade su `dev_name(parent)`):

```
mtdparts=spi0.0:0x400000@0x400000(uboot),0xc00000@0x800000(boot),0x80000@0x1400000(env),0x80000@0x1480000(env_r),0xdf60000@0x2000000(rootfs)
```

`linux-mainline.config` riga 197 diventa:
```
CONFIG_CMDLINE="earlycon=uart8250,mmio32,0xff0a0000 console=ttyS0,1500000 clk_ignore_unused rootwait mtdparts=spi0.0:0x400000@0x400000(uboot),0xc00000@0x800000(boot),0x80000@0x1400000(env),0x80000@0x1480000(env_r),0xdf60000@0x2000000(rootfs)"
```

`linux-mainline-flash.config` riga 53 diventa:
```
CONFIG_CMDLINE="earlycon=uart8250,mmio32,0xff0a0000 console=ttyS0,1500000 clk_ignore_unused rootwait mtdparts=spi0.0:0x400000@0x400000(uboot),0xc00000@0x800000(boot),0x80000@0x1400000(env),0x80000@0x1480000(env_r),0xdf60000@0x2000000(rootfs) ubi.mtd=rootfs root=ubi0:rootfs rootfstype=ubifs rw"
```

Nel commento di `linux-mainline.config` che elenca la conversione settori → byte (intorno alla riga 172), aggiungi le due righe nuove:
```
#         env     0x00000400@0x0000a000  ->  0x80000@0x1400000     512 KiB @ 20   MiB
#         env_r   0x00000400@0x0000a400  ->  0x80000@0x1480000     512 KiB @ 20.5 MiB
```

`ubi.mtd=rootfs` in `-flash` e' gia' per nome, quindi lo slittamento degli indici non lo tocca: era gia' scritto per questo.

- [ ] **Step 2: Verifica che le due stringhe combacino fino a `(rootfs)`**

```bash
a="$(sed -n 's/^CONFIG_CMDLINE="\(.*mtdparts=[^ ]*\).*"$/\1/p' external/board/lyra-plus/linux-mainline.config)"
b="$(sed -n 's/^CONFIG_CMDLINE="\(.*mtdparts=[^ ]*\).*"$/\1/p' external/board/lyra-plus/linux-mainline-flash.config)"
[ "$a" = "$b" ] && echo "IDENTICHE" || { echo "DIVERGONO"; diff <(echo "$a") <(echo "$b"); }
```
Expected: `IDENTICHE`. Le due copie vanno tenute allineate a mano, e questo e' il controllo.

- [ ] **Step 3: Verifica che gli offset combacino con `parameter.txt`**

```bash
. external/board/lyra-plus/flash-layout.sh
for n in uboot boot env env_r rootfs; do
	printf '%-8s parameter.txt=%s  ' "$n" "$(flash_part external/board/lyra-plus/parameter.txt "$n" | cut -d' ' -f2)"
	grep -o "@0x[0-9a-f]*($n)" external/board/lyra-plus/linux-mainline.config | head -1
done
```
Expected: per ogni partizione il decimale di `parameter.txt` e l'esadecimale del `CONFIG_CMDLINE` devono essere lo stesso numero (`20971520` = `0x1400000`, `21495808` = `0x1480000`, `33554432` = `0x2000000`).

- [ ] **Step 4: Materializza il kernel vendor e leggi il bootargs vero**

Il testo esatto del bootargs vendor **va riletto, non assunto**: `docs/BOARD-FACTS.md:81` lo riporta a partire dall'SDK Luckfox, non dal mirror allo SHA `73bca17b`.

```bash
make lyra_plus_defconfig
make linux-extract
K=output/build/linux-73bca17b67938d649b072408780369f600555263
grep -n 'bootargs' "$K/arch/arm/boot/dts/rk3506g-luckfox-lyra-plus.dts"
```
Expected: una riga con `ubi.mtd=2`. Se `ubi.mtd=2` non c'e' o e' scritto diversamente, **fermati e riporta**: la patch va scritta su quello che c'e' davvero.

- [ ] **Step 5: Aggiungi la guardia sul DTB in `post-image.sh`**

La guardia va scritta PRIMA della patch, altrimenti non c'e' modo di vederla
fallire: il DTB con `ubi.mtd=2` esiste solo finche' la patch non c'e'.

Ancora per contenuto, non per numero di riga (`post-image.sh` e' gia' stato
modificato da Task 2 e Task 5): subito dopo la riga

```bash
[ -f "$DTB" ] || die "DTB non trovato: $DTB"
```

inserisci:

```bash
# La patch che porta ubi.mtd=2 -> ubi.mtd=rootfs nel DTS vendor e' agganciata
# alla sottodirectory di versione patches/linux/<SHA>/. E' il prezzo di non
# romperla sui due percorsi mainline, che hanno il DTS altrove — ma significa
# che alzando lo SHA del kernel la patch smette di applicarsi SENZA UN
# MESSAGGIO, e la board monta la partizione sbagliata.
#
# Il DTB e' gia' in mano allo script: si controlla li'. Sui DTB mainline il
# nodo chosen non ha bootargs, quindi il controllo e' un no-op.
if strings "$DTB" | grep -qE 'ubi\.mtd=[0-9]'; then
	die "il DTB $DTB_NAME.dtb attacca UBI per INDICE:
        $(strings "$DTB" | grep -oE 'ubi\.mtd=[0-9]+' | head -1)
    Dopo l'aggiunta delle partizioni env/env_r la rootfs e' mtd4, non mtd2:
    con questo bootargs il kernel attaccherebbe UBI all'area dell'env.
    Quasi sempre significa che la patch al DTS vendor non si e' applicata
    perche' BR2_LINUX_KERNEL_CUSTOM_REPO_VERSION e' cambiato e la
    sottodirectory external/board/lyra-plus/patches/linux/<SHA>/ non
    corrisponde piu'. Rinominala con il nuovo SHA."
fi
```

Poi:
```bash
bash -n external/board/lyra-plus/post-image.sh
shellcheck -S warning external/board/lyra-plus/post-image.sh
```
Expected: nessun output.

- [ ] **Step 6: Esegui il test — la build deve morire**

```bash
make lyra_plus_defconfig
make 2>&1 | tail -15; echo "exit=${PIPESTATUS[0]}"
```
Expected: la build muore con
```
*** lyra-plus: il DTB rk3506g-luckfox-lyra-plus.dtb attacca UBI per INDICE:
        ubi.mtd=2
```
e exit diverso da 0. Questo e' esattamente lo stato in cui si troverebbe
chiunque alzasse lo SHA del kernel senza rinominare la sottodirectory delle
patch: e' la condizione che la guardia deve intercettare, ed e' osservabile ora
senza doverla simulare dopo.

- [ ] **Step 7: Scrivi la patch al DTS vendor**

```bash
K=output/build/linux-73bca17b67938d649b072408780369f600555263
D=arch/arm/boot/dts/rk3506g-luckfox-lyra-plus.dts
mkdir -p /tmp/k/a/arch/arm/boot/dts /tmp/k/b/arch/arm/boot/dts
cp "$K/$D" /tmp/k/a/$D
cp "$K/$D" /tmp/k/b/$D
sed -i 's/ubi\.mtd=2/ubi.mtd=rootfs/' /tmp/k/b/$D
( cd /tmp/k && diff -u a/$D b/$D ) > /tmp/0001-dts.diff
cat /tmp/0001-dts.diff    # controlla a occhio che cambi UNA riga
```

Poi:

```bash
P=external/board/lyra-plus/patches/linux/73bca17b67938d649b072408780369f600555263
mkdir -p "$P"
cat > "$P/0001-arm-dts-rk3506g-luckfox-lyra-plus-ubi-mtd-per-nome.patch" <<'EOF'
From: rk3506-framework <walter.dalmut@corley.it>
Subject: [PATCH 1/1] ARM: dts: rk3506g-luckfox-lyra-plus: ubi.mtd per nome

Il bootargs del DTS attacca UBI a `ubi.mtd=2`, cioe' per indice. Con le due
partizioni dell'environment (env, env_r) inserite nel buco a 20 MiB di
parameter.txt, mtd2 non e' piu' la rootfs ma la prima copia dell'env: il
kernel attaccherebbe UBI a 512 KiB di area cancellata e il boot morirebbe
sul mount della root.

`ubi.mtd=rootfs` attacca per nome: ubi_mtd_param_parse prova prima
simple_strtoul e, se la stringa non e' un numero, chiama get_mtd_device_nm().
Cosi' non si rompe piu' se il layout cambia ancora ordine.

Questa patch sta in una sottodirectory di versione perche' BR2_GLOBAL_PATCH_DIR
e' condiviso dai quattro defconfig e i due mainline hanno il DTS in un percorso
diverso (arch/arm/boot/dts/rockchip/). pkg-patches-dirs usa
<patch-dir>/linux/<LINUX_VERSION>/ al posto della base quando esiste, e con
BR2_LINUX_KERNEL_CUSTOM_GIT la VERSION e' lo SHA: gli alberi mainline non
trovano la sottodirectory, ricadono sulla base e non applicano nulla.

Effetto collaterale: se lo SHA del kernel vendor viene alzato, questa patch
smette di applicarsi IN SILENZIO. Per questo post-image.sh verifica che il DTB
costruito non contenga ubi.mtd=<numero>.

EOF
cat /tmp/0001-dts.diff >> "$P/0001-arm-dts-rk3506g-luckfox-lyra-plus-ubi-mtd-per-nome.patch"
```

- [ ] **Step 8: Ricostruisci e verifica che la build passi**

```bash
rm -rf output/build/linux-73bca17b*
make 2>&1 | grep -iE 'apply|patch|ubi\.mtd' | head
make 2>&1 | tail -15; echo "exit=${PIPESTATUS[0]}"
```
Expected: nella traccia compare l'applicazione di
`0001-arm-dts-rk3506g-luckfox-lyra-plus-ubi-mtd-per-nome.patch`, la guardia non
scatta piu' e la build arriva in fondo.

Controllo diretto sul DTB costruito:
```bash
strings output/build/linux-73bca17b*/arch/arm/boot/dts/rk3506g-luckfox-lyra-plus.dtb \
	| grep -o 'ubi\.mtd=[^ "]*'
```
Expected: `ubi.mtd=rootfs`, e nessun `ubi.mtd=2`.

- [ ] **Step 9: Verifica che i mainline NON prendano la patch**

```bash
make lyra_plus_mainline_defconfig
make linux-extract
ls output/build/linux-d5ef611a*/.applied_patches_list 2>/dev/null \
	&& cat output/build/linux-d5ef611a*/.applied_patches_list \
	|| echo "(nessuna patch applicata, come atteso)"
```
Expected: nessuna patch al kernel mainline. Se comparisse
`0001-arm-dts-...`, la sottodirectory di versione non sta funzionando e il
task va fermato e riportato.

- [ ] **Step 10: Commit**

```bash
git add external/board/lyra-plus/linux-mainline.config \
        external/board/lyra-plus/linux-mainline-flash.config \
        external/board/lyra-plus/patches/linux/73bca17b*/ \
        external/board/lyra-plus/post-image.sh
git commit -m "kernel: gli indici MTD sono slittati, e ubi.mtd va per nome

Con env ed env_r la rootfs e' mtd4. I tre punti che cablavano un indice:

  - le due CONFIG_CMDLINE mainline. Entrambe, non solo quella con la root
    su flash: se si aggiornasse solo -flash, sulla variante initramfs
    /dev/mtd2 resterebbe la rootfs e il fw_env.config generato farebbe
    scrivere fw_setenv dentro il filesystem.
  - il bootargs del DTS vendor: ubi.mtd=2 -> ubi.mtd=rootfs. La patch sta
    in patches/linux/<SHA vendor>/ perche' BR2_GLOBAL_PATCH_DIR e'
    condiviso e i due mainline hanno il DTS altrove.

Il prezzo di quell'aggancio allo SHA e' che alzando il kernel la patch
smette di applicarsi in silenzio, quindi post-image.sh verifica che il DTB
costruito non contenga ubi.mtd=<numero>. Senza quel controllo un bump
produrrebbe una board che monta la partizione sbagliata."
```

---

## Task 8: i due punti che descrivono il layout a parole

**Files:**
- Modify: `external/package/hello-lyra/src/main.go:174`
- Modify: `external/board/lyra-plus/genimage.cfg:11-17`, `:35-37`

**Interfaces:**
- Consumes: il layout di Task 3.
- Produces: niente. Sono due descrizioni, ed e' proprio quando servono che devono essere giuste.

- [ ] **Step 1: Scrivi il test che fallisce**

```bash
grep -n 'mtd2=rootfs' external/package/hello-lyra/src/main.go
```
Expected **oggi**: una riga, la 174. Quella stringa e' il messaggio che si legge quando `/proc/mtd` non c'e', cioe' esattamente quando ci si sta chiedendo com'e' fatta la flash: dire `mtd2=rootfs` manderebbe fuori strada nel momento peggiore.

- [ ] **Step 2: Correggi la stringa di fallback**

In `external/package/hello-lyra/src/main.go`, riga 174, da:

```go
		fmt.Println("    atteso su questa board: mtd0=uboot mtd1=boot mtd2=rootfs")
```

a:

```go
		fmt.Println("    atteso su questa board: mtd0=uboot mtd1=boot mtd2=env mtd3=env_r mtd4=rootfs")
```

Il resto della funzione legge `/proc/mtd` e non cabla nulla: non va toccato.

- [ ] **Step 3: Esegui i controlli che esegue la CI**

```bash
cd external/package/hello-lyra/src
test -z "$(gofmt -l .)" && echo "gofmt ok"
go vet ./...
GOOS=linux GOARCH=arm GOARM=7 CGO_ENABLED=0 go build -o /tmp/hello-lyra .
file /tmp/hello-lyra | grep -q 'ARM' && echo "ARM ok"
cd -
```
Expected: `gofmt ok`, nessun output da `go vet`, `ARM ok`.

- [ ] **Step 4: Verifica che il test passi**

```bash
grep -n 'mtd2=rootfs' external/package/hello-lyra/src/main.go
grep -n 'mtd2=env mtd3=env_r mtd4=rootfs' external/package/hello-lyra/src/main.go
```
Expected: il primo non trova nulla, il secondo trova la riga 174.

- [ ] **Step 5: Aggiorna i commenti di `genimage.cfg`**

Le righe 11-17 elencano gli offset e affermano che fra 20 e 32 MiB "resta un buco non allocato". Sostituiscile con:

```
# Gli offset sono quelli di board/lyra-plus/parameter.txt, convertiti da
# settori da 512 B a byte:
#     uboot   0x02000 sett =  4   MiB   (size 0x2000 sett =  4   MiB)
#     boot    0x04000 sett =  8   MiB   (size 0x6000 sett = 12   MiB)
#     env     0x0a000 sett = 20   MiB   (size 0x0400 sett =  0.5 MiB)
#     env_r   0x0a400 sett = 20.5 MiB   (size 0x0400 sett =  0.5 MiB)
#     rootfs  0x10000 sett = 32   MiB   (size "grow")
# Fra 21 e 32 MiB resta un buco non allocato di 11 MiB: e' quello che c'era
# gia' nel parameter.txt vendor, meno il MiB preso dalle due partizioni
# dell'environment.
#
# env ed env_r NON compaiono fra le partition qui sotto, e non e' una
# dimenticanza: nascono cancellate, non hanno un'immagine da scrivere. Al
# primo boot dopo il riflash U-Boot stampa tre righe, non una:
#     *** Warning - bad CRC, using default environment
#     *** Environment invalid, writing default to flash
#     Writing to redundant <NULL>(<NULL>)... done
# ricade sul default environment e lo scrive subito su una delle due copie --
# la ridondante, mtd3 -- senza aspettare un saveenv esplicito. La terza riga
# la stampa env_blk_save(), e i <NULL> sono devtype e devnum, che
# set_default_env() ha appena tolto dall'hashtable: e' atteso. Al boot
# successivo nessuna delle tre righe compare piu'.
#
# Le tre righe sono DEDOTTE DAL SORGENTE, non osservate su hardware:
# read_env() (env/env_blk.c:158-169) ritorna 0 se la lettura riesce, senza
# guardare il CRC, e una pagina NAND cancellata si rilegge come 0xFF, quindi
# il ramo "*** Error - No Valid Environment Area found"
# (env/env_blk.c:198-206) NON viene preso: si arriva a env_import_redund(),
# i due CRC falliscono, set_default_env("!bad CRC") (env/common.c:229-231,
# :73-78) stampa la prima riga e alza GD_FLG_ENV_DEFAULT, ed env_blk_repair()
# (env/env_blk.c) lo rileva e stampa la seconda scrivendo il default in
# flash. Se il driver SPI-NAND ritornasse un errore ECC sulle pagine
# cancellate comparirebbe l'altro messaggio al posto del primo, ma la
# riparazione scatterebbe comunque.
```

Le righe 35-37 (`Per la stessa ragione le partizioni non dichiarano 'size'...`) restano valide e non si toccano.

- [ ] **Step 6: Verifica che `genimage` accetti ancora il file**

```bash
make lyra_plus_defconfig && make 2>&1 | grep -i genimage
ls -l output/images/flash.img
```
Expected: `flash.img` prodotto, con la stessa dimensione di prima (le partizioni dichiarate non sono cambiate).

- [ ] **Step 7: Commit**

```bash
git add external/package/hello-lyra/src/main.go external/board/lyra-plus/genimage.cfg
git commit -m "layout: aggiorna le due descrizioni a parole delle partizioni

La stringa di fallback di hello-lyra diceva 'mtd2=rootfs'. E' solo un
messaggio, ma e' il messaggio che si legge quando /proc/mtd non c'e', cioe'
esattamente quando ci si sta chiedendo com'e' fatta la flash.

I commenti di genimage.cfg elencavano gli offset e dicevano che fra 20 e
32 MiB c'era un buco: ora ce n'e' uno di 11 MiB fra 21 e 32. Aggiunta la
nota che env ed env_r non hanno una partition qui perche' nascono
cancellate."
```

---

## Task 9: documentazione

**Files:**
- Modify: `docs/BOARD-FACTS.md`
- Modify: `docs/SCELTE-DI-PROGETTO.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: tutto quanto sopra.
- Produces: niente. La verifica dei valori numerici sull'hardware sta in Task 10, e la sostituzione dell'output di esempio del README pure — qui si scrive solo cio' che e' gia' verificato in albero.

- [ ] **Step 1: `docs/BOARD-FACTS.md` — tabella del layout MTD**

Aggiungi una sezione con la tabella e la fonte di ogni valore:

```markdown
### Layout MTD

Fonte unica: `external/board/lyra-plus/parameter.txt`, riga `CMDLINE`.
Da lì la GPT (`rkdeveloptool`/`afptool`), da lì la lista partizioni di U-Boot
(`part_efi`), da lì la stringa `mtdparts=` (`drivers/mtd/mtd_blk.c:381`), da lì
`/proc/mtd`. Non c'è un secondo posto dove dichiarare una partizione.

| idx | nome | offset | size | contenuto |
|---|---|---|---|---|
| — | *loader/IDB* | 0 | 4 MiB | non dichiarata; `MiniLoaderAll.bin` |
| `mtd0` | `uboot` | 4 MiB | 4 MiB | `uboot.img` (FIT ×2, 2 MiB ciascuna) |
| `mtd1` | `boot` | 8 MiB | 12 MiB | `boot.img` (FIT: zImage + fdt + resource) |
| `mtd2` | `env` | 20 MiB | 512 KiB | environment U-Boot, copia primaria |
| `mtd3` | `env_r` | 20.5 MiB | 512 KiB | environment U-Boot, copia ridondante |
| — | *buco* | 21 MiB | 11 MiB | non allocato |
| `mtd4` | `rootfs` | 32 MiB | `grow` → `0xdf60000` | UBI |

**Gli indici sono slittati** rispetto alle versioni fino alla v0.2.0: `rootfs`
era `mtd2`. Ogni punto che cablava un indice è stato convertito al nome
(`ubi.mtd=rootfs`), tranne `/etc/fw_env.config`, che di indici ha bisogno e per
questo è **generato** da `parameter.txt` invece che scritto a mano.

L'environment occupa un erase block (128 KiB) dentro una partizione di quattro:
gli altri tre sono riserva per lo skip dei blocchi guasti. Sull'esemplare
misurato ci sono 2 blocchi guasti su 1792.
```

- [ ] **Step 2: `docs/SCELTE-DI-PROGETTO.md` — le tre scelte**

Aggiungi una sezione che risponde a tre domande, ognuna con la fonte:

1. **Perché un env ridondante e non una copia sola.** Un power loss durante `saveenv` non deve lasciare zero copie valide. `env_blk_save()` scrive una copia per volta, alternata (`env/env_blk.c:126-148`), quindi l'altra resta intatta per tutta la durata della scrittura; in lettura `env_import_redund()` confronta i CRC e, se sono validi entrambi, decide in base al serial byte gestendo il wrap `255 → 0` (`env/common.c:216-257`). Il serial byte lo incrementa `env_export()` (`env/common.c:282`).
2. **Perché `ENV_IS_IN_BLK_DEV` e non ENVF**, nonostante ENVF sia la strada vendor battuta (20 defconfig la usano). `envf_save()` esporta con `H_MATCH_KEY | H_MATCH_IDENT` su una whitelist compile-time, `CONFIG_ENVF_LIST` (`env/envf.c:306`, `env/Kconfig:457`): `setenv pippo 1; saveenv` non persisterebbe. Allargare la lista non risolve — resta chiusa e decisa a compile time, cioè l'opposto di un ambiente. Va detto il rischio accettato: **zero defconfig in questo albero usano `ENV_IS_IN_BLK_DEV`**, è codice vendor poco battuto, e i criteri di accettazione 1-3 lo esercitano end-to-end proprio per questo.
3. **Perché due partizioni e non una da 1 MiB con due offset interni.** Con una sola partizione U-Boot rimappa i blocchi guasti sull'**intera** partizione (`mtd_blk_map_table_init()`, `drivers/mtd/mtd_blk.c:43`, chiamata per partizione da `mtd_blk_map_partitions()`), quindi un blocco guasto nella prima metà sposterebbe anche la copia di backup; `fw_env`, che salta entro il numero di settori della singola copia, no. Divergenza silenziosa: `fw_setenv` "riesce" e U-Boot legge altro. Con una partizione per copia le due semantiche coincidono per costruzione.

Aggiungi anche il perché delle patch ai file core invece che al board header: così i tre valori numerici restano dentro `uboot.config`, visibili nel diff e in un unico posto, invece di essere sepolti dentro un file di patch.

- [ ] **Step 3: `README.md` — il messaggio atteso al primo boot**

Nella sezione che descrive il primo boot dopo il riflash, aggiungi:

````markdown
> Al primo boot dopo un riflash U-Boot stampa **tre** righe, non una:
>
> ```
> *** Warning - bad CRC, using default environment
> *** Environment invalid, writing default to flash
> Writing to redundant <NULL>(<NULL>)... done
> ```
>
> **Sono tutte e tre attese, non un guasto.** Le due partizioni
> dell'environment nascono cancellate: `env_blk_load()` legge entrambe le
> copie, entrambe hanno CRC non valido, `env_import_redund()` ricade sul
> default environment (prima riga) e lo scrive subito su una delle due copie
> (seconda riga), senza aspettare un `saveenv` esplicito. La terza riga la
> stampa `env_blk_save()` (`env/env_blk.c:135-136`); i `<NULL>` sono `devtype`
> e `devnum`, che `set_default_env()` ha appena tolto dall'hashtable, e
> `lib/vsprintf.c` li rende così. La parola `redundant` dice che è stata
> scritta `mtd3`.
>
> Le tre righe, l'ordine in cui compaiono e il fatto che al boot successivo
> nessuna compaia più sono **dedotti dal sorgente, non osservati su
> hardware**. `read_env()` (`env/env_blk.c:158-169`) chiude con
> `return (n == blk_cnt) ? 0 : -1;`: segnala solo errori di I/O, mai un CRC.
> Una pagina NAND cancellata si rilegge come `0xFF`, quindi entrambe le
> letture riescono e il ramo che stamperebbe `*** Error - No Valid
> Environment Area found` (`env/env_blk.c:198-206`) non viene preso; si arriva
> a `env_import_redund()`, i due CRC falliscono, `set_default_env("!bad CRC")`
> (`env/common.c:229-231`, :73-78) stampa la prima riga e alza
> `GD_FLG_ENV_DEFAULT`, che `env_blk_repair()` (`env/env_blk.c`) rileva e usa
> per stampare la seconda riga scrivendo il default in flash. Al boot dopo
> quello la copia appena scritta ha un CRC valido e nessuno dei due rami
> dovrebbe più intervenire — ma è la stessa deduzione, non una conferma da
> banco.
>
> Caveat: con un driver SPI-NAND che ritorna un errore ECC sulle pagine
> cancellate invece di `0xFF` comparirebbe l'altro messaggio al posto della
> prima riga, ma la seconda comparirebbe comunque: quel percorso alza lo
> stesso flag. Lo deciderà il primo boot vero.
>
> Non si pre-seeda l'area con `mkenvimage`, e non è per evitare un messaggio
> benigno — quella era la motivazione originale, falsificata su hardware
> insieme alla D6 della spec: `default_environment` è un simbolo in
> `.rodata` dell'ELF di U-Boot, quindi non ci sarebbe nessun valore da tenere
> allineato a mano. Resta scartato per due motivi diversi: renderebbe
> distruttivo ogni `rkdeveloptool uf`, sovrascrivendo i dati per-esemplare
> (MAC address, numero di serie, calibrazioni) che sono la ragione per cui
> l'environment esiste; e coprirebbe comunque meno casi della riparazione al
> caricamento, che protegge anche il flash per singola partizione e la
> corruzione tardiva di entrambe le copie, non solo il riflash completo.
````

- [ ] **Step 4: `README.md` — il terzo punto di verifica del boot**

Il terzo bullet dopo l'output di esempio dice oggi «**`mtd0/1/2`** — nomi e dimensioni devono combaciare con `parameter.txt`». Sostituisci con:

```markdown
- **`mtd0`…`mtd4`** — nomi e dimensioni devono combaciare con `parameter.txt`.
  Se non c'e' nessuna partizione, `mtdparts=` non e' arrivato al kernel: il DTB
  e' sbagliato o U-Boot ha sovrascritto il bootargs. Se ce ne sono tre invece
  di cinque, l'immagine e' stata costruita prima delle partizioni
  dell'environment e `fw_setenv` scriverebbe dentro la rootfs.
```

- [ ] **Step 5: `README.md` — usare l'environment**

Aggiungi una sezione breve con i comandi reali:

````markdown
### L'environment U-Boot

Persistente e ridondante su due partizioni MTD. Da U-Boot:

```
=> setenv seriale AB1234
=> saveenv
=> reset
=> printenv seriale
```

Da Linux, con lo stesso ambiente:

```
# fw_printenv seriale
# fw_setenv mac_addr 02:00:00:12:34:56
```

`/etc/fw_env.config` e' **generato** da `parameter.txt` a ogni build: non
modificarlo a mano, la modifica sparirebbe alla build successiva e nel
frattempo farebbe scrivere `fw_setenv` nel posto sbagliato.
````

I due blocchi contengono i **comandi**, non le risposte: la riga di conferma di
`saveenv` e l'output di `printenv` si incollano dalla console reale in Task 10,
Step 7. Non inventarli qui.

- [ ] **Step 6: Controlla che non ci siano link morti (job `docs` della CI)**

```bash
rc=0
for f in README.md docs/*.md; do
	dir="$(dirname "$f")"
	for l in $(grep -ohE '\]\([^)#]+(#[^)]*)?\)' "$f" | sed 's/^](//; s/)$//; s/#.*//'); do
		case "$l" in http*|""|../../*) continue ;; esac
		[ -e "$dir/$l" ] || { echo "link morto in $f: $l"; rc=1; }
	done
done
exit $rc
```
Expected: nessun output, exit 0.

- [ ] **Step 7: Commit**

```bash
git add docs/BOARD-FACTS.md docs/SCELTE-DI-PROGETTO.md README.md
git commit -m "docs: il layout MTD nuovo, e perche' l'env e' fatto cosi'

BOARD-FACTS prende la tabella del layout con la fonte di ogni valore e la
nota che gli indici sono slittati.

SCELTE-DI-PROGETTO risponde alle tre domande che qualcuno rifara' fra sei
mesi: perche' ridondante e non copia singola, perche' ENV_IS_IN_BLK_DEV e
non ENVF nonostante ENVF sia la strada vendor battuta, perche' due
partizioni e non una con due offset interni.

Il README dice che 'bad CRC, using default environment' al primo boot e'
seguito da 'Environment invalid, writing default to flash': senza quelle
due righe sembra un guasto, e si perde un pomeriggio."
```

---

## Task 10: verifica sull'hardware

**Files:** nessuno da modificare, tranne l'output di esempio del README (Step 7).

**Interfaces:**
- Consumes: tutto.
- Produces: la conferma che i criteri di accettazione della spec sono soddisfatti.

**Operazione distruttiva.** Cambiare `parameter.txt` cambia la GPT: non basta riscrivere una partizione, serve un riflash completo. Non ci sono board in campo, quindi il costo e' il tempo di un riflash.

- [ ] **Step 1: Build completa e riflash**

```bash
make lyra_plus_defconfig
make
ls -l output/images/
rkdeveloptool uf output/images/update.img
```
Se dopo il riflash il loader non riparte: MaskROM, poi
```bash
rkdeveloptool db output/images/MiniLoaderAll.bin
rkdeveloptool uf output/images/update.img
```

- [ ] **Step 2: `docs/check-artifacts.sh` (criterio 5)**

```bash
./docs/check-artifacts.sh
```
Expected: nessun `FAIL`. Lo script **non e' stato modificato**: il suo unico punto sensibile al layout e' la riga 183, che itera su `parameter bootloader uboot boot rootfs`, ed `env` non ha immagine. Se qui fallisse, e' un fatto nuovo e va riportato, non aggirato.

- [ ] **Step 3: `/proc/mtd` mostra cinque partizioni**

Dalla console della board:
```
# cat /proc/mtd
```
Expected: `mtd0 uboot`, `mtd1 boot`, `mtd2 env`, `mtd3 env_r`, `mtd4 rootfs`, con `env` ed `env_r` da `00080000` ed erasesize `00020000`.

- [ ] **Step 4: Criterio 1 — l'env sopravvive al reboot**

Interrompi l'autoboot e, dal prompt di U-Boot:
```
=> setenv pippo 1
=> saveenv
=> reset
=> printenv pippo
```
Expected: `pippo=1`. Al **primo** boot dopo il riflash, prima di questo, U-Boot avrà stampato **tre** righe, non una:

```
*** Warning - bad CRC, using default environment
*** Environment invalid, writing default to flash
Writing to redundant <NULL>(<NULL>)... done
```

Sono tutte e tre attese (D6 della spec): la prima segnala il CRC non valido su entrambe le copie, la seconda è la riparazione che le rende valide scrivendo il default su una delle due, la terza la stampa `env_blk_save()`, che non è silenzioso (`env/env_blk.c:135-136`). I `<NULL>` della terza riga sono `devtype` e `devnum`: `set_default_env()` ha appena sostituito l'intera hashtable, portandosi via i valori che `rockchip_get_bootdev()` vi aveva messo, e `boot_devtype_init()` non li rimette perché è già stata chiamata una volta; `lib/vsprintf.c` stampa `<NULL>` per i puntatori nulli, non c'è nessun crash e non c'è niente da correggere. La parola `redundant` dice quale copia è stata scritta: `mtd3`. Al **secondo** boot nessuna delle tre compare più, perché la copia appena scritta ha un CRC valido. Le tre righe, e la sequenza in cui compaiono, sono dedotte dal sorgente, non osservate su hardware: la presenza della riga di riparazione è un fatto del codice sorgente, ma nessun boot reale ha ancora attraversato questo percorso, quindi né l'ordine né la compresenza delle righe sono confermati. Se comparisse invece `*** Error - No Valid Environment Area found`, significa che il driver SPI-NAND ritorna un errore ECC sulle pagine cancellate invece di `0xFF` — annotalo, non è un guasto nemmeno quello, e la riga di riparazione compare comunque, perché quel percorso alza lo stesso flag (`GD_FLG_ENV_DEFAULT`).

- [ ] **Step 5: Criterio 2 — i due lati si vedono**

Questo è lo step che, su una build senza la patch del Task 1, ha bloccato una
scheda reale: `fw_setenv` come prima scrittura dopo un riflash, su un
environment con CRC non valido, non si limita a rifiutarsi — semina l'intero
environment con il default di uboot-tools (`bootcmd=bootp; ...; bootm`), e il
boot successivo muore per assenza di rete. Con la patch del Task 1 questo
passo è sicuro **perché** U-Boot ha già riparato l'environment al primo boot
(Step 4): quando si arriva qui il CRC è valido, e `fw_setenv` scrive dentro un
environment corretto invece di sostituirlo.

Prima del test vero, un controllo che vale anche da verifica della
riparazione:
```
# fw_printenv bootcmd
```
Expected: il `bootcmd` di Rockchip (`boot_fit;boot_android ...`). Se invece
esce `bootcmd=bootp; ...`, l'environment è stato seminato da `fw_setenv` e la
riparazione non ha funzionato: **fermati e riporta, non proseguire con il
reboot**.

Solo dopo questo controllo, da Linux:
```
# fw_setenv pluto 2
# reboot
```
poi da U-Boot: `printenv pluto` → `pluto=2`.

Poi il contrario: da U-Boot `setenv topolino 3 ; saveenv ; boot`, poi da Linux `fw_printenv topolino` → `topolino=3`.

Expected: entrambi i versi funzionano. Se il primo verso fallisce con un CRC error, la causa piu' probabile e' un `Env.size`/`Sector size` sbagliato in `/etc/fw_env.config`: confrontalo con `CONFIG_ENV_SIZE` di `autoconf.h`.

- [ ] **Step 6: Criterio 3 — la ridondanza e' reale**

Prima verifica che le due copie esistano davvero a offset diversi:
```
# hexdump -C /dev/mtd2 | head -4
# hexdump -C /dev/mtd3 | head -4
```
Expected: entrambe iniziano con un CRC32 e poi il byte `flags`, seguiti da coppie `chiave=valore`; i due `flags` differiscono di 1.

Poi invalida la primaria e verifica che il boot usi la ridondante:
```
# flash_erase /dev/mtd2 0 1
# reboot
```
Expected: **nessun messaggio**. U-Boot non stampa niente, e non e' un
fallimento del test: `mtd2` cancellata si **rilegge** senza errori di I/O,
quindi `read_env()` ritorna 0 per entrambe le copie e il ramo
`*** Warning - some problems detected reading environment; recovered
successfully` (`env/env_blk.c:198-206`) non viene preso. Si arriva a
`env_import_redund()`, che con `!crc1_ok && crc2_ok` prende la copia
ridondante e chiama `env_import(ep, 0)` — con il controllo CRC disabilitato,
e **in completo silenzio** (`env/common.c`).

La riparazione del Task 1 **non** entra in gioco qui, e va detto esplicitamente
perché con quella patch in albero il test potrebbe sembrare ambiguo:
`set_default_env()`, che alza `GD_FLG_ENV_DEFAULT` e innesca la riparazione, è
chiamato solo quando **entrambe** le copie sono invalide (Step 4). Con una
sola copia cancellata `env_import_redund()` trova l'altra copia valida, prende
quella e non alza il flag — nessuna riparazione parte, e questo test resta
esattamente quello di prima della patch.

Questo vale **perché** `env_blk_load()` azzera `GD_FLG_ENV_DEFAULT` in testa:
il flag è un latch alzato da `initr_env_nowhere()` prima che qualunque driver
di environment giri, quindi senza l'azzeramento la riparazione sarebbe partita
anche qui, e anzi a ogni boot. Se qualcuno togliesse quella riga, questo test
comincerebbe a fallire in modo confuso.

La prova che la copia ridondante e' stata usata e' quindi un'altra: da U-Boot
`printenv pluto` deve rispondere ancora `pluto=2`. Se rispondesse il default
(o niente), la ridondanza non ha funzionato.

Come secondo segnale, subito dopo: `saveenv`. Scrivera' nella copia
**primaria** (`gd->env_valid` e' `ENV_REDUND`, e `env_blk_save()` alterna),
ripristinando l'alternanza fra le due copie; un `hexdump` di `/dev/mtd2` dopo
il reboot mostra di nuovo un env valido. È anche la conseguenza utile di
questo test: per ripristinare la ridondanza a due copie valide dopo aver
cancellato una copia per prova, basta questo `saveenv` — scrive la copia
mancante, non serve nessun altro passo.

Questo e' il test che esercita il rischio 3 della spec: su un chip senza blocchi guasti nell'area env i due percorsi di `get_mtd_blk_map_address()` sono indistinguibili, quindi il caso va provato deliberatamente e non aspettato.

- [ ] **Step 7: Aggiorna l'output di esempio del README**

Ora che c'e' l'output reale, incolla dalla console — non ricopiare a memoria:

1. il blocco delle partizioni MTD in `README.md` (righe ~1022-1027), con nomi,
   dimensioni e formattazione come li produce `hello-lyra` (`parseHexBytes`
   stampa `%.3f MiB` sopra il MiB e `%.0f KiB` sotto, quindi `env` ed `env_r`
   compariranno come `512 KiB`);
2. le risposte mancanti nella sezione *L'environment U-Boot* aggiunta in Task 9
   Step 5: la riga di conferma di `saveenv` (`Writing to ...`) e l'output di
   `printenv seriale` e `fw_printenv seriale`.

- [ ] **Step 8: Criterio 6 — la variante initramfs boota**

```bash
make lyra_plus_initramfs_defconfig
make
rkdeveloptool uf output/images/update.img
```
Expected: la board arriva al prompt di login. Su questa variante il rootfs sta dentro `boot.img`, quindi `env`/`env_r` restano le uniche partizioni nuove che contano, e `fw_printenv` deve funzionare comunque.

- [ ] **Step 9: Le due varianti mainline costruiscono**

```bash
make lyra_plus_mainline_defconfig && make
make lyra_plus_mainline_initramfs_defconfig && make
```
Expected: entrambe arrivano in fondo. Sono quelle a rischio per la sottodirectory di versione delle patch: verifica che **nessuna** patch al kernel sia stata applicata (`cat output/build/linux-*/.applied_patches_list`, che non deve esistere o essere vuoto per gli SHA mainline).

- [ ] **Step 10: Commit finale**

```bash
git add README.md
git commit -m "README: l'output reale della board con cinque partizioni MTD

Incollato dalla console dopo il riflash, non ricostruito a mano."
```

---

## Self-Review

**Copertura della spec.** Ogni sezione del design ha un task:

| Sezione della spec | Task |
|---|---|
| D1 backend `ENV_IS_IN_BLK_DEV` | 4 |
| D2 due partizioni, `ENV_SIZE` = 1 erase block | 3, 4 |
| D3 layout nel buco a 20 MiB, indici che slittano | 3, 7 |
| D4 fonte unica + parser condiviso | 1, 2, 5, 6 |
| D5 patch ai file core di U-Boot | 4 |
| D6 le due copie nascono cancellate | 8 (genimage), 9 (README), 10 (Step 4) |
| `flash-layout.sh` | 1 |
| `post-build.sh` → `fw_env.config` | 6 |
| `post-image.sh` (parser, check env, check DTB) | 2, 5, 7 |
| `*_defconfig` + `savedefconfig` | 6 |
| `linux-mainline-flash.config` | 7 |
| `linux-mainline.config` (**non nella spec**) | 7 |
| patch al DTS vendor + sottodirectory di versione | 7 |
| `hello-lyra` `main.go:174` | 8 |
| `genimage.cfg` | 8 |
| `check-artifacts.sh` (non cambia, si riverifica) | 10 Step 2 |
| `.github/workflows/checks.yml` | 1 |
| Documentazione | 9 |
| Criteri di accettazione 1-6 | 10 |

**Consistenza dei nomi.** `flash_layout` e `flash_part` sono definite in Task 1 e usate con la stessa firma nei Task 2, 5, 6. `LYRA_ERASE_BLOCK` è definita in Task 1 e usata nei Task 5 e 6. `uboot_def` è locale a `post-image.sh` (Task 5); `post-build.sh` (Task 6) legge `CONFIG_ENV_SIZE` con un `sed` proprio perché non ha `UBOOT_DIR`. `mib` è locale al blocco dimensioni (Task 2).

**Ordine e dipendenze.** 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10. I task 8 e 9 non hanno dipendenze dal 7 e potrebbero girare prima; l'ordine scritto tiene insieme le modifiche funzionali e lascia in fondo quelle descrittive.

**Cosa non è coperto, di proposito.** `BOOT_ORDER`, contatori di boot, logica A/B, slot multipli, RAUC. E il rilassamento di `CONFIG_CMDLINE_FORCE`, che è la seconda metà del problema "U-Boot non passa i parametri": resta fuori perché oggi non ha un consumatore, e il momento in cui serve davvero è l'arrivo dell'A/B, quando `root=` deve diventare dinamico. Il commento in `linux-mainline.config:118-121` descrive già la ricetta.
