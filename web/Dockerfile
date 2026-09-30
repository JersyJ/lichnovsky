# syntax=docker/dockerfile:1

# Build on the CI machine's own architecture (fast); the output is plain static files.
FROM --platform=$BUILDPLATFORM node:24.21.0-alpine AS build

WORKDIR /src

# Dependencies first, from the lock file only, so this layer is reused until they change.
RUN --mount=type=bind,source=package.json,target=package.json \
    --mount=type=bind,source=package-lock.json,target=package-lock.json \
    --mount=type=cache,target=/root/.npm \
    npm ci --no-audit --no-fund

COPY . .

RUN npm run build

# The slim nginx: core modules only (no njs, perl, image filters or curl), ~6 MB compressed.
# Runs as the unprivileged nginx user (101), listens on 8080, keeps its pid and temp files in /tmp.
FROM nginxinc/nginx-unprivileged:1.31.6-alpine-slim AS runtime

COPY --link nginx.conf /etc/nginx/conf.d/default.conf

COPY --link --from=build /src/dist /srv/site

# Check the pages exist and the config parses (the status host is resolved per request, so
# nothing needs to resolve here).
RUN <<EOT
set -e
test -s /srv/site/index.html
test -s /srv/site/404.html
nginx -t -q
rm -rf /tmp/*
EOT

EXPOSE 8080

# Start nginx directly: the image's entrypoint scripts (config templating, IPv6 rewrites) aren't
# used here and would only try to write to the read-only root filesystem.
ENTRYPOINT ["nginx"]

CMD ["-g", "daemon off;"]
