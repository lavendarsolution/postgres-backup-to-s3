# PostgreSQL Backup to S3

Automated PostgreSQL backup to S3-compatible storage (Digital Ocean Spaces, AWS S3, MinIO).

## Quick Start

### Option 1: Local PostgreSQL (Docker container)

```bash
# 1. Download
curl -O https://raw.githubusercontent.com/lavendarsolution/postgres-backup-to-s3/master/docker-compose.yml
curl -O https://raw.githubusercontent.com/lavendarsolution/postgres-backup-to-s3/master/.env.example

# 2. Configure
cp .env.example .env
nano .env   # Set POSTGRES_HOST=your_container_name, NETWORK_NAME=your_network

# 3. Run
docker-compose up -d
```

### Option 2: External PostgreSQL (online host, RDS, etc.)

```bash
# 1. Download
curl -O https://raw.githubusercontent.com/lavendarsolution/postgres-backup-to-s3/master/docker-compose.external.yml
curl -O https://raw.githubusercontent.com/lavendarsolution/postgres-backup-to-s3/master/.env.example

# 2. Configure
cp .env.example .env
nano .env   # Set POSTGRES_HOST=db.example.com or IP address

# 3. Run
docker-compose -f docker-compose.external.yml up -d
```

## Configuration (.env)

```bash
# PostgreSQL
POSTGRES_HOST=postgres          # Container name OR external host (db.example.com)
POSTGRES_PORT=5432
POSTGRES_USER=postgres
POSTGRES_PASSWORD=your_password
POSTGRES_DATABASES=db1,db2,db3  # Comma-separated

# S3 / Digital Ocean Spaces
S3_ENDPOINT=https://nyc3.digitaloceanspaces.com
S3_BUCKET=my-bucket
S3_ACCESS_KEY=your_access_key
S3_SECRET_KEY=your_secret_key
S3_PREFIX=backups

# Schedule (default: every 2 hours)
BACKUP_SCHEDULE=0 */2 * * *

# Retention (0=unlimited)
BACKUP_RETENTION_DAYS=30

# Run backup on start
BACKUP_ON_START=true

# Network (only for local Docker PostgreSQL)
NETWORK_NAME=myapp_default
```

## Backup Structure

```
s3://bucket/backups/
├── db1/
│   └── 2025/11/27/
│       ├── 00-00.sql.gz
│       ├── 02-00.sql.gz
│       └── ...
└── db2/
    └── ...
```

## Restore

```bash
# Download and restore
aws s3 cp s3://bucket/backups/db1/2025/11/27/02-00.sql.gz - \
    --endpoint-url https://nyc3.digitaloceanspaces.com \
    | gunzip | psql -h localhost -U postgres -d db1
```
## Commands

```bash
# View logs
docker logs -f pg-backup

# Manual backup
docker exec pg-backup /scripts/backup.sh

# Validate configuration
docker exec pg-backup /scripts/validate.sh
```

## License

MIT
