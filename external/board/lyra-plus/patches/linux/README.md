# Patch per `linux`

Patch numerate applicate da Buildroot al sorgente scaricato via
`_CUSTOM_GIT`, in ordine lessicografico:

```
0001-descrizione-breve.patch
0002-altra-cosa.patch
```

Generale: `git format-patch` dal tree vendor, poi `git add` qui.
**Non forkare kernel o U-Boot**: lo SHA pinnato nel defconfig deve restare
quello del mirror, e ogni delta deve essere leggibile come patch in questo
repository.

## Sottodirectory di versione

`pkg-patches-dirs` (`buildroot/package/pkg-utils.mk:166-170`) cerca prima
`<patch-dir>/linux/<LINUX_VERSION>/` e, se esiste, la usa AL POSTO della
directory base: le patch qui in `patches/linux/` non vengono applicate a
quel kernel. Con `BR2_LINUX_KERNEL_CUSTOM_GIT` la `LINUX_VERSION` e' lo SHA
pinnato nel defconfig.

Questo serve a limitare una patch a un solo kernel quando i defconfig di
questo BR2_EXTERNAL condividono lo stesso `BR2_GLOBAL_PATCH_DIR` ma i
sorgenti non sono compatibili fra loro: `patches/linux/<SHA>/` esiste per
il kernel vendor perche' il suo DTS ha un bootargs (`ubi.mtd=2`) che sui
kernel mainline non esiste nemmeno, e il DTS mainline sta in un percorso
diverso (`arch/arm/boot/dts/rockchip/`). Una patch in base fallirebbe
l'applicazione sui due percorsi mainline e romperebbe due build su
quattro.

Il prezzo: se lo SHA nel defconfig viene alzato senza rinominare la
sottodirectory, la patch smette di applicarsi IN SILENZIO, perche' Buildroot
ricade sulla directory base (che qui non contiene altro che questo
README) e non segnala nulla. Per questo `post-image.sh` verifica che il
DTB costruito non contenga piu' `ubi.mtd=<numero>`.
