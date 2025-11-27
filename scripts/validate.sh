#!/bin/bash

# Validation script for PostgreSQL Backup to S3
# Checks all environment variables and connections before starting

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

log_ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    ((ERRORS++))
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((WARNINGS++))
}

log_info() {
    echo -e "[INFO] $1"
}

echo "=========================================="
echo "PostgreSQL Backup to S3 - Configuration Validation"
echo "=========================================="
echo ""

# ------------------------------------------
# 1. Check Required Environment Variables
# ------------------------------------------
echo "1. Checking environment variables..."

required_vars=(
    "POSTGRES_HOST"
    "POSTGRES_USER"
    "POSTGRES_PASSWORD"
    "POSTGRES_DATABASES"
    "S3_ENDPOINT"
    "S3_BUCKET"
    "S3_ACCESS_KEY"
    "S3_SECRET_KEY"
)

for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        log_error "$var is not set"
    else
        # Mask sensitive values
        if [[ "$var" == *"PASSWORD"* ]] || [[ "$var" == *"SECRET"* ]]; then
            log_ok "$var is set (****)"
        else
            log_ok "$var = ${!var}"
        fi
    fi
done

# Check optional variables
echo ""
echo "2. Checking optional settings..."

if [ -z "$S3_PREFIX" ]; then
    export S3_PREFIX="backups"
    log_info "S3_PREFIX not set, using default: backups"
else
    log_ok "S3_PREFIX = $S3_PREFIX"
fi

if [ -z "$POSTGRES_PORT" ]; then
    export POSTGRES_PORT="5432"
    log_info "POSTGRES_PORT not set, using default: 5432"
else
    log_ok "POSTGRES_PORT = $POSTGRES_PORT"
fi

if [ -z "$BACKUP_SCHEDULE" ]; then
    log_info "BACKUP_SCHEDULE not set, using default: 0 */2 * * *"
else
    log_ok "BACKUP_SCHEDULE = $BACKUP_SCHEDULE"
fi

if [ -z "$BACKUP_RETENTION_DAYS" ] || [ "$BACKUP_RETENTION_DAYS" -eq 0 ]; then
    log_info "BACKUP_RETENTION_DAYS = 0 (unlimited)"
else
    log_ok "BACKUP_RETENTION_DAYS = $BACKUP_RETENTION_DAYS days"
fi

# ------------------------------------------
# 2. Validate S3 Endpoint Format
# ------------------------------------------
echo ""
echo "3. Validating S3 endpoint..."

if [[ ! "$S3_ENDPOINT" =~ ^https?:// ]]; then
    log_error "S3_ENDPOINT must start with http:// or https://"
else
    log_ok "S3_ENDPOINT format is valid"
fi

# ------------------------------------------
# 3. Test PostgreSQL Connection
# ------------------------------------------
echo ""
echo "4. Testing PostgreSQL connection..."

if [ $ERRORS -eq 0 ]; then
    export PGPASSWORD="${POSTGRES_PASSWORD}"

    if pg_isready -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" > /dev/null 2>&1; then
        log_ok "PostgreSQL connection successful"

        # Test each database
        echo ""
        echo "5. Checking databases..."

        IFS=',' read -ra DBS <<< "${POSTGRES_DATABASES}"
        for db in "${DBS[@]}"; do
            db=$(echo "$db" | xargs)
            if [ -n "$db" ]; then
                if psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d "$db" -c "SELECT 1" > /dev/null 2>&1; then
                    log_ok "Database '$db' is accessible"
                else
                    log_error "Database '$db' is not accessible"
                fi
            fi
        done
    else
        log_error "Cannot connect to PostgreSQL at ${POSTGRES_HOST}:${POSTGRES_PORT}"
    fi
else
    log_warn "Skipping PostgreSQL connection test due to missing variables"
fi

# ------------------------------------------
# 4. Test S3 Connection
# ------------------------------------------
echo ""
echo "6. Testing S3 connection..."

if [ $ERRORS -eq 0 ]; then
    export AWS_ACCESS_KEY_ID="${S3_ACCESS_KEY}"
    export AWS_SECRET_ACCESS_KEY="${S3_SECRET_KEY}"

    # Test S3 bucket access
    if aws s3 ls "s3://${S3_BUCKET}" --endpoint-url "${S3_ENDPOINT}" > /dev/null 2>&1; then
        log_ok "S3 bucket '${S3_BUCKET}' is accessible"
    else
        log_error "Cannot access S3 bucket '${S3_BUCKET}'. Check credentials and bucket name."
    fi
else
    log_warn "Skipping S3 connection test due to missing variables"
fi

# ------------------------------------------
# Summary
# ------------------------------------------
echo ""
echo "=========================================="
echo "Validation Summary"
echo "=========================================="

if [ $ERRORS -gt 0 ]; then
    echo -e "${RED}FAILED${NC}: $ERRORS error(s), $WARNINGS warning(s)"
    echo ""
    echo "Please fix the errors above and try again."
    exit 1
else
    if [ $WARNINGS -gt 0 ]; then
        echo -e "${YELLOW}PASSED${NC} with $WARNINGS warning(s)"
    else
        echo -e "${GREEN}PASSED${NC}: All checks successful"
    fi
    echo ""
    echo "Configuration is valid. Ready to start backup service."
    exit 0
fi
