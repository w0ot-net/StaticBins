# syntax=docker/dockerfile:1

ARG BUILDER_IMAGE
FROM ${BUILDER_IMAGE} AS builder

COPY build-in-container.sh /usr/local/bin/build-sqlite3
COPY source.lock target.lock validate-elf.sh /usr/local/share/static_bins/sqlite3/
COPY sources/ /usr/local/share/static_bins/sqlite3/sources/
COPY licenses/ /usr/local/share/licenses/sqlite3/

RUN /usr/local/bin/build-sqlite3

FROM scratch AS artifact
COPY --from=builder /out/sqlite3 /sqlite3
