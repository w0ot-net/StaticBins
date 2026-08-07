# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

ARG BUILDER_IMAGE
FROM ${BUILDER_IMAGE} AS builder

ARG BUILD_JOBS=8

COPY source.lock /usr/local/share/static_bins/gdb/source.lock
COPY sources /usr/local/share/static_bins/gdb/sources
COPY licenses /usr/local/share/licenses/gdb
COPY build-in-container.sh /usr/local/bin/build-static-gdb

RUN /usr/local/bin/build-static-gdb

COPY validate-in-container.sh /usr/local/bin/validate-static-gdb

RUN /usr/local/bin/validate-static-gdb

COPY smoke-target.c /tmp/smoke-target.c

RUN cc -O0 -g -Wall -Wextra -Werror -static -no-pie \
        -o /out/smoke-target /tmp/smoke-target.c

FROM scratch AS artifact

COPY --from=builder /out/gdb /gdb
COPY --from=builder /out/smoke-target /smoke-target
