# syntax=docker/dockerfile:1
FROM ghcr.io/foundry-rs/foundry@sha256:043752653d5be351c71709091b3db97c4421c907eb40ea294195e7f532aadf46
USER root
ENV FOUNDRY_DISABLE_NIGHTLY_WARNING=1 \
    FOUNDRY_FFI=false \
    FOUNDRY_FUZZ_SEED=0x1
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git python3 \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL https://downloads.claude.ai/claude-code-releases/bootstrap.sh | bash -s -- \
    && install -m 0755 "$(readlink -f /root/.local/bin/claude)" /usr/local/bin/claude \
    && /usr/local/bin/claude --version
# The audited remappings.txt files expect these libraries under lib/.
RUN set -eu; lib=/app/smart-contracts/lib; \
    fetch() { \
      git init -q "$lib/$1"; \
      git -C "$lib/$1" fetch -q --depth 1 "https://github.com/$2.git" "$3"; \
      git -C "$lib/$1" checkout -q FETCH_HEAD; \
      git -C "$lib/$1" submodule -q update --init --recursive --depth 1; \
    }; \
    fetch forge-std foundry-rs/forge-std f3dae6e6ee381f25eb6a246f7da9b85c91a68219; \
    fetch openzeppelin-contracts OpenZeppelin/openzeppelin-contracts 01ef448981be9d20ca85f2faf6ebdf591ce409f3; \
    fetch openzeppelin-contracts-upgradeable OpenZeppelin/openzeppelin-contracts-upgradeable fbdb824a735891908d5588b28e0da5852d7ed7ba; \
    fetch openzeppelin-foundry-upgrades OpenZeppelin/openzeppelin-foundry-upgrades 332bd3306242e09520df2685b2edb99ebd7f5d37; \
    fetch solidity-stringutils Arachnid/solidity-stringutils 4b2fcc43fa0426e19ce88b1f1ec16f5903a2e461; \
    find "$lib" -type l -exec sh -c 'for link; do cp --remove-destination "$(readlink -f "$link")" "$link"; done' sh {} +; \
    find "$lib" -depth \( -name .git -o -name .github -o -name test -o -name audits -o -name certora -o -name docs -o -name '*.pdf' \) -exec rm -rf {} +
COPY app/ /app/
RUN chown -R foundry:foundry /app
USER foundry
WORKDIR /app/smart-contracts
RUN forge build \
    && { forge test --json > /tmp/baseline.json || true; } \
    && python3 -c 'import json; json.load(open("/tmp/baseline.json"))'
USER root
# The verifier compiles with a root-owned copy of solc, not the agent-writable ~/.svm.
RUN install -d -m 0755 /opt/eclipse \
    && cp -a /home/foundry/.svm /opt/eclipse/svm \
    && chown -R root:root /opt/eclipse/svm \
    && install -m 0444 /tmp/baseline.json /opt/eclipse/baseline.json \
    && rm /tmp/baseline.json \
    && { find test script lib -type f -print0; printf '%s\0' foundry.toml remappings.txt; } \
       | sort -z | xargs -0 sha256sum > /opt/eclipse/protected.sha256 \
    && chmod 0444 /opt/eclipse/protected.sha256 \
    && cp -r src /opt/eclipse/src \
    && chown -R root:root /opt/eclipse/src
# The container's main process stays root so the verifier can kill every agent
# process without stopping the container. task.toml runs the agent as foundry.
WORKDIR /app
ENTRYPOINT []
CMD ["/bin/bash"]
