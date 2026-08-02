FROM --platform=$BUILDPLATFORM golang:1.26-alpine AS build

ARG TARGETOS
ARG TARGETARCH

WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY cmd ./cmd
COPY internal ./internal
COPY prompts ./prompts
COPY content ./content

RUN go test ./...
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go build -trimpath -ldflags='-s -w' -o /culturelens-api ./cmd/api && \
    CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go build -trimpath -ldflags='-s -w' -o /culturelens-db ./cmd/db && \
    CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go build -trimpath -ldflags='-s -w' -o /culturelens-content ./cmd/content

FROM alpine:3.22

RUN apk add --no-cache ca-certificates \
    && addgroup -S -g 10001 culturelens \
    && adduser -S -D -H -u 10001 -G culturelens culturelens

WORKDIR /app

COPY --from=build --chown=10001:10001 /culturelens-api ./culturelens-api
COPY --from=build --chown=10001:10001 /culturelens-db ./culturelens-db
COPY --from=build --chown=10001:10001 /culturelens-content ./culturelens-content
COPY --from=build --chown=10001:10001 /src/prompts ./prompts
COPY --from=build --chown=10001:10001 /src/content ./content

ENV PORT=8080

USER 10001:10001
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -q -O /dev/null "http://127.0.0.1:${PORT}/health" || exit 1

ENTRYPOINT ["./culturelens-api"]
