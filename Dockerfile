ARG PLAYWRIGHT_BROWSERS_PATH=/ms-playwright

# ------------------------------
# Base
# ------------------------------
# Base stage: Contains only the minimal dependencies required for runtime
# (node_modules and Playwright system dependencies)
FROM node:22-bookworm-slim AS base

ARG PLAYWRIGHT_BROWSERS_PATH
ENV PLAYWRIGHT_BROWSERS_PATH=${PLAYWRIGHT_BROWSERS_PATH}

# Set the working directory
WORKDIR /app

RUN --mount=type=cache,target=/root/.npm,sharing=locked,id=npm-cache \
    --mount=type=bind,source=package.json,target=package.json \
    --mount=type=bind,source=package-lock.json,target=package-lock.json \
  npm ci --omit=dev && \
  # Install system dependencies for playwright
  npx -y playwright-core install-deps chromium

# ------------------------------
# Builder
# ------------------------------
FROM base AS builder

RUN --mount=type=cache,target=/root/.npm,sharing=locked,id=npm-cache \
    --mount=type=bind,source=package.json,target=package.json \
    --mount=type=bind,source=package-lock.json,target=package-lock.json \
  npm ci

# Copy the rest of the app
COPY *.json *.js *.ts .

# ------------------------------
# Browser
# ------------------------------
# Cache optimization:
# - Browser is downloaded only when node_modules or Playwright system dependencies change
# - Cache is reused when only source code changes
FROM base AS browser

RUN npx -y playwright-core install --no-shell chromium

# ------------------------------
# Runtime
# ------------------------------
FROM base

ARG PLAYWRIGHT_BROWSERS_PATH
ARG USERNAME=node
ENV NODE_ENV=production
ENV PLAYWRIGHT_MCP_OUTPUT_DIR=/tmp/playwright-output

## Default container port. This will be used when neither WEBSITES_PORT (Azure) nor
## a runtime PORT environment variable is provided. Azure App Service sets
## WEBSITES_PORT for container applications when it needs to route traffic to a
## non-standard port.
ENV PORT=8080

# Set the correct ownership for the runtime user on production `node_modules`
RUN chown -R ${USERNAME}:${USERNAME} node_modules

USER ${USERNAME}

## Expose common ports that might be used by this image. We expose the original
## default (8080) and the legacy port (8931) so the intent is clear in the image
## metadata. Azure will still route to whatever port is set in `WEBSITES_PORT`.
EXPOSE 8080 8931

COPY --from=browser --chown=${USERNAME}:${USERNAME} ${PLAYWRIGHT_BROWSERS_PATH} ${PLAYWRIGHT_BROWSERS_PATH}
COPY --chown=${USERNAME}:${USERNAME} cli.js package.json ./

# Run in headless and only with chromium (other browsers need more dependencies not included in this image)
# Use --host and --port (supported flags) instead of the unsupported --listen flag.
ENTRYPOINT ["/bin/sh", "-c", "PORT_TO_USE=${WEBSITES_PORT:-${PORT:-8080}}; echo \"Starting mcp-server on 0.0.0.0:${PORT_TO_USE}\"; node cli.js --headless --browser chromium --no-sandbox --host 0.0.0.0 --port ${PORT_TO_USE}"]

# Copy a lightweight healthcheck script and register Docker HEALTHCHECK. The
# healthcheck queries /mcp on the chosen port (WEBSITES_PORT -> PORT -> 8080).
COPY --chown=${USERNAME}:${USERNAME} healthcheck.js ./
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD node ./healthcheck.js || exit 1
