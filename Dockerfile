# astraOS build environment for sweet: Alpine Linux, aarch64.
# Native on arm64 hosts; on x86_64 it runs through qemu-user (binfmt).
FROM alpine:3.24

COPY scripts/build-deps.txt /tmp/build-deps.txt
# The mounted source trees belong to the host user, not to root: git must
# still work in them.
RUN apk add --no-cache $(grep -v '^#' /tmp/build-deps.txt) \
    && ln -sf /usr/bin/samu /usr/bin/ninja \
    && git config --system --add safe.directory '*'

WORKDIR /work/device
