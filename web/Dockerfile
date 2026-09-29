# Build on the CI machine's own architecture (fast), serve with unprivileged nginx on any.
FROM --platform=$BUILDPLATFORM node:24.21.0-alpine AS build
WORKDIR /src
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM nginxinc/nginx-unprivileged:1.31.6-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /src/dist /usr/share/nginx/html
