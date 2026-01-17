#!/bin/bash

# ============================================================
# CLAUDE CONTEXT SYSTEM - GitHub Backup Script
# ============================================================

set -e

# Load environment variables
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

# Configuration
BACKUP_TYPE="${1:-data_only}"  # full, incremental, data_only
COMMIT_MESSAGE="${2:-Auto backup: $(date +'%Y-%m-%d %H:%M')}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}Claude Context System - GitHub Backup${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo ""
echo "Backup type: $BACKUP_TYPE"
echo "Started at: $(date)"
echo ""

# ============================================================
# STEP 1: Export database to SQL
# ============================================================

echo -e "${YELLOW}Step 1: Exporting database...${NC}"

# Create backup directory
BACKUP_DIR="./backups/github"
mkdir -p "$BACKUP_DIR"

# Generate timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/claude_context_${BACKUP_TYPE}_${TIMESTAMP}.sql"

# Export from PostgreSQL
echo "Connecting to database..."
docker exec candid-crm-staging-postgres-1 pg_dump -U candid claude_context > "$BACKUP_FILE"

if [ $? -eq 0 ]; then
    SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    echo -e "${GREEN}✓ Database exported: $BACKUP_FILE ($SIZE)${NC}"
else
    echo -e "${RED}✗ Database export failed${NC}"
    exit 1
fi
echo ""

# ============================================================
# STEP 2: Compress backup
# ============================================================

echo -e "${YELLOW}Step 2: Compressing backup...${NC}"

gzip "$BACKUP_FILE"
BACKUP_FILE="${BACKUP_FILE}.gz"
SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
echo -e "${GREEN}✓ Compressed: $BACKUP_FILE ($SIZE)${NC}"
echo ""

# ============================================================
# STEP 3: Commit to GitHub
# ============================================================

echo -e "${YELLOW}Step 3: Committing to GitHub...${NC}"

# Copy to repository
cp "$BACKUP_FILE" "./database-backups/"

# Add to git
git add ./database-backups/

# Check if there are changes
if git diff --cached --quiet; then
    echo "No new changes to commit"
else
    git commit -m "$COMMIT_MESSAGE

Backup type: $BACKUP_TYPE
File: $(basename $BACKUP_FILE)
Size: $SIZE"

    # Push to GitHub
    git push origin main

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Pushed to GitHub${NC}"
    else
        echo -e "${RED}✗ Git push failed${NC}"
        exit 1
    fi
fi
echo ""

# ============================================================
# STEP 4: Log backup in database
# ============================================================

echo -e "${YELLOW}Step 4: Logging backup...${NC}"

# Get commit hash
COMMIT_HASH=$(git rev-parse --short HEAD)

# Insert backup record
docker exec candid-crm-staging-postgres-1 psql -U candid -d claude_context -c "
INSERT INTO github_backups (backup_type, status, repo_owner, repo_name, branch, commit_hash, tables_included, started_at, completed_at, status_message)
VALUES ('$BACKUP_TYPE', 'completed', 'ryanmayiras', 'claude-context-system', 'main', '$COMMIT_HASH', ARRAY['all'], NOW(), NOW(), 'Backup successful: $SIZE')
ON CONFLICT DO NOTHING;"

echo -e "${GREEN}✓ Backup logged${NC}"
echo ""

# ============================================================
# STEP 5: Cleanup old backups
# ============================================================

echo -e "${YELLOW}Step 5: Cleaning up old backups...${NC}"

# Keep only last 10 backups
cd "./database-backups/"
ls -t claude_context_*.sql.gz | tail -n +11 | xargs -r rm --
cd ../

REMOVED=$(find ./database-backups/ -name "claude_context_*.sql.gz" | wc -l)
echo -e "${GREEN}✓ Kept last 10 backups ($REMOVED total)${NC}"
echo ""

# ============================================================
# COMPLETE
# ============================================================

echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ BACKUP COMPLETE${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
echo ""
echo "Backup file: $BACKUP_FILE"
echo "Size: $SIZE"
echo "GitHub: https://github.com/ryanmayiras/claude-context-system"
echo "Completed at: $(date)"
echo ""
