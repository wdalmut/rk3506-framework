# Verifica

Come controllare che questo albero produca davvero quello che deve, e cosa e'
gia' stato verificato.

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

---

## Stato di verifica

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
