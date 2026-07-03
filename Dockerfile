# Thin extension of the pinned upstream Hermes Agent image: adds the CLI tools our SRE
# skills call directly via shell scripts (kubectl, jq, curl). Everything else — behavior,
# config, skills — still comes from mounted volumes, not this image, per plan.md's "configure,
# don't rebuild" approach. This keeps the stack reproducible (Constitution Principle IV) while
# supplying tooling the base image doesn't ship.
#
# NOTE: curl is kept (not purged after use) — propose-fix.sh calls Ollama directly via curl at
# runtime. An earlier version purged it right after downloading kubectl, which silently broke
# every "Suggested fix" (found live: every alert fell back to the canned per-type template).
FROM nousresearch/hermes-agent:v2026.6.5

ARG KUBECTL_VERSION=v1.31.0

RUN apt-get update && \
    apt-get install -y --no-install-recommends curl jq ca-certificates && \
    curl -fsSL -o /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/$(dpkg --print-architecture)/kubectl" && \
    chmod +x /usr/local/bin/kubectl && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*
