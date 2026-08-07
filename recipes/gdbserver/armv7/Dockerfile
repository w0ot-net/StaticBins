# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

ARG BUILDER_IMAGE
FROM ${BUILDER_IMAGE} AS builder

ARG BUILD_JOBS=8

COPY source.lock /usr/local/share/static_bins/gdbserver/source.lock
COPY sources /usr/local/share/static_bins/gdbserver/sources
COPY licenses /usr/local/share/licenses/gdbserver
COPY build-in-container.sh /usr/local/bin/build-static-gdbserver

RUN /usr/local/bin/build-static-gdbserver

FROM ${BUILDER_IMAGE} AS smoke-tools

COPY vm-smoke.c /tmp/vm-smoke.c
COPY smoke-target.c /tmp/smoke-target.c

RUN cc -O2 -Wall -Wextra -Werror -static -no-pie \
        -o /vm-smoke /tmp/vm-smoke.c \
    && cc -O2 -Wall -Wextra -Werror -static -no-pie \
        -o /smoke-target /tmp/smoke-target.c \
    && strip /vm-smoke /smoke-target

FROM scratch AS artifact

COPY --from=builder /out/gdbserver /gdbserver
COPY --from=smoke-tools /vm-smoke /vm-smoke
COPY --from=smoke-tools /smoke-target /smoke-target
