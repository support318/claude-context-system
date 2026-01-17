#!/bin/bash

# ============================================================
# CLAUDE CONTEXT SYSTEM - Server Setup Script
# ============================================================

set -e

echo "🚀 Setting up Claude Context System on server..."
echo ""

# Server configuration
SERVER_HOST="candid@192.168.40.100"
SERVER_DIR="/tank/services/claude-context"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ============================================================
# STEP 1: Create directory structure on server
# ============================================================

echo -e "${YELLOW}Step 1: Creating directory structure...${NC}"

ssh $SERVER_HOST "mkdir -p $SERVER_DIR/{database,mcp-server,backups,github}"

echo -e "${GREEN}✓ Directories created${NC}"
echo ""

# ============================================================
# STEP 2: Check PostgreSQL and create database
# ============================================================

echo -e "${YELLOW}Step 2: Setting up PostgreSQL database...${NC}"

# Check if PostgreSQL is running
echo "Checking PostgreSQL..."
ssh $SERVER_HOST "docker ps | grep postgres" || {
    echo -e "${RED}✗ PostgreSQL not found in Docker${NC}"
    echo "Please ensure PostgreSQL is running"
    exit 1
}

# Create database if it doesn't exist
echo "Creating claude_context database..."
ssh $SERVER_HOST "docker exec candid-crm-staging-postgres-1 psql -U candid -c \"SELECT 'CREATE DATABASE claude_context' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'claude_context') | psql -U candid\""

echo -e "${GREEN}✓ Database ready${NC}"
echo ""

# ============================================================
# STEP 3: Copy schema to server and apply
# ============================================================

echo -e "${YELLOW}Step 3: Applying database schema...${NC}"

# Copy schema file
scp schema.sql $SERVER_HOST:$SERVER_DIR/database/

# Apply schema (use existing PostgreSQL container)
echo "Applying schema..."
ssh $SERVER_HOST "docker exec -i candid-crm-staging-postgres-1 psql -U candid -d claude_context < $SERVER_DIR/database/schema.sql"

echo -e "${GREEN}✓ Schema applied${NC}"
echo ""

# ============================================================
# STEP 4: Set up GitHub repository
# ============================================================

echo -e "${YELLOW}Step 4: Setting up GitHub repository...${NC}"

echo "Checking for gh CLI..."
if command -v gh &> /dev/null; then
    echo "Creating GitHub repository..."
    gh repo create claude-context-system --public --source=$PWD --remote=origin --push || {
        echo "Repository might already exist, adding remote..."
        git remote -v | grep origin || git remote add origin git@github.com:ryanmayiras/claude-context-system.git
    }

    # Create .gitignore if not exists
    if [ ! -f .gitignore ]; then
        cat > .gitignore << 'EOF'
node_modules/
dist/
.env
*.log
.DS_Store
EOF
    fi

    echo -e "${GREEN}✓ GitHub repository configured${NC}"
else
    echo -e "${YELLOW}⚠ gh CLI not found. Please set up GitHub manually${NC}"
fi
echo ""

# ============================================================
# STEP 5: Set up MCP server
# ============================================================

echo -e "${YELLOW}Step 5: Setting up MCP server...${NC}"

# Copy MCP server files to local project (for development)
echo "Building MCP server..."
cd mcp-server
npm install
npm run build
cd ..

echo -e "${GREEN}✓ MCP server built${NC}"
echo ""

# ============================================================
# STEP 6: Create environment files
# ============================================================

echo -e "${YELLOW}Step 6: Creating configuration files...${NC}"

# Create .env file
cat > .env << EOF
# Database Configuration
DB_HOST=192.168.40.100
DB_PORT=5432
DB_NAME=claude_context
DB_USER=candid
DB_PASSWORD=Snoboard19

# GitHub Configuration
GITHUB_REPO_OWNER=ryanmayiras
GITHUB_REPO_NAME=claude-context-system
GITHUB_BRANCH=main

# Server Configuration
SERVER_HOST=192.168.40.100
SERVER_USER=candid
SERVER_DIR=/tank/services/claude-context
EOF

echo -e "${GREEN}✓ Configuration files created${NC}"
echo ""

# ============================================================
# STEP 7: Add MCP server to Claude Code
# ============================================================

echo -e "${YELLOW}Step 7: Registering MCP server with Claude Code...${NC}"

# Get absolute path to mcp-server
MCP_SERVER_PATH="$(pwd)/mcp-server"

echo "Adding MCP server to Claude Code config..."
claude mcp add-json claude-context --scope user "{
  \"command\": \"node\",
  \"args\": [\"$MCP_SERVER_PATH/dist/index.js\"],
  \"env\": {
    \"DB_HOST\": \"192.168.40.100\",
    \"DB_PORT\": \"5432\",
    \"DB_NAME\": \"claude_context\",
    \"DB_USER\": \"candid\",
    \"DB_PASSWORD\": \"Snoboard19\"
  }
}"

echo -e "${GREEN}✓ MCP server registered${NC}"
echo ""

# ============================================================
# STEP 8: Create initial backup to GitHub
# ============================================================

echo -e "${YELLOW}Step 8: Creating initial backup to GitHub...${NC}"

# Add all files and commit
git add .
git commit -m "Initial commit: Claude Context System

- Database schema with full context tracking
- MCP server for Claude Code integration
- Setup scripts and configuration
- GitHub backup integration" || echo "No changes to commit"

git push -u origin main || echo "Nothing to push or already up to date"

echo -e "${GREEN}✓ Initial backup complete${NC}"
echo ""

# ============================================================
# COMPLETE
# ============================================================

echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ SETUP COMPLETE!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
echo ""
echo "Next steps:"
echo ""
echo "1. Restart Claude Code to load the MCP server:"
echo "   - Exit current session (Ctrl+C)"
echo "   - Start new session: claude code"
echo ""
echo "2. Verify MCP server is loaded:"
echo "   claude mcp list"
echo "   Should show: claude-context: ✓ Connected"
echo ""
echo "3. Start using context tools:"
echo "   - session_start: Begin a new session with context"
echo "   - create_main_goal: Define your primary objective"
echo "   - get_active_main_goals: See what you're working on"
echo "   - session_end: Close session with summary"
echo ""
echo "4. GitHub repository:"
echo "   https://github.com/ryanmayiras/claude-context-system"
echo ""
echo "Database: claude_context on 192.168.40.100"
echo "MCP Server: $MCP_SERVER_PATH"
echo ""
