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
