# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 Corley S.r.l.
################################################################################
#
# rk-resource-tool
#
# `resource_tool` di Rockchip, compilato per l'host. Impacchetta un DTB (e,
# opzionalmente, i logo BMP) nel formato `RSCE` che U-Boot si aspetta nella
# partizione/immagine `resource`.
#
# Esiste solo come host package: nulla di questo finisce nel target.
#
# Provenienza e licenza del sorgente: README.md di questa directory.
# Il sorgente NON e' di questo progetto: e' scripts/resource_tool.c del kernel
# vendor 6.1, che mainline non ha (vedi README.md, "Perche' non basta il
# kernel").
#
################################################################################

# Non e' una versione upstream: e' il commit del kernel vendor da cui il
# sorgente e' stato preso. Alzarlo significa ricopiare il file e aggiornare
# resource_tool.sha256 e README.md.
RK_RESOURCE_TOOL_VERSION = 73bca17b67938d649b072408780369f600555263
RK_RESOURCE_TOOL_SITE = $(BR2_EXTERNAL_LYRA_PLUS_PATH)/package/rk-resource-tool/src
RK_RESOURCE_TOOL_SITE_METHOD = local
RK_RESOURCE_TOOL_LICENSE = GPL-2.0+
# Il file porta la propria intestazione SPDX e il copyright Rockchip: e' lui
# stesso il documento di licenza. Non c'e' un COPYING da copiare, perche' non
# stiamo vendorizzando un progetto ma un singolo file.
RK_RESOURCE_TOOL_LICENSE_FILES = resource_tool.c

# Un solo file, nessun build system: niente autotools, niente CMake.
# -Wno-declaration-after-statement e' l'unico flag che il kernel gli aggiunge
# (scripts/Makefile:18) e serve davvero: il file dichiara variabili a meta'
# blocco.
define HOST_RK_RESOURCE_TOOL_BUILD_CMDS
	$(HOSTCC) $(HOST_CFLAGS) $(HOST_LDFLAGS) \
		-Wno-declaration-after-statement \
		-o $(@D)/resource_tool $(@D)/resource_tool.c
endef

define HOST_RK_RESOURCE_TOOL_INSTALL_CMDS
	$(INSTALL) -D -m 0755 $(@D)/resource_tool $(HOST_DIR)/bin/resource_tool
endef

$(eval $(host-generic-package))
