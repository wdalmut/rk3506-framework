# Ambiente di build per Luckfox Lyra Plus (RK3506G2).
#
# Perche' un container e non l'host
# --------------------------------
# Non e' un requisito di Buildroot, che compila benissimo su una distro
# recente. E' il pinning delle dipendenze host del BSP vendor:
#
#   - U-Boot 2017.09 Rockchip non compila con gcc host >= 14;
#   - la stessa U-Boot pretende python2 (device/rockchip/common/scripts/
#     check-loader.sh e' un gate incondizionato), che le distro correnti
#     non impacchettano piu'.
#
# Ubuntu 22.04 e' l'ultima release che ha entrambi come pacchetti.
#
# Cosa NON serve, contrariamente al Dockerfile dell'SDK
# ----------------------------------------------------
# Il Dockerfile dell'SDK Luckfox installa gcc-multilib e g++-multilib. La
# ricognizione (docs/BOARD-FACTS.md §1c) ha passato `file` su ogni tool di
# rkbin/tools e tools/linux/Linux_Pack_Firmware/rockdev: sono tutti x86-64.
# L'unico binario a 32 bit e' `firmwareMerger`, che NON e' nella catena di
# packaging (update.img usa afptool + rkImageMaker, entrambi x86-64 statici).
# Quindi niente multilib e niente libc6:i386.
#
# Sono state tolte anche le dipendenze degli stack che questo porting non
# costruisce: qemu-user-static, live-build, binfmt-support, scons, texinfo,
# expect, patchelf, chrpath, cpp-aarch64-linux-gnu.
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      # --- richiesti da Buildroot (docs/manual: "System requirements") ---
      bc build-essential ca-certificates cpio file git rsync unzip wget \
      bzip2 cpio gzip perl sed tar xz-utils \
      libncurses-dev \
      python3 python-is-python3 \
      # --- richiesti dal kernel vendor 6.1 ---
      bison flex libssl-dev libelf-dev \
      # --- richiesti da U-Boot 2017.09 Rockchip ---
      #     python2: check-loader.sh e gli script in tools/ (binman, dtoc)
      #     device-tree-compiler: make.sh aborta senza `dtc` nel PATH
      python2 device-tree-compiler swig \
      # --- richiesti dalla catena di packaging Rockchip ---
      #     liblz4-tool/lz4: compressione FIT
      #     bsdextrautils: hexdump, con cui post-image.sh ricava il tag del
      #       loader (RK350F) leggendo 4 byte a offset 21 di MiniLoaderAll.bin,
      #       esattamente come mk-updateimg.sh dell'SDK. In Ubuntu 22.04
      #       hexdump non e' piu' in bsdmainutils.
      #     util-linux: rev, usato sullo stesso tag
      #     gdisk: per il flash su SD in bring-up
      liblz4-tool bsdextrautils util-linux gdisk \
 && rm -rf /var/lib/apt/lists/*

# Marcatore letto dal Makefile per capire se e' gia' dentro il container.
RUN touch /.lyra-container && chmod 0444 /.lyra-container

# L'utente e' allineato a quello dell'host cosi' che output/ resti di sua
# proprieta' e non servano sudo o chown dopo ogni build.
ARG UID=1000
ARG GID=1000
RUN groupadd -g $GID builder 2>/dev/null || true \
 && useradd -m -u $UID -g $GID builder 2>/dev/null || true

# Buildroot rifiuta di girare come root ("You seem to have the current
# working directory in your PATH environment variable" / do-not-run-as-root),
# e comunque lavorare da root sui file dell'host e' una pessima idea.
USER $UID:$GID
ENV HOME=/tmp
WORKDIR /work
