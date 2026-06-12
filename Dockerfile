# ========================================================
# Stage 1: Frontend (Vite)
# ========================================================
FROM --platform=$BUILDPLATFORM node:22-alpine AS frontend
WORKDIR /src/frontend

COPY frontend/package.json frontend/package-lock.json ./
RUN --mount=type=cache,target=/root/.npm \
    npm ci --no-audit --no-fund

COPY frontend/ ./
COPY internal/web/translation /src/internal/web/translation
RUN npm run build

# ========================================================
# Stage 2: Go Builder
# ========================================================
FROM golang:1.26-alpine AS builder
WORKDIR /app
ARG TARGETARCH

RUN apk add --no-cache \
  build-base \
  curl \
  unzip \
  dos2unix \
  upx

# Cache Go modules separately from source code
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

COPY . .
COPY --from=frontend /src/internal/web/dist ./internal/web/dist

# Fix line endings for shell scripts (Windows checkout safety)
RUN dos2unix DockerInit.sh DockerEntrypoint.sh x-ui.sh \
  && chmod +x DockerInit.sh DockerEntrypoint.sh x-ui.sh

ENV CGO_ENABLED=1
ENV CGO_CFLAGS="-D_LARGEFILE64_SOURCE"

# Build with Go compiler + module cache mounts
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go build -ldflags "-w -s" -o build/x-ui main.go

# Download Xray + geo assets
RUN ./DockerInit.sh "$TARGETARCH"

# Compress binaries to minimize final image (~60-70% smaller)
RUN upx --best --lzma build/x-ui build/bin/xray-linux-* build/bin/mtg-linux-*

# ========================================================
# Stage 3: Final minimal image
# ========================================================
FROM alpine AS final
ENV TZ=Asia/Ho_Chi_Minh
WORKDIR /app

# Single layer: install packages + configure fail2ban
RUN apk add --no-cache \
  ca-certificates \
  tzdata \
  fail2ban \
  bash \
  curl \
  openssl \
  && rm -f /etc/fail2ban/jail.d/alpine-ssh.conf \
  && cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local \
  && sed -i "s/^\[ssh\]$/&\nenabled = false/" /etc/fail2ban/jail.local \
  && sed -i "s/^\[sshd\]$/&\nenabled = false/" /etc/fail2ban/jail.local \
  && sed -i "s/#allowipv6 = auto/allowipv6 = auto/g" /etc/fail2ban/fail2ban.conf

# Copy build artifacts with permissions set inline (saves a chmod layer)
COPY --chmod=755 --from=builder /app/build/              /app/
COPY --chmod=755 --from=builder /app/DockerEntrypoint.sh  /app/
COPY --chmod=755 --from=builder /app/x-ui.sh              /usr/bin/x-ui
COPY              --from=builder /app/internal/web/translation /app/internal/web/translation

ENV XUI_IN_DOCKER="true"
ENV XUI_MAIN_FOLDER="/app"
ENV XUI_ENABLE_FAIL2BAN="true"
ENV XUI_DB_TYPE=""
ENV XUI_DB_DSN=""

EXPOSE 2053
VOLUME [ "/etc/x-ui" ]
ENTRYPOINT [ "/app/DockerEntrypoint.sh" ]
CMD [ "./x-ui" ]
