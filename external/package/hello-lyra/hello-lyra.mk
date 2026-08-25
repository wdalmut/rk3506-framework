# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 Corley S.r.l.
################################################################################
#
# hello-lyra
#
################################################################################

HELLO_LYRA_VERSION = 1.0.0
HELLO_LYRA_SITE = $(BR2_EXTERNAL_LYRA_PLUS_PATH)/package/hello-lyra/src
HELLO_LYRA_SITE_METHOD = local
HELLO_LYRA_LICENSE = MIT
HELLO_LYRA_LICENSE_FILES = LICENSE

# Il modulo Go. Deve combaciare con la riga `module` di src/go.mod, perche'
# pkg-golang.mk costruisce il target come "$(HELLO_LYRA_GOMOD)/$(target)".
# Va impostato a mano: l'inferenza automatica ricava domain/vendor/software
# da _SITE, che qui e' un percorso locale e non un URL.
HELLO_LYRA_GOMOD = github.com/wdalmut/hello-lyra

# Requisito esplicito: nessun CGO. Buildroot lo metterebbe a 1 quando il
# target lo supporta (HOST_GO_CGO_ENABLED), quindi lo forziamo dopo.
# GOARCH=arm e GOARM=7 arrivano da soli: package/go/go.mk deduce GOARM=7 da
# BR2_ARM_CPU_ARMV7A, selezionato da BR2_cortex_a7.
HELLO_LYRA_GO_ENV = CGO_ENABLED=0

# Binario piu' piccolo: -s -w tolgono tabella dei simboli e DWARF.
# Va in _LDFLAGS, non in _BUILD_OPTS: pkg-golang.mk costruisce da se'
# `-ldflags "$(HELLO_LYRA_LDFLAGS)"` (e aggiunge gia' -trimpath), quindi
# passarlo in _BUILD_OPTS darebbe un -ldflags duplicato.
HELLO_LYRA_LDFLAGS = -s -w -X main.version=$(HELLO_LYRA_VERSION)

$(eval $(golang-package))
