# Pubblicare una release

Le immagini si pubblicano **a mano**. Non c'e' un workflow che le costruisca,
e non e' una dimenticanza. Costruire richiede il container Docker e circa
mezz'ora di compilazione: e' lavoro che ha senso fare su una macchina vera,
quando si e' pronti a pubblicare, non a ogni push. La CI copre quello che si
verifica in pochi secondi.

## Procedura

Partire da un albero pulito, per non pubblicare artefatti costruiti da
modifiche non committate:

```bash
git status --short          # deve essere vuoto
make lyra_plus_defconfig
make
docs/check-artifacts.sh                     # deve passare
```

Preparare il kit. Il taglio e' volutamente minimo: serve a flashare e vedere se
la scheda parte, non a coprire ogni caso d'uso.

```bash
V=v0.1.0
mkdir -p /tmp/rel-$V && cd /tmp/rel-$V
cp ~/git/rk3506-framework/output/images/{update.img,MiniLoaderAll.bin,parameter.txt} .
sha256sum update.img MiniLoaderAll.bin parameter.txt > SHA256SUMS
```

`update.img` contiene gia' loader, U-Boot, kernel e rootfs. `MiniLoaderAll.bin`
serve comunque, perche' `rkdeveloptool db` lo vuole separato per caricare il
loader in SRAM prima di poter scrivere. `flash.img` **non** va incluso: e'
40 MB e non e' avviabile, visto che l'area IDB resta vuota.

Pubblicare:

```bash
cd ~/git/rk3506-framework
git tag -a $V -m "Prima immagine verificata su hardware"
git push origin $V
gh release create $V /tmp/rel-$V/* --title "$V" --notes-file docs/release-notes-$V.md
```

## Cosa deve dire il testo della release

Tre cose non vanno dimenticate, perche' senza sono problemi veri e non
dettagli:

1. **Il baudrate: 1500000, non 115200.** Con l'adattatore a 115200 non si vede
   niente e sembra un boot fallito. E' il primo motivo per cui qualcuno
   pensera' che l'immagine e' rotta.
2. **I sorgenti GPL.** Kernel e U-Boot sono GPL-2.0 e le immagini ne
   contengono i binari: vanno linkati i due commit esatti sui mirror, piu' le
   patch in `external/board/lyra-plus/patches/uboot/` e la configurazione in
   `external/configs/`.
3. **I blob Rockchip.** Le immagini incorporano `rk3506_ddr_750MHz_v1.04.bin`
   e `rk3506_tee_v1.25.bin`. La licenza rkbin concede esplicitamente uso,
   copia e distribuzione; i vincoli sono non fare reverse engineering e non
   rimuovere le note di copyright, ed entrambi sono rispettati perche' i blob
   restano inclusi intatti.

E una che evita segnalazioni inutili: **le immagini non sono riproducibili byte
per byte.** `ubinize` scrive un `image_seq` casuale a ogni esecuzione e i FIT
contengono un timestamp, quindi ricostruire dallo stesso commit da' file
diversi. Cio' che e' stabile sono struttura e geometria, ed e' quello che
`docs/check-artifacts.sh` verifica.
