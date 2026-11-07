# vitals-ps3's build environment: RPCS3's PS3DK (GCC 16 for the PPU, PSL1GHT, prx-gen for PRX and
# SPRX modules), built from source at a pinned commit, as PS3DK only ships prebuilt for Windows.
#   docker build -t vitals-ps3-sdk .
#   docker run --rm -v "$PWD":/src -w /src vitals-ps3-sdk <command>
# Two stages: the toolchain is built in the first, with everything building it takes (about 25 GB:
# GCC's and binutils' build trees, their sources, Rust); the image is the second, the installed SDK
# with its host programs stripped, and only what running them needs (about 1 GB)
FROM ubuntu:24.04 AS builder

ARG PS3DK_REPOSITORY=https://github.com/FirebirdTA01/PS3DK
ARG PS3DK_COMMIT=85c35f1
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential gcc-12 g++-12 cmake ninja-build texinfo bison flex libgmp-dev libmpfr-dev \
        libmpc-dev libisl-dev zlib1g-dev libreadline-dev libncurses-dev libexpat1-dev libssl-dev \
        libelf-dev python3 python3-dev git wget curl ca-certificates patch autoconf automake libtool \
        zip unzip pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Rust 1.88+ for PS3DK's host tools (nidgen, prx-gen); Ubuntu's is too old
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal
ENV PATH=/root/.cargo/bin:$PATH

RUN git clone "$PS3DK_REPOSITORY" /opt/ps3dk-src && cd /opt/ps3dk-src && git checkout "$PS3DK_COMMIT"
WORKDIR /opt/ps3dk-src

# The toolchain, PSL1GHT and the SDK, in PS3DK's own order (env.sh sets PS3DEV and the prefixes)
RUN bash -c 'source scripts/env.sh && ./scripts/bootstrap.sh'
RUN bash -c 'source scripts/env.sh && ./scripts/build-ppu-toolchain.sh'
RUN bash -c 'source scripts/env.sh && ./scripts/build-spu-toolchain.sh'
RUN bash -c 'source scripts/env.sh && ./scripts/build-psl1ght.sh'
# The host tools first (nidgen, prx-gen, rsx-cg-compiler, sprx-linker): the SDK's own build needs
# rsx-cg-compiler, which build-sdk.sh would only install after it
RUN bash -c 'source scripts/env.sh && ./scripts/install-host-tools.sh'
RUN bash -c 'source scripts/env.sh && ./scripts/build-sdk.sh --no-host-tools'

# vitals' changes to PS3DK's tools (patches/): prx-gen rebuilt with them, in place of PS3DK's
#   prx-gen-split-segments.patch: a module with its code and data in separate segments, as Sony's.
#   TOC-relative accesses are checked against the TOC's segment rather than the instruction's,
#   branches against where the linked instruction goes (not the .opd descriptor its symbol names),
#   and .TOC. past the end of the data segment is relocated against it rather than frozen
# The sources go back as they were once it's installed: PS3DK's CMake refuses a "dirty" source tree
# (its version, from git, no longer matches the installed SDK's)
COPY patches /opt/vitals-patches
RUN bash -c 'source scripts/env.sh && git apply /opt/vitals-patches/prx-gen-split-segments.patch && \
    (cd tools && cargo build --release -p prx-gen) && install -m 0755 tools/target/release/prx-gen "$PS3DEV/bin/prx-gen" && \
    git apply -R /opt/vitals-patches/prx-gen-split-segments.patch && test -z "$(git status --porcelain)"'

# What the image doesn't need: the build trees (/root/ps3tc), the downloaded sources and the Rust
# target directory (both git-ignored, so PS3DK's checkout stays clean for its CMake's check), and
# the host programs' symbols (strip: only this machine's own ELF files, never the PPU's and SPU's)
RUN rm -rf /root/ps3tc src/upstream tools/target && \
    find stage -type f -exec sh -c 'file -b "$1" | grep -q "ELF.*$(uname -m | sed s/arm64/aarch64/)" && strip --strip-unneeded "$1" || true' _ {} \; && \
    test -z "$(git status --porcelain)"

FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
# CMake, Ninja and patch (vitals-ssl/crypto's Mbed TLS patches) for vitals' builds, Python and git
# for PS3DK's scripts (env.sh's SOURCE_DATE_EPOCH, its CMake's installed-SDK check), and the
# libraries PS3DK's host programs (GCC, binutils, the PKG and SFO tools) are linked with
RUN apt-get update && apt-get install -y --no-install-recommends \
        cmake ninja-build make python3 git ca-certificates patch \
        libgmp10 libmpfr6 libmpc3 libisl23 zlib1g libzstd1 libelf1t64 libexpat1 libssl3t64 \
        libpython3.12t64 libreadline8t64 libncursesw6 libstdc++6 \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /opt/ps3dk-src /opt/ps3dk-src
WORKDIR /opt/ps3dk-src
RUN git config --global --add safe.directory /opt/ps3dk-src

# Every later shell gets the toolchain
RUN echo 'source /opt/ps3dk-src/scripts/env.sh' >> /root/.bashrc
SHELL ["/bin/bash", "-lc"]
