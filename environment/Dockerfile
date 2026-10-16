# syntax=docker/dockerfile:1
# Foundry image used to compile syzygy smart-contracts and grade audit tasks.
# Repository history is mounted or copied at runtime so each task can check out
# its own vulnerable commit. Do not bake hidden tests or reference patches in.
FROM ghcr.io/foundry-rs/foundry:stable

USER root
# Ubuntu 22.04's default python3 is 3.10. SWE-ReX needs 3.11, and the image
# entrypoint must stay empty so `docker run image /bin/sh -c ...` is not
# swallowed by `/bin/sh -c`.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git patch python3.11 \
    && rm -rf /var/lib/apt/lists/* \
    && curl -sS https://bootstrap.pypa.io/get-pip.py | python3.11 \
    && python3.11 -m pip install --no-cache-dir 'swe-rex==1.4.0' \
    && swerex-remote --version \
    && ln -sf /usr/bin/python3.11 /usr/bin/python3

# Foundry libraries are copied into each task checkout from
# environment/forge-libs. They are not baked into this image.
WORKDIR /testbed
ENTRYPOINT []
CMD ["/bin/bash"]
