# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

ARG BUILDER_IMAGE
FROM ${BUILDER_IMAGE} AS builder

ARG BUILD_JOBS=8

COPY source.lock target.lock /usr/local/share/static_bins/binutils/
COPY sources /usr/local/share/static_bins/binutils/sources
COPY fixture.c archive-member.c /usr/local/share/static_bins/binutils/
COPY compile-in-container.sh /usr/local/bin/compile-static-binutils

RUN /usr/local/bin/compile-static-binutils

COPY relink-in-container.sh /usr/local/bin/relink-static-binutils

RUN /usr/local/bin/relink-static-binutils

COPY licenses /usr/local/share/licenses/binutils
COPY validate-elf.sh /usr/local/bin/validate-binutils-elf
COPY package-in-container.sh /usr/local/bin/package-static-binutils

RUN TARGET_LOCK=/usr/local/share/static_bins/binutils/target.lock \
    /usr/local/bin/package-static-binutils

FROM scratch AS artifact

COPY --from=builder /out/objdump /objdump
COPY --from=builder /out/fixture.o /fixture.o
