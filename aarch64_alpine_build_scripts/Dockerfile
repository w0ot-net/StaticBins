# syntax=docker/dockerfile:1

FROM alpine:3.24.1@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b

LABEL org.opencontainers.image.source="https://github.com/w0ot-net/static_bins" \
      org.opencontainers.image.description="Reusable AArch64 Alpine toolchain for static_bins build recipes"

RUN apk add --no-cache \
    autoconf \
    automake \
    bash \
    bison \
    build-base \
    ca-certificates \
    cmake \
    curl \
    expat-dev \
    expat-static \
    file \
    flex \
    git \
    gmp-dev \
    gmp-static \
    libtool \
    linux-headers \
    mpfr-dev \
    ncurses-dev \
    ncurses-static \
    ninja \
    patch \
    perl \
    pkgconf \
    python3 \
    tar \
    texinfo \
    wget \
    xz \
    xz-dev \
    xz-static \
    zlib-dev \
    zlib-static \
    zstd-dev \
    zstd-static

WORKDIR /workspace
CMD ["/bin/bash"]
