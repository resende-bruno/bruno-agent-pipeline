# Minimal work-container image: slim Node base + git + the coding agent CLI.
# Rebuild with --no-cache when you need a newer CLI version (new models often require one).
FROM node:22-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://claude.ai/install.sh | bash
ENV PATH="/root/.local/bin:${PATH}"

WORKDIR /workspace
ENTRYPOINT ["claude"]
