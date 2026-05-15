# ========================================================
# Stage: Frontend (Vite)
# ========================================================
FROM --platform=$BUILDPLATFORM node:22-alpine AS frontend
WORKDIR /src/frontend
COPY frontend/package.json frontend/package-lock.json ./
RUN --mount=type=cache,target=/root/.npm \
    npm ci
COPY frontend/ ./
COPY web/translation /src/web/translation
RUN npm run build

# ========================================================
# Stage: Builder
# ========================================================
FROM golang:1.26-alpine AS builder
WORKDIR /app
ARG TARGETARCH

RUN apk --no-cache --update add \
  build-base \
  gcc \
  curl \
  unzip \
  dos2unix \
  upx

# Optimize Go dependency caching
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

COPY . .
COPY --from=frontend /src/web/dist ./web/dist

RUN dos2unix DockerInit.sh DockerEntrypoint.sh x-ui.sh \
  && chmod +x DockerInit.sh DockerEntrypoint.sh x-ui.sh

ENV CGO_ENABLED=1
ENV CGO_CFLAGS="-D_LARGEFILE64_SOURCE"

# Optimize build with Go compiler cache mounts
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go build -ldflags "-w -s" -o build/x-ui main.go

RUN ./DockerInit.sh "$TARGETARCH"

# Compress binaries to minimize final image size
RUN upx -9 build/x-ui build/bin/xray-linux-*

# ========================================================
# Stage: Final Image of 3x-ui
# ========================================================
FROM alpine
ENV TZ=Asia/Ho_Chi_Minh
WORKDIR /app

# Combine installation and configuration layers
RUN apk add --no-cache --update \
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

# Copy build artifacts with executable permissions directly
COPY --chmod=755 --from=builder /app/build/ /app/
COPY --chmod=755 --from=builder /app/DockerEntrypoint.sh /app/
COPY --chmod=755 --from=builder /app/x-ui.sh /usr/bin/x-ui
COPY --from=builder /app/web/translation /app/web/translation

ENV XUI_ENABLE_FAIL2BAN="true"
EXPOSE 2053
VOLUME [ "/etc/x-ui" ]
CMD [ "./x-ui" ]
ENTRYPOINT [ "/app/DockerEntrypoint.sh" ]