#!/bin/bash
set -e

# Colors for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Default schedule: every 2 hours (0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22)
BACKUP_SCHEDULE="${BACKUP_SCHEDULE:-0 */2 * * *}"

log_info "=========================================="
log_info "PostgreSQL Backup to S3"
log_info "=========================================="

# Set default S3 prefix if not provided
export S3_PREFIX="${S3_PREFIX:-backups}"

# Run validation
log_info "Validating configuration..."
echo ""

if ! /scripts/validate.sh; then
    log_error "Configuration validation failed. Please check your .env file."
    exit 1
fi

echo ""
log_info "=========================================="
log_info "Configuration Summary"
log_info "=========================================="
log_info "Timezone: ${TZ:-UTC}"
log_info "Schedule: ${BACKUP_SCHEDULE}"
log_info "Databases: ${POSTGRES_DATABASES}"
log_info "S3 Endpoint: ${S3_ENDPOINT}"
log_info "S3 Bucket: ${S3_BUCKET}"
log_info "S3 Prefix: ${S3_PREFIX}"
log_info "Retention: ${BACKUP_RETENTION_DAYS:-0} days (0=unlimited)"
log_info "=========================================="

# Run backup on start if enabled
if [ "${BACKUP_ON_START}" = "true" ]; then
    log_info "BACKUP_ON_START is enabled, running initial backup..."
    /scripts/backup.sh || log_warn "Initial backup completed with warnings"
fi

# Create cron job
log_info "Setting up cron schedule: ${BACKUP_SCHEDULE}"

# Export all environment variables for cron
printenv | grep -E "^(POSTGRES_|S3_|BACKUP_|TZ)" > /etc/environment

# Create crontab
echo "${BACKUP_SCHEDULE} /scripts/backup.sh >> /var/log/backup.log 2>&1" > /etc/crontabs/root

# Create log file
touch /var/log/backup.log

log_info "Starting cron daemon..."
log_info "Backup service is now running. Next backup at scheduled time."

# Start cron in foreground and tail the log
crond -l 2 -f &

# Tail the log file to keep container running and show output
tail -f /var/log/backup.log
