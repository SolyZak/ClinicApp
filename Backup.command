#!/bin/bash

# Dr. Medhat Clinic - Backup Script
# Double-click this file to backup patient data

cd "$(dirname "$0")"

echo ""
echo "============================================"
echo "   Dr. Medhat - Database Backup"
echo "============================================"
echo ""

# Resolve database location:
# - App installs use ~/Library/Application Support/DrMedhatClinic/clinic.db
# - Script installs use ./data/clinic.db
APP_DATA_DB="$HOME/Library/Application Support/DrMedhatClinic/clinic.db"
LOCAL_DB="data/clinic.db"

if [ -f "$APP_DATA_DB" ]; then
    DB_PATH="$APP_DATA_DB"
elif [ -f "$LOCAL_DB" ]; then
    DB_PATH="$LOCAL_DB"
else
    echo "❌ No database found to backup."
    echo "   Start the system first to create a database."
    echo ""
    read -p "Press Enter to close..."
    exit 1
fi

# Choose destination folder (USB or any folder)
DEST_DIR=$(/usr/bin/osascript -e 'tell application "System Events" to choose folder with prompt "Select a folder to save the backup (USB drive is ok):"')
if [ -z "$DEST_DIR" ]; then
    echo "Backup cancelled."
    echo ""
    read -p "Press Enter to close..."
    exit 0
fi

# Create backup with timestamp
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_FILE="${DEST_DIR}clinic_backup_${TIMESTAMP}.db"

cp "$DB_PATH" "$BACKUP_FILE"

if [ -f "$BACKUP_FILE" ]; then
    echo "✓ Backup created successfully!"
    echo ""
    echo "  Location: $BACKUP_FILE"
    echo ""
else
    echo "❌ Backup failed!"
fi

echo ""
read -p "Press Enter to close..."
