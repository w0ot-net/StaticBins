# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

ARG BUILDER_IMAGE
FROM ${BUILDER_IMAGE} AS builder

ARG BUILD_JOBS=8

COPY source.lock /usr/local/share/static_bins/rsync/source.lock
COPY sources /usr/local/share/static_bins/rsync/sources
COPY licenses /usr/local/share/licenses/rsync
COPY validate-elf.sh /usr/local/bin/validate-rsync-elf
COPY build-in-container.sh /usr/local/bin/build-static-rsync

RUN /usr/local/bin/build-static-rsync

FROM scratch AS artifact

COPY --from=builder /out/rsync /rsync
