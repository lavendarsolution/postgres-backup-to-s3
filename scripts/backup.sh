#!/bin/bash
set -e

# Colors for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Validate required environment variables
validate_env() {
    local required_vars=(
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
            log_error "Required environment variable $var is not set"
            exit 1
        fi
    done
}

# Configure AWS CLI for S3-compatible storage
configure_s3() {
    export AWS_ACCESS_KEY_ID="${S3_ACCESS_KEY}"
    export AWS_SECRET_ACCESS_KEY="${S3_SECRET_KEY}"

    # Create AWS config for endpoint
    mkdir -p ~/.aws
    cat > ~/.aws/config << EOF
[default]
s3 =
    endpoint_url = ${S3_ENDPOINT}
    signature_version = s3v4
EOF
}

# Backup a single database
backup_database() {
    local db_name="$1"
    local year=$(date '+%Y')
    local month=$(date '+%m')
    local day=$(date '+%d')
    local time=$(date '+%H-%M')
    local backup_file="${db_name}_${time}.sql.gz"
    local local_path="/backup/${backup_file}"
    local s3_path="s3://${S3_BUCKET}/${S3_PREFIX}/${db_name}/${year}/${month}/${day}/${time}.sql.gz"

    log_info "Starting backup for database: ${db_name}"

    # Create backup using pg_dump and compress with gzip
    PGPASSWORD="${POSTGRES_PASSWORD}" pg_dump \
        -h "${POSTGRES_HOST}" \
        -p "${POSTGRES_PORT:-5432}" \
        -U "${POSTGRES_USER}" \
        -d "${db_name}" \
        --no-owner \
        --no-acl \
        --clean \
        --if-exists \
        | gzip > "${local_path}"

    if [ $? -eq 0 ]; then
        local file_size=$(du -h "${local_path}" | cut -f1)
        log_info "Backup created: ${backup_file} (${file_size})"
    else
        log_error "Failed to create backup for ${db_name}"
        rm -f "${local_path}"
        return 1
    fi

    # Upload to S3
    log_info "Uploading to S3: ${s3_path}"
    aws s3 cp "${local_path}" "${s3_path}" --endpoint-url "${S3_ENDPOINT}"

    if [ $? -eq 0 ]; then
        log_info "Successfully uploaded: ${s3_path}"
        rm -f "${local_path}"
    else
        log_error "Failed to upload ${backup_file} to S3"
        rm -f "${local_path}"
        return 1
    fi

    return 0
}

# Delete old backups based on retention policy
cleanup_old_backups() {
    if [ -z "${BACKUP_RETENTION_DAYS}" ] || [ "${BACKUP_RETENTION_DAYS}" -eq 0 ]; then
        log_info "Backup retention is disabled (BACKUP_RETENTION_DAYS=0 or not set)"
        return 0
    fi

    log_info "Cleaning up backups older than ${BACKUP_RETENTION_DAYS} days"

    local cutoff_date=$(date -d "-${BACKUP_RETENTION_DAYS} days" '+%Y-%m-%d' 2>/dev/null || \
                        date -v-${BACKUP_RETENTION_DAYS}d '+%Y-%m-%d')

    # Parse databases
    IFS=',' read -ra DBS <<< "${POSTGRES_DATABASES}"

    for db_name in "${DBS[@]}"; do
        db_name=$(echo "${db_name}" | xargs)  # Trim whitespace
        log_info "Checking old backups for database: ${db_name}"

        # List and delete old files
        aws s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/${db_name}/" \
            --endpoint-url "${S3_ENDPOINT}" \
            --recursive 2>/dev/null | while read -r line; do

            # Extract date from path (format: PREFIX/DB/YYYY/MM/DD/file)
            file_path=$(echo "$line" | awk '{print $4}')
            if [ -n "$file_path" ]; then
                # Extract year/month/day from path
                year=$(echo "$file_path" | grep -oP '\d{4}(?=/\d{2}/\d{2})' | head -1)
                month=$(echo "$file_path" | grep -oP '(?<=\d{4}/)\d{2}(?=/\d{2})' | head -1)
                day=$(echo "$file_path" | grep -oP '(?<=\d{4}/\d{2}/)\d{2}' | head -1)

                if [ -n "$year" ] && [ -n "$month" ] && [ -n "$day" ]; then
                    file_date="${year}-${month}-${day}"
                    if [[ "$file_date" < "$cutoff_date" ]]; then
                        log_info "Deleting old backup: ${file_path}"
                        aws s3 rm "s3://${S3_BUCKET}/${file_path}" \
                            --endpoint-url "${S3_ENDPOINT}"
                    fi
                fi
            fi
        done
    done
}

# Main backup function
run_backup() {
    log_info "=========================================="
    log_info "Starting PostgreSQL backup process"
    log_info "=========================================="

    validate_env
    configure_s3

    # Parse comma-separated database list
    IFS=',' read -ra DATABASES <<< "${POSTGRES_DATABASES}"

    local success_count=0
    local fail_count=0

    for db in "${DATABASES[@]}"; do
        # Trim whitespace
        db=$(echo "${db}" | xargs)

        if [ -n "${db}" ]; then
            if backup_database "${db}"; then
                ((success_count++))
            else
                ((fail_count++))
            fi
        fi
    done

    log_info "=========================================="
    log_info "Backup process completed"
    log_info "Success: ${success_count}, Failed: ${fail_count}"
    log_info "=========================================="

    # Cleanup old backups
    cleanup_old_backups

    # Update health check timestamp
    date '+%Y-%m-%d %H:%M:%S' > /tmp/last_backup_time

    if [ ${fail_count} -gt 0 ]; then
        return 1
    fi

    return 0
}

# Run backup
run_backup
