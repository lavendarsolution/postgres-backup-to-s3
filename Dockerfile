FROM alpine:3.19

LABEL maintainer="Lavendar Solution <lavendarsolution@email.com>"
LABEL description="PostgreSQL backup to S3-compatible storage (Digital Ocean Spaces, AWS S3, MinIO)"
LABEL version="1.0.0"

# Install dependencies
RUN apk add --no-cache \
    postgresql16-client \
    aws-cli \
    bash \
    tzdata \
    curl \
    && rm -rf /var/cache/apk/*

# Create backup directory
RUN mkdir -p /backup /scripts

# Copy scripts
COPY scripts/*.sh /scripts/

# Make scripts executable
RUN chmod +x /scripts/*.sh

# Set timezone (can be overridden by TZ env var)
ENV TZ=UTC

# Health check
HEALTHCHECK --interval=5m --timeout=10s --start-period=10s --retries=3 \
    CMD /scripts/healthcheck.sh

ENTRYPOINT ["/scripts/entrypoint.sh"]
