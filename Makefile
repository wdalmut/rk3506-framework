# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 Corley S.r.l.
# Wrapper attorno a Buildroot upstream.
#
# Non contiene logica di build: serve solo a non far ripetere ogni volta
# `-C buildroot O=... BR2_EXTERNAL=...`, e a dare un modo unico di entrare
# nel container.
#
#   make image                            costruisce l'immagine Docker
#   make shell                            apre una shell nel container
#   make lyra_plus_defconfig              configura per SPI NAND + UBIFS
#   make lyra_plus_initramfs_defconfig    configura per bring-up in RAM
#   make                                  costruisce
#   make savedefconfig                    riscrive il defconfig dal .config
#
# Qualunque altro target viene inoltrato a Buildroot cosi' com'e':
# `make menuconfig`, `make linux-menuconfig`, `make uboot-rebuild`,
# `make hello-lyra-rebuild`, `make printvars VARS=...`.

TOPDIR       := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
O            ?= $(TOPDIR)/output
BR2_EXTERNAL := $(TOPDIR)/external
BUILDROOT    := $(TOPDIR)/buildroot

# I binari vendor non ricompilabili (blob DDR, OP-TEE, boot_merger, mkimage,
# afptool, rkImageMaker) stanno nel submodule `vendor`, quindi gia' dentro
# l'albero: per costruire NON serve l'SDK Luckfox.
#
# L'SDK resta utile solo per due cose fuori dalla build: rigenerare i mirror
# con docs/mk-vendor-mirror.sh, e confrontare gli artefatti con i suoi in
# docs/check-artifacts.sh. Se la directory esiste viene montata read-only, se
# non c'e' non succede niente.
SDK_DIR      ?= $(HOME)/git/luckfox-lyra
SDK_MOUNT    := $(if $(wildcard $(SDK_DIR)),-v $(SDK_DIR):/sdk:ro,)

DOCKER       ?= docker
IMAGE        ?= rk3506-framework:build
UID          := $(shell id -u)
GID          := $(shell id -g)
TTY          := $(shell [ -t 0 ] && echo -t)

# Marcatore piantato dal Dockerfile: se c'e', siamo gia' dentro e i comandi
# girano diretti invece di annidare un altro container.
IN_CONTAINER := $(wildcard /.lyra-container)

DOCKER_RUN = $(DOCKER) run --rm -i $(TTY) \
	-v $(TOPDIR):/work \
	$(SDK_MOUNT) \
	-u $(UID):$(GID) \
	-w /work $(IMAGE)

BRMAKE = $(MAKE) -C $(BUILDROOT) O=$(O) BR2_EXTERNAL=$(BR2_EXTERNAL)

.PHONY: all shell image defconfigs help

ifeq ($(IN_CONTAINER),)
# ---------------------------------------------------- host: delega al container
all:
	@$(DOCKER_RUN) make

shell:
	@$(DOCKER_RUN) bash

%:
	@$(DOCKER_RUN) make $@

else
# ------------------------------------------------- container: chiama Buildroot
all:
	@$(BRMAKE)

shell:
	@echo "Sei gia' dentro il container di build."

%:
	@$(BRMAKE) $@

endif

# Evita che la regola catch-all provi a "ricostruire" il Makefile stesso.
Makefile: ;

# ------------------------------------------------------ non passano da Buildroot
image:
	$(DOCKER) build -t $(IMAGE) \
		--build-arg UID=$(UID) --build-arg GID=$(GID) $(TOPDIR)/docker

defconfigs:
	@echo "defconfig disponibili:"
	@ls -1 $(BR2_EXTERNAL)/configs | sed 's/^/  /'

help:
	@awk '/SPDX-License-Identifier|^# Copyright/{next} /^#$$/{next} \
	      /^#/{sub(/^# ?/,""); print; next} {exit}' $(firstword $(MAKEFILE_LIST))
