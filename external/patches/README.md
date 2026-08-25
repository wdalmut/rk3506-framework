# `BR2_GLOBAL_PATCH_DIR`

Patch applicate ai package **Buildroot upstream**, con la struttura
`<nome-package>/<NNNN>-<descrizione>.patch`.

**Al momento e' vuota, e non e' una svista.**

La Fase 1 ha confrontato il Buildroot dell'SDK Luckfox (`e6abe17d`, basato su
`2024.02`) con l'upstream `2024.02`: 452 file aggiunti, 242 modificati. Tutte le
modifiche che toccano il percorso usato da questa board — `fs/ubi`, `fs/ubifs`,
`linux/linux.mk`, `arch/Config.in.arm`, `support/scripts/apply-patches.sh` —
sono **comodita', non funzionalita' mancanti in upstream**. Il dettaglio, voce
per voce, e' in `docs/BOARD-FACTS.md` §1a.

Le patch a **kernel** e **U-Boot** non vanno qui: stanno in
`board/lyra-plus/patches/{linux,uboot}/`.
