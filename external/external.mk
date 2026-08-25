################################################################################
#
# Luckfox Lyra Plus (RK3506G2) — external tree
#
# I package di questo albero vivono in package/<nome>/<nome>.mk.
#
# Nota: la catena di packaging Rockchip (loader, uboot.img, boot.img,
# update.img) NON sta qui. Vive in board/lyra-plus/post-image.sh, perche'
# gira dopo che Buildroot ha prodotto kernel, U-Boot e rootfs.ubi, e
# dipende da binari vendor esterni all'albero (rkbin, afptool).
#
################################################################################

include $(sort $(wildcard $(BR2_EXTERNAL_LYRA_PLUS_PATH)/package/*/*.mk))
