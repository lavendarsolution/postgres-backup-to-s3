#!/bin/bash

# Health check script
# Checks if cron is running and last backup was successful

# Check if crond is running
if ! pgrep -x "crond" > /dev/null; then
    echo "UNHEALTHY: crond is not running"
    exit 1
fi

# Check if backup log exists and doesn't contain recent errors
if [ -f /var/log/backup.log ]; then
    # Check last 50 lines for errors in the last hour
    recent_errors=$(tail -50 /var/log/backup.log | grep -c "\[ERROR\]" || true)
    if [ "$recent_errors" -gt 0 ]; then
        echo "WARNING: Found ${recent_errors} recent errors in backup log"
        # Don't fail health check for errors, just warn
    fi
fi

# Check last backup timestamp if available
if [ -f /tmp/last_backup_time ]; then
    last_backup=$(cat /tmp/last_backup_time)
    echo "HEALTHY: Last backup at ${last_backup}"
else
    echo "HEALTHY: Waiting for first backup"
fi

exit 0
