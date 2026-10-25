# astraOS build environment for sweet: Alpine Linux, aarch64.
# Native on arm64 hosts; on x86_64 it runs through qemu-user (binfmt).
FROM alpine:3.22

COPY scripts/build-deps.txt /tmp/build-deps.txt
RUN apk add --no-cache $(grep -v '^#' /tmp/build-deps.txt) \
    && ln -sf /usr/bin/samu /usr/bin/ninja

WORKDIR /work/device
